import 'dart:async';
import 'package:dio/dio.dart';
import 'models.dart';
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
  });
}

class DioRepository implements AppRepository {
  DioRepository({required String baseUrl, required this.store, Dio? client})
    : dio =
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
  final SessionStore store;
  Json? session;
  Future<void>? _refresh;
  int _generation = 0;
  final expired = StreamController<void>.broadcast();
  final tokensChanged = StreamController<void>.broadcast();
  Future<void> restore() async => session = await store.read();
  Future<void> saveSession(Json value) async {
    final tokenChanged = session?['accessToken'] != value['accessToken'];
    await store.write(value);
    session = value;
    _generation++;
    if (tokenChanged) tokensChanged.add(null);
  }

  Future<void> clearSession() async {
    _generation++;
    session = null;
    await store.clear();
    tokensChanged.add(null);
    expired.add(null);
  }

  Future<void> refreshSession() =>
      _refresh ??= _refreshOnce().whenComplete(() => _refresh = null);
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
  }) async {
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
      return result;
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) {
        throw const AppFailure('Request canceled.', code: 'CANCELED');
      }
      final detail = asJson(asJson(error.response?.data)['error']);
      throw AppFailure(
        detail['message']?.toString() ??
            (error.response == null
                ? 'Cannot reach TWON. Check your connection and try again.'
                : 'Could not complete this request. Please try again.'),
        code: detail['code']?.toString() ?? '',
        status: error.response?.statusCode,
      );
    }
  }

  @override
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Object? body,
    Json? query,
    bool authenticated = true,
    CancelToken? cancel,
  }) async => (await envelope(
    path,
    method: method,
    body: body,
    query: query,
    authenticated: authenticated,
    cancel: cancel,
  ))['data'];
  @override
  Future<ApiPage> page(String path, {Json? query, CancelToken? cancel}) async =>
      ApiPage.fromEnvelope(await envelope(path, query: query, cancel: cancel));
  @override
  Future<Json> upload(
    String path, {
    String? fileName,
    void Function(int, int)? progress,
  }) async {
    try {
      final response = await dio.post(
        'media/upload',
        data: FormData.fromMap({
          'file': await MultipartFile.fromFile(path, filename: fileName),
        }),
        onSendProgress: progress,
      );
      return asJson(asJson(response.data)['data']);
    } on DioException catch (error) {
      throw AppFailure(
        asJson(asJson(error.response?.data)['error'])['message']?.toString() ??
            'Upload failed. Please select the file again.',
      );
    }
  }
}
