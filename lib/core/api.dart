import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'models.dart';
import 'response_cache.dart';
import 'token_store.dart';

abstract class AppRepository {
  Future<Json> envelope(
    String path, {
    String method = 'GET',
    Object? body,
    Json? query,
    bool authenticated = true,
    CancelToken? cancel,
  });
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Object? body,
    Json? query,
    bool authenticated = true,
    CancelToken? cancel,
  });
  Future<ApiPage> page(String path, {Json? query, CancelToken? cancel});
  Future<Json> upload(
    String path, {
    String? fileName,
    void Function(int, int)? progress,
    String endpoint = 'media/upload',
  });
}

class DioRepository implements AppRepository {
  DioRepository({
    required String baseUrl,
    required this.store,
    Dio? client,
    Dio? storageClient,
  }) : storage =
           storageClient ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 15),
               receiveTimeout: const Duration(seconds: 30),
               sendTimeout: const Duration(minutes: 5),
             ),
           ),
       dio =
           client ??
           Dio(
             BaseOptions(
               baseUrl: '$baseUrl/',
               connectTimeout: const Duration(seconds: 15),
               receiveTimeout: const Duration(seconds: 30),
               sendTimeout: const Duration(seconds: 60),
             ),
           ) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.extra['authenticated'] != false &&
              session?['accessToken'] is String) {
            options.headers['Authorization'] =
                'Bearer ${session!['accessToken']}';
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          final options = error.requestOptions;
          if (error.response?.statusCode == 401 &&
              options.extra['authenticated'] != false &&
              options.extra['retried'] != true &&
              session != null) {
            try {
              await refreshSession();
              options.extra['retried'] = true;
              options.headers['Authorization'] =
                  'Bearer ${session!['accessToken']}';
              // A multipart stream cannot be replayed. Ask the user to upload again.
              if (options.data is FormData) {
                handler.next(error);
                return;
              }
              handler.resolve(await dio.fetch(options));
              return;
            } catch (_) {
              handler.next(error);
              return;
            }
          }
          handler.next(error);
        },
      ),
    );
  }
  final Dio dio;

  /// Direct uploads to storage (Task 02). It has no interceptors, so the
  /// session token is never sent to storage.
  final Dio storage;

  /// Task 13: short-lived cache of public reads (see [ResponseCache]).
  final cache = ResponseCache();
  final SessionStore store;
  Json? session;
  Future<void>? _refresh;
  int _generation = 0;
  final expired = StreamController<void>.broadcast();
  final tokensChanged = StreamController<void>.broadcast();
  Future<void> restore() async => session = await store.read();
  Future<void> saveSession(Json value) async {
    final tokenChanged = session?['accessToken'] != value['accessToken'];
    if (tokenChanged) cache.clear(); // never across accounts or sessions
    await store.write(value);
    session = value;
    _generation++;
    if (tokenChanged) tokensChanged.add(null);
  }

  Future<void> clearSession() async {
    cache.clear();
    _generation++;
    session = null;
    await store.clear();
    tokensChanged.add(null);
    expired.add(null);
  }

  /// No refresh request before this time after a rate-limited refresh (F-26).
  DateTime? _refreshBlockedUntil;

  Future<void> refreshSession() {
    final blocked = _refreshBlockedUntil;
    if (blocked != null && DateTime.now().isBefore(blocked)) {
      // Keep the session; callers back off (no immediate retry, no loop).
      return Future.error(
        const AppFailure(
          'Too many session refreshes. Please try again shortly.',
          code: 'RATE_LIMITED',
          status: 429,
        ),
      );
    }
    return _refresh ??= _refreshOnce().whenComplete(() => _refresh = null);
  }

  Future<void> _refreshOnce() async {
    final generation = _generation;
    try {
      final result = asJson(
        await request(
          'auth/refresh',
          method: 'POST',
          body: {'refreshToken': session?['refreshToken']},
          authenticated: false,
        ),
      );
      if (generation != _generation || session == null) {
        throw const AppFailure('Your session changed. Please sign in again.');
      }
      await saveSession({...session!, ...result});
    } on AppFailure catch (error) {
      if (generation == _generation && [400, 401, 403].contains(error.status)) {
        await clearSession();
      }
      if (error.status == 429) {
        // Honour Retry-After (bounded to 5 minutes; 30 s if absent).
        final wait = error.retryAfter ?? const Duration(seconds: 30);
        _refreshBlockedUntil = DateTime.now().add(
          wait > const Duration(minutes: 5) ? const Duration(minutes: 5) : wait,
        );
      }
      rethrow;
    }
  }

  @override
  Future<Json> envelope(
    String path, {
    String method = 'GET',
    Object? body,
    Json? query,
    bool authenticated = true,
    CancelToken? cancel,
    bool cached = false,
  }) async {
    final cacheKey = method == 'GET' && ResponseCache.cacheable(path, query)
        ? ResponseCache.keyFor(path, query)
        : null;
    if (cached && cacheKey != null) {
      final hit = cache.get(cacheKey);
      if (hit != null) return hit;
    }
    final generation = _generation;
    try {
      final response = await dio.request(
        path,
        data: body,
        queryParameters: query,
        options: Options(
          method: method,
          extra: {'authenticated': authenticated},
        ),
        cancelToken: cancel,
      );
      final result = asJson(response.data);
      if (result['success'] == false) {
        throw AppFailure(
          asJson(result['error'])['message']?.toString() ??
              'Could not complete this request.',
        );
      }
      if (method != 'GET') {
        cache.clear(); // a write may change any cached read
      } else if (cacheKey != null && generation == _generation) {
        cache.put(cacheKey, result);
      }
      return result;
    } on DioException catch (error) {
      throw _failure(error);
    }
  }

  static AppFailure _failure(DioException error) {
    if (CancelToken.isCancel(error)) {
      return const AppFailure('Request canceled.', code: 'CANCELED');
    }
    final detail = asJson(asJson(error.response?.data)['error']);
    return AppFailure(
      detail['message']?.toString() ??
          (error.response == null
              ? 'Cannot reach TWON. Check your connection and try again.'
              : 'Could not complete this request. Please try again.'),
      code: detail['code']?.toString() ?? '',
      status: error.response?.statusCode,
      retryAfter: _retryAfter(error.response?.headers),
    );
  }

  static Duration? _retryAfter(Headers? headers) {
    final seconds = int.tryParse(headers?.value('retry-after') ?? '');
    return seconds != null && seconds > 0 ? Duration(seconds: seconds) : null;
  }

  @override
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Object? body,
    Json? query,
    bool authenticated = true,
    CancelToken? cancel,
    bool cached = false,
  }) async => (await envelope(
    path,
    method: method,
    body: body,
    query: query,
    authenticated: authenticated,
    cancel: cancel,
    cached: cached,
  ))['data'];
  @override
  Future<ApiPage> page(
    String path, {
    Json? query,
    CancelToken? cancel,
    bool cached = false,
  }) async => ApiPage.fromEnvelope(
    await envelope(path, query: query, cancel: cancel, cached: cached),
  );

  /// Media uploads use direct uploads (Task 02) when the server supports
  /// them: a session, the file sent straight to private storage, then
  /// finalization with polling. The result is the same as `media/upload`.
  /// Other endpoints (private verification uploads), file types the direct
  /// flow does not accept, and servers without direct uploads use the
  /// multipart endpoint unchanged. Once a file has been sent, failures are
  /// reported and never retried through the legacy endpoint.
  @override
  Future<Json> upload(
    String path, {
    String? fileName,
    void Function(int, int)? progress,
    String endpoint = 'media/upload',
    CancelToken? cancel,
  }) async {
    final name = fileName ?? path.split(RegExp(r'[/\\]')).last;
    final type = endpoint == 'media/upload'
        ? _directTypes[name.split('.').last.toLowerCase()]
        : null;
    final unavailable = _directUnavailableUntil;
    if (type == null || (unavailable != null && now().isBefore(unavailable))) {
      return _legacyUpload(
        path,
        fileName: fileName,
        progress: progress,
        endpoint: endpoint,
        cancel: cancel,
      );
    }
    final size = await File(path).length();
    for (var restarts = 0; ; restarts++) {
      Json session;
      try {
        session = asJson(
          await request(
            'media/uploads',
            method: 'POST',
            body: {
              'kind': type.$1,
              'size': size,
              'contentType': type.$2,
              'fileName': name.length > 255 ? name.substring(0, 255) : name,
            },
            cancel: cancel,
          ),
        );
      } on AppFailure catch (error) {
        final off =
            error.status == 404 ||
            (error.status == 503 && error.code == 'DIRECT_UPLOADS_UNAVAILABLE');
        if (restarts == 0 && off) {
          _directUnavailableUntil = now().add(const Duration(minutes: 5));
          return _legacyUpload(
            path,
            fileName: fileName,
            progress: progress,
            endpoint: endpoint,
            cancel: cancel,
          );
        }
        rethrow;
      }
      final id = session['uploadId'];
      final target = asJson(session['upload']);
      final url = target['url'];
      if (id is! String || url is! String || target['method'] != 'POST') {
        throw const AppFailure(
          'Upload failed. Please select the file again.',
          code: 'UPLOAD_FAILED',
        );
      }
      final fields = asJson(target['fields']);
      // Local staging (SEC-017) repeats its token in a header so the API can
      // check it before reading the body. S3 instructions carry none.
      final headers = <String, String>{
        for (final entry in asJson(target['headers']).entries)
          entry.key: '${entry.value}',
      };
      if (await _sendToStorage(
        url,
        fields,
        headers,
        path,
        name,
        type.$2,
        progress,
        cancel,
      )) {
        return _finalizeUpload(id, cancel);
      }
      if (restarts >= 1) {
        throw const AppFailure(
          'The upload link expired. Please try again.',
          code: 'UPLOAD_EXPIRED',
          status: 410,
        );
      }
    }
  }

  /// Extension → (kind, declared type) accepted by direct uploads (backend `DECLARED_TYPES`).
  static const _directTypes = <String, (String, String)>{
    'jpg': ('image', 'image/jpeg'),
    'jpeg': ('image', 'image/jpeg'),
    'png': ('image', 'image/png'),
    'webp': ('image', 'image/webp'),
    'gif': ('image', 'image/gif'),
    'mp4': ('video', 'video/mp4'),
    'mov': ('video', 'video/quicktime'),
    'webm': ('video', 'video/webm'),
    'm4a': ('audio', 'audio/mp4'),
    'aac': ('audio', 'audio/aac'),
    'pdf': ('document', 'application/pdf'),
    'docx': (
      'document',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    ),
    'xlsx': (
      'document',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    ),
    'pptx': (
      'document',
      'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    ),
    'zip': ('document', 'application/zip'),
    'rar': ('document', 'application/vnd.rar'),
    'doc': ('document', 'application/msword'),
    'xls': ('document', 'application/vnd.ms-excel'),
    'ppt': ('document', 'application/vnd.ms-powerpoint'),
    'txt': ('document', 'text/plain'),
    'csv': ('document', 'text/csv'),
  };

  /// Skip the direct flow until then after the server said it is unavailable.
  DateTime? _directUnavailableUntil;

  /// Test seams for upload retry pacing.
  @visibleForTesting
  Future<void> Function(Duration) sleep = (d) => Future<void>.delayed(d);
  @visibleForTesting
  DateTime Function() now = DateTime.now;

  Future<void> _wait(Duration duration, CancelToken? cancel) async {
    if (cancel == null) return sleep(duration);
    await Future.any([sleep(duration), cancel.whenCancel]);
    if (cancel.isCancelled) {
      throw const AppFailure('Request canceled.', code: 'CANCELED');
    }
  }

  /// Sends the storage form (no Authorization header, no interceptors).
  /// Returns false when the link expired (start a new session).
  Future<bool> _sendToStorage(
    String url,
    Json fields,
    Map<String, String> headers,
    String path,
    String name,
    String contentType,
    void Function(int, int)? progress,
    CancelToken? cancel,
  ) async {
    for (var attempt = 1; ; attempt++) {
      var status = 0;
      try {
        final response = await storage.post<void>(
          url,
          // Rebuilt for every attempt (a multipart stream cannot be replayed); the file is last.
          data: FormData.fromMap({
            for (final entry in fields.entries) entry.key: '${entry.value}',
            'file': await MultipartFile.fromFile(
              path,
              filename: name,
              contentType: DioMediaType.parse(contentType),
            ),
          }),
          onSendProgress: progress,
          cancelToken: cancel,
          options: Options(
            headers: headers,
            validateStatus: (_) => true,
            responseType: ResponseType.plain,
          ),
        );
        status = response.statusCode ?? 0;
      } on DioException catch (error) {
        if (CancelToken.isCancel(error)) {
          throw const AppFailure('Request canceled.', code: 'CANCELED');
        }
      }
      if (status >= 200 && status < 300) return true;
      if (status == 403 || status == 410) return false;
      if (status == 400 || status == 413 || status == 415) {
        throw AppFailure(
          'The file was rejected. Check its type and size.',
          code: 'UPLOAD_REJECTED',
          status: status,
        );
      }
      // Network failures, 409 (a previous attempt is still being written), 429 and 5xx.
      if (attempt >= 3) {
        throw const AppFailure(
          'Upload failed. Please try again.',
          code: 'UPLOAD_FAILED',
          status: 503,
        );
      }
      await _wait(Duration(seconds: 1 << (attempt - 1)), cancel);
    }
  }

  /// Calls complete until the upload is processed (202 → wait Retry-After).
  Future<Json> _finalizeUpload(String id, CancelToken? cancel) async {
    final deadline = now().add(const Duration(minutes: 15));
    var transient = 0;
    var changed = 0;
    while (true) {
      Duration wait;
      try {
        final response = await dio.post<dynamic>(
          'media/uploads/${Uri.encodeComponent(id)}/complete',
          cancelToken: cancel,
        );
        final data = asJson(asJson(response.data)['data']);
        if (data['status'] == 'completed' && data['result'] is Map) {
          return asJson(data['result']);
        }
        transient = 0;
        wait = _retryAfter(response.headers) ?? const Duration(seconds: 2);
      } on DioException catch (error) {
        final failure = _failure(error);
        if (failure.code == 'CANCELED') throw failure;
        final status = failure.status;
        if (status == 409 &&
            (failure.code == 'UPLOAD_CHANGED' ||
                failure.code == 'UPLOAD_NOT_RECEIVED') &&
            ++changed <= 3) {
          wait = const Duration(seconds: 1);
        } else if ([null, 408, 429, 502, 503, 504].contains(status) &&
            ++transient <= 5) {
          wait = failure.retryAfter ?? Duration(seconds: 1 << transient);
        } else {
          throw failure;
        }
      }
      if (wait < const Duration(seconds: 1)) {
        wait = const Duration(seconds: 1);
      } else if (wait > const Duration(seconds: 30)) {
        wait = const Duration(seconds: 30);
      }
      if (now().add(wait).isAfter(deadline)) {
        throw const AppFailure(
          'Processing is taking longer than expected. Please try again later.',
          code: 'UPLOAD_TIMEOUT',
          status: 504,
        );
      }
      await _wait(wait, cancel);
    }
  }

  Future<Json> _legacyUpload(
    String path, {
    String? fileName,
    void Function(int, int)? progress,
    String endpoint = 'media/upload',
    CancelToken? cancel,
  }) async {
    try {
      final response = await dio.post(
        endpoint,
        data: FormData.fromMap({
          'file': await MultipartFile.fromFile(
            path,
            filename: fileName,
            contentType: switch ((fileName ?? path)
                .split('.')
                .last
                .toLowerCase()) {
              'jpg' || 'jpeg' => DioMediaType.parse('image/jpeg'),
              'png' => DioMediaType.parse('image/png'),
              'webp' => DioMediaType.parse('image/webp'),
              'gif' => DioMediaType.parse('image/gif'),
              _ => null,
            },
          ),
        }),
        onSendProgress: progress,
        cancelToken: cancel,
      );
      return asJson(asJson(response.data)['data']);
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) {
        throw const AppFailure('Request canceled.', code: 'CANCELED');
      }
      throw AppFailure(
        asJson(asJson(error.response?.data)['error'])['message']?.toString() ??
            'Upload failed. Please select the file again.',
      );
    }
  }
}
