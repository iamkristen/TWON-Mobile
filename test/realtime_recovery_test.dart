import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:twon_mobile/core/api.dart';
import 'package:twon_mobile/core/models.dart';
import 'package:twon_mobile/core/realtime.dart';
import 'package:twon_mobile/core/token_store.dart';

/// F-04 A3: realtime recovery through the existing refresh lifecycle.
class MemoryStore implements SessionStore {
  Json? value;
  @override
  Future<Json?> read() async => value;
  @override
  Future<void> write(Json session) async => value = session;
  @override
  Future<void> clear() async => value = null;
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

/// Models socket_io_client: `connect()` is one attempt that runs the auth
/// callback; a refused handshake or a server disconnect leaves it inactive.
class FakeSocket extends Fake implements io.Socket {
  FakeSocket(this.options);
  final Map<String, dynamic> options;
  final handlers = <String, List<dynamic Function(dynamic)>>{};
  final attempts = <String>[];
  bool isActive = false;
  bool disposed = false;
  @override
  bool get active => isActive;
  @override
  Function() on(String event, dynamic Function(dynamic) handler) {
    handlers.putIfAbsent(event, () => []).add(handler);
    return () {};
  }

  @override
  io.Socket connect() {
    isActive = true;
    final auth = options['auth'];
    // Like socket_io_client: a callback runs on every attempt, a map is fixed.
    if (auth is Function) {
      auth((Map value) => attempts.add(value['token'] as String));
    } else {
      attempts.add((auth as Map)['token'] as String);
    }
    return this;
  }

  @override
  io.Socket disconnect() {
    isActive = false;
    fire('disconnect', 'io client disconnect');
    return this;
  }

  @override
  void dispose() {
    disposed = true;
    isActive = false;
  }

  void fire(String event, [dynamic data]) {
    for (final handler in [...?handlers[event]]) {
      handler(data);
    }
  }

  void accept() => fire('connect');
  void serverDisconnect() {
    isActive = false;
    fire('disconnect', 'io server disconnect');
  }

  void refuse([String message = 'Unauthorized', int? retryAfterMs]) {
    isActive = false;
    fire('connect_error', {
      'message': message,
      if (retryAfterMs != null) 'data': {'retryAfterMs': retryAfterMs},
    });
  }
}

class LowRandom implements Random {
  @override
  double nextDouble() => 0;
  @override
  int nextInt(int max) => 0;
  @override
  bool nextBool() => false;
}

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  late DioRepository api;
  late RealtimeService realtime;
  late List<FakeSocket> sockets;
  late int refreshes;
  late Future<ResponseBody> Function() onRefresh;

  setUp(() async {
    sockets = [];
    refreshes = 0;
    api = DioRepository(baseUrl: 'https://test.invalid', store: MemoryStore());
    api.dio.httpClientAdapter = ApiAdapter((r) async {
      if (r.path == 'auth/refresh') {
        refreshes++;
        return onRefresh();
      }
      return response(200, {'success': true, 'data': {}});
    });
    await api.saveSession({'accessToken': 'a1', 'refreshToken': 'r1'});
    realtime = RealtimeService(
      api,
      createSocket: (_, options) {
        final socket = FakeSocket(options);
        sockets.add(socket);
        return socket;
      },
      random: LowRandom(),
    );
    realtime.connect();
  });

  tearDown(() async {
    await realtime.dispose();
    api.dio.close();
  });

  Future<ResponseBody> rotated(String n) async => response(200, {
    'success': true,
    'data': {'accessToken': 'a$n', 'refreshToken': 'r$n'},
  });

  test('token expiry: one refresh, then a new socket with the new token', () async {
    onRefresh = () => rotated('2');
    sockets.last.accept();
    sockets.last.serverDisconnect();
    await settle();
    expect(refreshes, 1);
    expect(sockets, hasLength(2));
    expect(sockets.first.disposed, isTrue);
    expect(sockets.last.attempts, ['a2']);
  });

