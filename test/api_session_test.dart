import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twon_mobile/core/api.dart';
import 'package:twon_mobile/core/models.dart';
import 'package:twon_mobile/core/token_store.dart';

class MemoryStore implements SessionStore {
  Json? value;
  @override
  Future<Json?> read() async => value;
  @override
  Future<void> write(Json session) async {
    value = session;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

class ApiAdapter implements HttpClientAdapter {
  ApiAdapter(this.respond);
  final Future<ResponseBody> Function(RequestOptions) respond;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => respond(options);
  @override
  void close({bool force = false}) {}
}

ResponseBody response(int status, Json body) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: ['application/json'],
  },
);
void main() {
  test(
    'parallel expired requests share one token refresh and retry with the new token',
    () async {
      var refreshes = 0;
      final store = MemoryStore();
      final api = DioRepository(
        baseUrl: 'https://test.invalid/api/v1',
        store: store,
      );
      api.dio.httpClientAdapter = ApiAdapter((r) async {
        if (r.path == 'auth/refresh') {
          refreshes++;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          expect(r.headers['Authorization'], isNull);
          return response(200, {
            'success': true,
            'data': {'accessToken': 'new', 'refreshToken': 'new-refresh'},
          });
        }
        if (r.headers['Authorization'] == 'Bearer old') {
          return response(401, {
            'success': false,
            'error': {'message': 'Expired'},
          });
        }
        expect(r.headers['Authorization'], 'Bearer new');
        return response(200, {
          'success': true,
          'data': {'path': r.path},
        });
      });
      await api.saveSession({
        'accessToken': 'old',
        'refreshToken': 'old-refresh',
        'user': {'id': 'buyer'},
      });
      final result = await Future.wait([
        api.request('users/me'),
        api.request('merch/basket'),
      ]);
      expect(result.length, 2);
      expect(refreshes, 1);
      expect(store.value!['refreshToken'], 'new-refresh');
      expect(store.value!['user']['id'], 'buyer');
      api.dio.close();
      await api.expired.close();
      await api.tokensChanged.close();
    },
  );
  test('invalid refresh signs out and removes saved credentials', () async {
    final store = MemoryStore();
    final api = DioRepository(baseUrl: 'https://test.invalid', store: store);
    api.dio.httpClientAdapter = ApiAdapter(
      (_) async => response(401, {
        'success': false,
        'error': {'message': 'Sign in again'},
      }),
    );
    await api.saveSession({'accessToken': 'old', 'refreshToken': 'revoked'});
    await expectLater(api.request('users/me'), throwsA(isA<AppFailure>()));
    expect(api.session, isNull);
    expect(store.value, isNull);
    api.dio.close();
    await api.expired.close();
    await api.tokensChanged.close();
  });
  test('temporary backend refresh failure keeps the stored session', () async {
    final store = MemoryStore();
    final api = DioRepository(baseUrl: 'https://test.invalid', store: store);
    api.dio.httpClientAdapter = ApiAdapter(
      (r) async => response(r.path == 'auth/refresh' ? 503 : 401, {
        'success': false,
        'error': {'message': 'Try later'},
      }),
    );
    await api.saveSession({'accessToken': 'old', 'refreshToken': 'valid'});
    await expectLater(api.request('users/me'), throwsA(isA<AppFailure>()));
    expect(store.value!['refreshToken'], 'valid');
    api.dio.close();
    await api.expired.close();
    await api.tokensChanged.close();
  });
}
