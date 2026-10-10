import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'api.dart';
import 'env_config.dart';
import 'models.dart';

class RealtimeEvent {
  const RealtimeEvent(this.name, this.payload);
  final String name;
  final Json payload;
}

class RealtimeService {
  RealtimeService(this.api) {
    _tokens = api.tokensChanged.stream.listen((_) => connect());
  }
  final DioRepository api;
  io.Socket? socket;
  late final StreamSubscription<void> _tokens;
  final events = StreamController<RealtimeEvent>.broadcast();
  bool active = true;
  void connect() {
    socket?.dispose();
    socket = null;
    final token = api.session?['accessToken'];
    if (token == null) return;
    socket = io.io(
      AppConfig.socketUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token})
          .disableAutoConnect()
          .enableForceNew()
          .build(),
    );
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
    if (active) socket!.connect();
  }

  void pause() {
    active = false;
    socket?.disconnect();
  }

  void resume() {
    active = true;
    if (socket == null) {
      connect();
    } else {
      if (active) socket!.connect();
    }
  }

  Future<void> dispose() async {
    socket?.dispose();
    await _tokens.cancel();
    await events.close();
  }
}
