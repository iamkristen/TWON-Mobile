import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twon_mobile/core/api.dart';
import 'package:twon_mobile/core/models.dart';
import 'api_session_test.dart' show ApiAdapter, MemoryStore;

/// Task 02-C: media uploads use direct uploads (session → storage POST →
/// complete → poll) when the server supports them, the multipart endpoint
/// otherwise; verification uploads are unchanged.

const result = {
  'url': 'https://cdn/x.webp',
  'key': 'images/u/x.webp',
  'size': 10,
  'mimeType': 'image/webp',
};
const session = {
  'uploadId': 'u1',
  'upload': {
    'method': 'POST',
    'url': 'https://staging.s3.test/',
    'fields': {
      'key': 'incoming/a/u1',
      'Content-Type': 'image/jpeg',
      'Policy': 'p',
    },
  },
};

ResponseBody reply(
  int status,
  Object? data, {
  Map<String, String> headers = const {},
  bool success = true,
}) => ResponseBody.fromString(
  jsonEncode(
    success
        ? {'success': true, 'data': data}
        : {'success': false, 'error': data},
  ),
  status,
  headers: {
    Headers.contentTypeHeader: ['application/json'],
    for (final h in headers.entries) h.key: [h.value],
  },
);

class Rig {
  Rig(this.apiReplies, {List<int>? storageReplies})
    : storageReplies = storageReplies ?? [] {
    api = DioRepository(
      baseUrl: 'https://test.invalid/api/v1',
      store: MemoryStore(),
    );
    api.session = {'accessToken': 'app-jwt', 'refreshToken': 'r'};
    api.dio.httpClientAdapter = ApiAdapter((r) async {
      apiCalls.add(r);
      if (apiReplies.isEmpty) throw StateError('unexpected API call ${r.path}');
      return apiReplies.removeAt(0);
    });
    api.storage.httpClientAdapter = ApiAdapter((r) async {
      storageCalls.add(r);
      final status = this.storageReplies.isEmpty
          ? 204
          : this.storageReplies.removeAt(0);
      return ResponseBody.fromString('', status);
    });
    api.sleep = (d) async => sleeps.add(d);
  }
  final List<ResponseBody> apiReplies;
  final List<int> storageReplies;
  late final DioRepository api;
  final apiCalls = <RequestOptions>[];
  final storageCalls = <RequestOptions>[];
  final sleeps = <Duration>[];
}

