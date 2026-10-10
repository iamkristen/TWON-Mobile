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
    on<ChatLoad>(_load, transformer: restartable());
    on<ChatSend>(_send, transformer: sequential());
    _socket = realtime.events.stream
        .where((event) => event.payload['conversationId'] == id)
        .listen((event) {
          if (event.payload['message'] is Map) {
            add(ChatPatch(Entity(asJson(event.payload['message']))));
          }
          add(ChatLoad());
        });
    _poll = Timer.periodic(const Duration(seconds: 15), (_) {
      if (active) add(ChatLoad());
    });
    add(ChatLoad());
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
      await repository.request('conversations/$id/read', method: 'PATCH');
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
    await _socket.cancel();
    return super.close();
  }
}
