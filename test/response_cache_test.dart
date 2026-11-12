import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twon_mobile/core/api.dart';
import 'package:twon_mobile/core/response_cache.dart';
import 'api_session_test.dart' show ApiAdapter, MemoryStore;

/// Task 13: bounded, account-partitioned cache of public reads.
ResponseBody ok(Object? data) => ResponseBody.fromString(
  jsonEncode({'success': true, 'data': data}),
  200,
  headers: {
    Headers.contentTypeHeader: ['application/json'],
  },
);

void main() {
  test('allowlists public reads only, never cursor pages', () {
    expect(ResponseCache.cacheable('users/bob', null), isTrue);
    expect(
      ResponseCache.cacheable('posts/65f0000000000000000000aa', null),
      isTrue,
    );
    expect(ResponseCache.cacheable('posts', {'limit': 20}), isTrue);
    for (final path in [
      'users/me',
      'verification/status',
      'notifications',
      'conversations',
      'auth/refresh',
      'users/me/sessions',
    ]) {
      expect(ResponseCache.cacheable(path, null), isFalse, reason: path);
    }
    expect(ResponseCache.cacheable('posts', {'cursor': 'x'}), isFalse);
  });

  test('expires after the TTL and keeps a bounded number of entries', () {
    var now = DateTime(2026);
    final cache = ResponseCache(maxEntries: 3, clock: () => now);
    for (var i = 0; i < 5; i++) {
      cache.put('k$i', {'i': i});
    }
    expect(cache.length, 3);
    expect(cache.get('k0'), isNull); // least recently used dropped
    expect(cache.get('k4'), {'i': 4});
    now = now.add(const Duration(seconds: 31));
    expect(cache.get('k4'), isNull); // expired
  });

  test(
    'reuses a fresh profile, refreshes on demand, and is cleared by writes and session changes',
    () async {
      final api = DioRepository(
        baseUrl: 'https://test.invalid/api/v1',
        store: MemoryStore(),
      );
      await api.saveSession({
        'accessToken': 'a1',
        'refreshToken': 'r1',
        'user': {'id': 'A'},
      });
      final calls = <String>[];
      api.dio.httpClientAdapter = ApiAdapter((r) async {
        calls.add('${r.method} ${r.path}');
        return ok({'id': 'bob', 'n': calls.length});
      });
      await api.request('users/bob', cached: true);
      await api.request('users/bob', cached: true);
      expect(calls, ['GET users/bob']); // revisited: no request
      await api.request(
        'users/bob',
      ); // pull-to-refresh: always fetched, cache updated
      await api.request('users/me', cached: true);
      await api.request('users/me', cached: true);
      expect(
        calls.where((c) => c == 'GET users/me'),
        hasLength(2),
      ); // never cached
      await api.request('users/bob/follow', method: 'POST');
      await api.request('users/bob', cached: true);
      expect(
        calls.where((c) => c == 'GET users/bob'),
        hasLength(3),
      ); // a write cleared it
      await api.saveSession({
        'accessToken': 'b1',
        'refreshToken': 'r2',
        'user': {'id': 'B'},
      });
      expect(api.cache.length, 0); // another account starts empty
      await api.clearSession();
      expect(api.cache.length, 0);
    },
  );

  test(
    "a response that arrives after the account changed is not cached for the new account",
    () async {
      final api = DioRepository(
        baseUrl: 'https://test.invalid/api/v1',
        store: MemoryStore(),
      );
      await api.saveSession({'accessToken': 'a1', 'refreshToken': 'r1'});
      final gate = Completer<void>();
      api.dio.httpClientAdapter = ApiAdapter((r) async {
        await gate.future;
        return ok({'id': 'bob'});
      });
      final pending = api.request('users/bob', cached: true);
      await api.saveSession({'accessToken': 'b1', 'refreshToken': 'r2'});
      gate.complete();
      await pending;
      expect(api.cache.length, 0);
    },
  );
}
