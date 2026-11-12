import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import '../../core/api.dart';
import '../../core/models.dart';
import '../../core/realtime.dart';

sealed class ChatEvent {}

class ChatLoad extends ChatEvent {
  ChatLoad({this.older = false});
  final bool older;
}

class ChatPatch extends ChatEvent {
  ChatPatch(this.message);
  final Entity message;
}

/// A message pushed by the server (Task 15): inserted locally, no reload.
class ChatIncoming extends ChatEvent {
  ChatIncoming(this.message);
  final Entity message;
}

class ChatRemove extends ChatEvent {
  ChatRemove(this.messageId);
  final String messageId;
}

class ChatSend extends ChatEvent {
  ChatSend(this.body);
  final Json body;
}

class ChatState {
  const ChatState({
    this.messages = const [],
    this.loading = false,
    this.sending = false,
    this.error,
    this.cursor,
    this.sent = 0,
  });
  final List<Entity> messages;
  final bool loading, sending;
  final String? error, cursor;
  final int sent;
  ChatState copy({
    List<Entity>? messages,
    bool? loading,
    bool? sending,
    String? error,
    String? cursor,
    int? sent,
  }) => ChatState(
    messages: messages ?? this.messages,
    loading: loading ?? this.loading,
    sending: sending ?? this.sending,
    error: error,
    cursor: cursor ?? this.cursor,
    sent: sent ?? this.sent,
  );
}

class ChatBloc extends Bloc<ChatEvent, ChatState> {
  ChatBloc(this.repository, this.realtime, this.id) : super(const ChatState()) {
    on<ChatPatch>((event, emit) {
      emit(
        state.copy(
          messages: state.messages
              .map(
                (row) => row.id == event.message.id
                    ? Entity({
                        ...row.data,
                        ...event.message.data,
                        if (event.message.data['senderId'] is String &&
                            entityId(row.data['senderId']) ==
                                entityId(event.message.data['senderId']) &&
                            row.data['senderId'] is Map)
                          'senderId': row.data['senderId'],
                      })
                    : row,
              )
              .toList(),
        ),
      );
    });
    on<ChatIncoming>((event, emit) {
      if (state.messages.any((m) => m.id == event.message.id)) {
        return add(ChatPatch(event.message)); // already shown (e.g. own send)
      }
      final messages = [event.message, ...state.messages]
        ..sort((a, b) => b.text('createdAt').compareTo(a.text('createdAt')));
      emit(state.copy(messages: messages));
    });
    on<ChatRemove>((event, emit) {
      emit(
        state.copy(
          messages: state.messages
              .where((m) => m.id != event.messageId)
              .toList(),
        ),
      );
    });
    on<ChatLoad>(_load, transformer: restartable());
    on<ChatSend>(_send, transformer: sequential());
    // Task 15: pushed events update the open chat locally. Before, every event
    // reloaded the last 30 messages and sent a read PATCH, and a 15 s poll did
    // the same while the socket was connected.
    _socket = realtime.events.stream.listen((event) {
      if (event.name == 'connect') {
        // Catch up on events missed while disconnected.
        if (_loaded) add(ChatLoad());
        return;
      }
      if (event.payload['conversationId'] != id) return;
      final message = event.payload['message'];
      switch (event.name) {
        case 'chat:message' when message is Map:
          add(ChatIncoming(Entity(asJson(message))));
          _scheduleRead();
        case 'chat:message_updated' when message is Map:
          add(ChatPatch(Entity(asJson(message))));
        case 'chat:message_deleted' when event.payload['messageId'] is String:
          add(ChatRemove(event.payload['messageId'] as String));
        default:
          _scheduleReload(); // reactions and unknown shapes: one reload per burst
      }
    });
    // Fallback only: while the socket is down, poll every 15 s.
    _poll = Timer.periodic(const Duration(seconds: 15), (_) {
      if (active && !realtime.connected) add(ChatLoad());
    });
    add(ChatLoad());
  }

  Timer? _readTimer;
  Timer? _reloadTimer;

  /// One read receipt per burst of incoming messages (loads mark read server-side).
  void _scheduleRead() {
    _readTimer?.cancel();
    _readTimer = Timer(const Duration(seconds: 1), () {
      if (!active || isClosed) return;
      repository
          .request('conversations/$id/read', method: 'PATCH')
          .catchError((_) => null);
    });
  }

  void _scheduleReload() {
    _reloadTimer?.cancel();
    _reloadTimer = Timer(const Duration(seconds: 1), () {
      if (active && !isClosed) add(ChatLoad());
    });
  }

  bool active = true;
  bool _loaded = false;
  bool _historyExhausted = false;
  final AppRepository repository;
  final RealtimeService realtime;
  final String id;
  late final StreamSubscription<RealtimeEvent> _socket;
  late final Timer _poll;
  Future<void> _load(ChatLoad event, Emitter<ChatState> emit) async {
    if (event.older && (state.cursor == null || _historyExhausted)) return;
    emit(state.copy(loading: state.messages.isEmpty));
    try {
      final page = await repository.page(
        'conversations/$id/messages',
        query: {'limit': 30, if (event.older) 'cursor': state.cursor},
      );
      if (emit.isDone) return;
      final firstLoad = !_loaded;
      _loaded = true;
      if (event.older || firstLoad) {
        _historyExhausted = page.cursor == null;
      }
      final rows = event.older
          ? [...state.messages, ...page.items]
          : [...page.items, ...state.messages];
      final unique = <String, Entity>{};
      for (final row in rows) {
        unique.putIfAbsent(row.id, () => row);
      }
      final messages = unique.values.toList()
        ..sort((a, b) => b.text('createdAt').compareTo(a.text('createdAt')));
      emit(
        ChatState(
          messages: messages,
          loading: false,
          sending: state.sending,
          cursor: event.older || firstLoad ? page.cursor : state.cursor,
          sent: state.sent,
        ),
      );
      // Loading messages marks them read on the server; no separate PATCH.
    } catch (error) {
      if (!emit.isDone) {
        emit(state.copy(loading: false, error: error.toString()));
      }
    }
  }

  Future<void> _send(ChatSend event, Emitter<ChatState> emit) async {
    emit(state.copy(sending: true));
    try {
      final row = Entity(
        asJson(
          await repository.request(
            'conversations/$id/messages',
            method: 'POST',
            body: event.body,
          ),
        ),
      );
      if (emit.isDone) return;
      emit(
        state.copy(
          messages: [row, ...state.messages.where((m) => m.id != row.id)],
          sending: false,
          sent: state.sent + 1,
        ),
      );
    } catch (error) {
      if (!emit.isDone) {
        emit(state.copy(sending: false, error: error.toString()));
      }
    }
  }

  @override
  Future<void> close() async {
    _poll.cancel();
    _readTimer?.cancel();
    _reloadTimer?.cancel();
    await _socket.cancel();
    return super.close();
  }
}
