import 'dart:async';
import 'dart:math';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'api.dart';
import 'env_config.dart';
import 'models.dart';

class RealtimeEvent {
  const RealtimeEvent(this.name, this.payload);
  final String name;
  final Json payload;
}

typedef SocketFactory =
    io.Socket Function(String url, Map<String, dynamic> options);

/// Exponential backoff with jitter: a random delay in [cap/2, cap], the cap
/// doubling from 2 s up to 60 s.
Duration realtimeBackoff(int attempt, Random random) {
  final cap = min(60000, 2000 * pow(2, min(attempt, 10)).toInt());
  return Duration(
    milliseconds: (cap / 2 + random.nextDouble() * cap / 2).round(),
  );
}

/// Upper bound of the random delay before a `realtime:resync` catch-up.
const realtimeResyncJitterMs = 5000;

/// Retries without a fresh credential before giving up until the tokens change.
const maxRealtimeRetriesWithoutConnect = 6;

/// Handshake refusals that say nothing about credentials (F-04 A4): back off,
/// never refresh. Refusals before the WebSocket upgrade (per-IP limit) arrive as
/// plain transport errors and are retried by Socket.IO's own backoff instead.
const temporarySocketErrors = {
  'RATE_LIMITED',
  'TOO_MANY_CONNECTIONS',
  'SERVICE_UNAVAILABLE',
};

/// Socket.IO for the signed-in user (F-04 A3). The server disconnects a socket
/// when its access token expires or its session is revoked, and Socket.IO does
/// not retry those. Recovery uses the existing refresh lifecycle: one
/// de-duplicated refresh per cycle, after which `tokensChanged` rebuilds the
/// socket with the new token; a refused refresh clears the session (no token,
/// no socket); temporary failures back off. Pausing or signing out never
/// triggers a refresh.
class RealtimeService {
  RealtimeService(this.api, {SocketFactory? createSocket, Random? random})
    : _create = createSocket ?? io.io,
      _random = random ?? Random() {
    _tokens = api.tokensChanged.stream.listen((_) => connect());
  }
  final DioRepository api;
  final SocketFactory _create;
  final Random _random;
  io.Socket? socket;
  late final StreamSubscription<void> _tokens;
  final events = StreamController<RealtimeEvent>.broadcast();
  bool active = true;

  /// Whether the socket is connected (Task 15: polling is only a fallback).
  bool get connected => socket?.connected ?? false;
  String? _usedToken;
  Timer? _retry;
  Timer? _resync;
  int _attempt = 0;
  int _temporaryAttempt = 0;
  bool _refreshedThisCycle = false;
  bool _recovering = false;

  void connect() {
    _retry?.cancel();
    _retry = null;
    _resync?.cancel();
    _resync = null;
    socket?.dispose();
    socket = null;
    final token = api.session?['accessToken'];
    if (token == null) {
      // Signed out: the next sign-in starts a fresh cycle.
      _attempt = 0;
      _refreshedThisCycle = false;
      return;
    }
    final created = _create(
      AppConfig.socketUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          // Read on every attempt, so Socket.IO's own reconnects use the latest token.
          .setAuthFn((callback) {
            _usedToken = api.session?['accessToken'] as String?;
            callback({'token': _usedToken ?? ''});
          })
          .disableAutoConnect()
          .enableForceNew()
          // Transport-level retries (network drops, per-IP refusals): 2–60 s with jitter.
          .setReconnectionDelay(2000)
          .setReconnectionDelayMax(60000)
          .setRandomizationFactor(0.5)
          .build(),
    );
    socket = created;
    created.onConnect((_) {
      _attempt = 0;
      _temporaryAttempt = 0;
      _refreshedThisCycle = false;
      // Events sent while disconnected are not replayed: listeners catch up once.
      if (!events.isClosed) events.add(const RealtimeEvent('connect', {}));
    });
    // Server-initiated (expiry, revocation, logout elsewhere): Socket.IO will not retry.
    created.onDisconnect((reason) {
      if (identical(socket, created) && reason == 'io server disconnect') {
        _recover();
      }
    });
    // Handshake refused (inactive socket); transport errors are retried by Socket.IO.
    created.onConnectError((error) {
      if (!identical(socket, created) || created.active) return;
      final detail = error is Map ? error : const {};
      if (temporarySocketErrors.contains(detail['message'])) {
        final hint = detail['data'] is Map
            ? detail['data']['retryAfterMs']
            : null;
        return _retryLater(hint is num && hint > 0 ? hint.toInt() : 0);
      }
      _recover();
    });
    // After a server-side Redis outage (multi-instance), events from other servers
    // may have been lost while this socket stayed connected: listeners catch up as
    // after a reconnect, after a random delay so clients do not refetch at once.
    created.on('realtime:resync', (_) {
      if (!identical(socket, created) || _resync != null) return;
      _resync = Timer(
        Duration(
          milliseconds: (_random.nextDouble() * realtimeResyncJitterMs).round(),
        ),
        () {
          _resync = null;
          if (identical(socket, created) && active && !events.isClosed) {
            events.add(const RealtimeEvent('connect', {}));
          }
        },
      );
    });
    for (final name in [
      'chat:message',
      'chat:message_updated',
      'chat:message_deleted',
      'chat:reaction',
      'notification:new',
    ]) {
      socket!.on(
        name,
        (value) => events.add(RealtimeEvent(name, asJson(value))),
      );
    }
    if (active) created.connect();
  }

  void _later(void Function() run) {
    _retry?.cancel();
    _retry = Timer(realtimeBackoff(_attempt++, _random), () {
      if (active) run();
    });
  }

  /// A refusal unrelated to credentials: wait (at least the server's hint), retry.
  void _retryLater(int retryAfterMs) {
    _retry?.cancel();
    final backoff = realtimeBackoff(
      _temporaryAttempt++,
      _random,
    ).inMilliseconds;
    final delay = min(60000, max(retryAfterMs, backoff));
    _retry = Timer(Duration(milliseconds: delay), () {
      if (active) socket?.connect();
    });
  }

  Future<void> _recover() async {
    if (!active || _recovering) return;
    final current = api.session?['accessToken'];
    if (current == null) return; // signed out
    if (current != _usedToken) return connect(); // refreshed elsewhere already
    if (_refreshedThisCycle) {
      // Refreshed already and still refused: back off, never refresh again.
      if (_attempt >= maxRealtimeRetriesWithoutConnect) return;
      return _later(() => socket?.connect());
    }
    _refreshedThisCycle = true;
    _recovering = true;
    try {
      await api.refreshSession(); // success: tokensChanged rebuilds the socket
    } on AppFailure catch (error) {
      // 400/401/403: the session was cleared, so no token and no socket.
      if (![400, 401, 403].contains(error.status)) {
        _refreshedThisCycle = false;
        _later(_recover);
      }
    } catch (_) {
      _refreshedThisCycle = false;
      _later(_recover);
    } finally {
      _recovering = false;
    }
  }

  void pause() {
    active = false;
    _retry?.cancel();
    _resync?.cancel();
    _resync = null;
    socket?.disconnect();
  }

  /// Rebuilds the socket so it authenticates with the latest token, never the
  /// one it had before the app was paused.
  void resume() {
    active = true;
    connect();
  }

  Future<void> dispose() async {
    _retry?.cancel();
    _resync?.cancel();
    socket?.dispose();
    await _tokens.cancel();
    await events.close();
  }
}