  test('a refused refresh (ban, deletion, revocation) clears the session and stops', () async {
    onRefresh = () async => response(403, {
      'success': false,
      'error': {'code': 'ACCOUNT_BANNED', 'message': 'This account has been suspended.'},
    });
    sockets.last.accept();
    sockets.last.serverDisconnect();
    await settle();
    expect(refreshes, 1);
    expect(api.session, isNull);
    expect(realtime.socket, isNull);
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    expect(refreshes, 1);
  });

  test('a refreshed token refused again is retried with backoff, never refreshed again', () async {
    onRefresh = () => rotated('2');
    sockets.last.refuse();
    await settle();
    expect(refreshes, 1);
    sockets.last.refuse(); // the new token is refused too
    await settle();
    expect(sockets.last.attempts, ['a2']);
    await Future<void>.delayed(const Duration(milliseconds: 1050)); // first backoff: 1 s
    expect(sockets.last.attempts, ['a2', 'a2']);
    expect(refreshes, 1);
  });

  test('a temporary refresh failure keeps the session and retries after backoff', () async {
    var calls = 0;
    onRefresh = () async => ++calls == 1
        ? response(503, {'success': false, 'error': {'message': 'Try later'}})
        : rotated('2');
    sockets.last.accept();
    sockets.last.serverDisconnect();
    await settle();
    expect(refreshes, 1);
    expect(api.session?['refreshToken'], 'r1');
    await Future<void>.delayed(const Duration(milliseconds: 1050));
    expect(refreshes, 2);
    expect(sockets.last.attempts, ['a2']);
  });

  test('pausing never refreshes; resuming uses the latest token', () async {
    onRefresh = () => rotated('9');
    sockets.last.accept();
    realtime.pause(); // client disconnect
    await settle();
    expect(refreshes, 0);
    await api.saveSession({'accessToken': 'a3', 'refreshToken': 'r3'}); // refreshed by HTTP while paused
    await settle();
    expect(sockets.last.attempts, isEmpty); // not connected while paused
    realtime.resume();
    expect(sockets.last.attempts, ['a3']);
    expect(refreshes, 0);
  });

  for (final code in ['RATE_LIMITED', 'TOO_MANY_CONNECTIONS', 'SERVICE_UNAVAILABLE']) {
    test('$code backs off (at least the server hint) and never refreshes (A4)', () async {
      onRefresh = () => rotated('2');
      sockets.last.refuse(code, 1200);
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      expect(sockets.last.attempts, ['a1']); // still waiting: the hint (1.2 s) beats the backoff (1 s)
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(sockets.last.attempts, ['a1', 'a1']);
      sockets.last.refuse(code); // no hint: the second backoff step (2 s)
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      expect(sockets.last.attempts, ['a1', 'a1']);
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(sockets.last.attempts, ['a1', 'a1', 'a1']);
      expect(refreshes, 0);
      expect(api.session?['refreshToken'], 'r1');
    });
  }

  test('transport-level retries use a 2–60 s jittered backoff', () {
    final options = sockets.last.options;
    expect(options['reconnectionDelay'], 2000);
    expect(options['reconnectionDelayMax'], 60000);
    expect(options['randomizationFactor'], 0.5);
  });

  test('transport errors are left to Socket.IO; signing out stops realtime', () async {
    onRefresh = () => rotated('2');
    sockets.last.fire('connect_error', {'message': 'websocket error'}); // still active
    await settle();
    expect(refreshes, 0);
    await api.clearSession();
    await settle();
    expect(realtime.socket, isNull);
  });

  test('a server resync catches up once, like a reconnect; never after sign-out', () async {
    final seen = <String>[];
    final sub = realtime.events.stream.listen((e) => seen.add(e.name));
    sockets.last.accept();
    await settle();
    seen.clear();
    sockets.last.fire('realtime:resync', {'at': 1});
    sockets.last.fire('realtime:resync', {'at': 2}); // repeated: one catch-up
    await settle();
    expect(seen, ['connect']);
    expect(refreshes, 0); // not a credential problem
    sockets.last.fire('realtime:resync', {'at': 3});
    await api.clearSession(); // signed out before the delayed catch-up
    await settle();
    expect(seen, ['connect']);
    await sub.cancel();
  });
}