void main() {
  late Directory dir;
  late String photo;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('twon-direct-');
    photo = '${dir.path}/a.jpg';
    File(photo).writeAsBytesSync(List.filled(10, 1));
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test(
    'uploads directly, never sends the app token to storage, and polls on 202',
    () async {
      final rig = Rig([
        reply(201, session),
        reply(202, {'status': 'processing'}, headers: {'retry-after': '3'}),
        reply(200, {'status': 'completed', 'result': result}),
      ]);
      expect(await rig.api.upload(photo), result);
      expect(rig.apiCalls.map((r) => r.path), [
        'media/uploads',
        'media/uploads/u1/complete',
        'media/uploads/u1/complete',
      ]);
      expect(rig.apiCalls.first.data, {
        'kind': 'image',
        'size': 10,
        'contentType': 'image/jpeg',
        'fileName': 'a.jpg',
      });
      for (final call in rig.apiCalls) {
        expect(call.headers['Authorization'], 'Bearer app-jwt');
      }
      expect(rig.storageCalls, hasLength(1));
      final storage = rig.storageCalls.single;
      expect(storage.uri.toString(), 'https://staging.s3.test/');
      expect(
        storage.headers.keys.map((k) => k.toLowerCase()),
        isNot(contains('authorization')),
      );
      expect(jsonEncode(storage.headers), isNot(contains('app-jwt')));
      final form = storage.data as FormData;
      expect(form.fields.map((f) => f.key), ['key', 'Content-Type', 'Policy']);
      expect(form.fields.map((f) => f.value), isNot(contains('app-jwt')));
      expect(form.files.single.key, 'file');
      expect(rig.sleeps, [const Duration(seconds: 3)]);
    },
  );

  test(
    'SEC-017: sends the local-staging token header from the session, never the app token',
    () async {
      final local = {
        'uploadId': 'u1',
        'upload': {
          'method': 'POST',
          'url': 'https://test.invalid/api/v1/media/uploads/u1/local',
          'fields': {'token': 'tok', 'Content-Type': 'image/jpeg'},
          'headers': {'X-Upload-Token': 'tok'},
        },
      };
      final rig = Rig([
        reply(201, local),
        reply(200, {'status': 'completed', 'result': result}),
      ]);
      expect(await rig.api.upload(photo), result);
      final storage = rig.storageCalls.single;
      expect(storage.headers['X-Upload-Token'], 'tok');
      expect(
        storage.headers.keys.map((k) => k.toLowerCase()),
        isNot(contains('authorization')),
      );
      expect(jsonEncode(storage.headers), isNot(contains('app-jwt')));
    },
  );

  test(
    'falls back to the multipart endpoint only when direct uploads are disabled, and remembers it',
    () async {
      final rig = Rig([
        reply(404, {
          'code': 'NOT_FOUND',
          'message': 'Not found',
        }, success: false),
        reply(201, result),
        reply(201, result),
      ]);
      expect(await rig.api.upload(photo), result);
      expect(await rig.api.upload(photo), result);
      expect(rig.apiCalls.map((r) => r.path), [
        'media/uploads',
        'media/upload',
        'media/upload',
      ]);
      expect(rig.apiCalls[1].data, isA<FormData>());
      expect(rig.storageCalls, isEmpty);
    },
  );

  test(
    'verification uploads and unsupported types keep the multipart endpoint',
    () async {
      final rig = Rig([
        reply(201, {'ref': 'verification/x'}),
        reply(201, result),
      ]);
      await rig.api.upload(photo, endpoint: 'verification/uploads');
      final other = '${dir.path}/a.heic';
      File(other).writeAsBytesSync([1]);
      await rig.api.upload(other);
      expect(rig.apiCalls.map((r) => r.path), [
        'verification/uploads',
        'media/upload',
      ]);
      expect(rig.storageCalls, isEmpty);
    },
  );

  test(
    'reports a rejection after the file was sent instead of re-uploading',
    () async {
      final rig = Rig([
        reply(201, session),
        reply(415, {
          'code': 'UNSUPPORTED_MEDIA_TYPE',
          'message': 'Not supported',
        }, success: false),
      ]);
      await expectLater(
        rig.api.upload(photo),
        throwsA(isA<AppFailure>().having((f) => f.status, 'status', 415)),
      );
      expect(rig.apiCalls.map((r) => r.path), [
        'media/uploads',
        'media/uploads/u1/complete',
      ]);
    },
  );

  test(
    'retries transient failures and starts one new session after an expired link',
    () async {
      final rig = Rig(
        [
          reply(201, session),
          reply(201, {...session, 'uploadId': 'u2'}),
          reply(
            503,
            {'code': 'MEDIA_BUSY', 'message': 'Busy'},
            headers: {'retry-after': '4'},
            success: false,
          ),
          reply(409, {
            'code': 'UPLOAD_CHANGED',
            'message': 'Changed',
          }, success: false),
          reply(200, {'status': 'completed', 'result': result}),
        ],
        storageReplies: [403, 0, 204],
      );
      expect(await rig.api.upload(photo), result);
      expect(rig.apiCalls.map((r) => r.path), [
        'media/uploads',
        'media/uploads',
        'media/uploads/u2/complete',
        'media/uploads/u2/complete',
        'media/uploads/u2/complete',
      ]);
      expect(rig.storageCalls, hasLength(3));
      expect(rig.sleeps, [
        const Duration(seconds: 1),
        const Duration(seconds: 4),
        const Duration(seconds: 1),
      ]);
    },
  );

  test('cancellation stops polling', () async {
    final cancel = CancelToken();
    final rig = Rig([
      reply(201, session),
      reply(202, {'status': 'processing'}),
    ]);
    rig.api.sleep = (_) {
      cancel.cancel();
      return Future<void>.delayed(const Duration(seconds: 1));
    };
    await expectLater(
      rig.api.upload(photo, cancel: cancel),
      throwsA(isA<AppFailure>().having((f) => f.code, 'code', 'CANCELED')),
    );
    expect(rig.apiCalls, hasLength(2));
  });
}
