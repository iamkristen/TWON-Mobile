import 'dart:async';
import 'dart:math';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import '../../core/api.dart';
import '../../core/models.dart';
import '../../core/realtime.dart';
import 'chat_outbox.dart';

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

/// CHAT-4: a pushed message names its sender (a large clan's conversation does
/// not list every member).
Entity withSender(Json message) => Entity({
  ...message,
  if (message['sender'] is Map) 'senderId': message['sender'],
});

/// CHAT-4: anyone else's receipt means read (the sender's own id is no longer
/// recorded since CHAT-1, so one reader is enough).
bool readByOthers(Entity message, String? me) =>
    message.strings('readBy').any((id) => id != me);

/// CHAT-4: the sender's own name for one message; a retry with it never sends twice.
String newClientMessageId([Random? random]) {
  final source = random ?? Random.secure();
  return List.generate(
    16,
    (_) => source.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

/// The outcome is unknown, or the server asks to try again; anything else is an answer.
bool isRetryableSend(Object error) =>
    error is AppFailure &&
    (error.code == 'MESSAGE_IN_PROGRESS' ||
        (error.status == null && error.code != 'CANCELED') ||
        const [502, 503, 504].contains(error.status));

/// CHAT-5: the outbox or a receipt changed.
class ChatLiveChanged extends ChatEvent {}

/// CHAT-5: own message status: delivered or read by someone else (DMs and groups).
String ownStatus(Entity message, String? me, Json receipts) {
  bool reached(dynamic r) {
    final p = asJson(r);
    if (p['userId'] == me) return false;
    final at = '${p['at']}', created = message.text('createdAt');
    return created.compareTo(at) < 0 ||
        (created == at && message.id.compareTo('${p['upTo']}') <= 0);
  }

  if (readByOthers(message, me) ||
      ((receipts['read'] as List?) ?? const []).any(reached)) {
    return 'Read';
  }
  if (((receipts['delivered'] as List?) ?? const []).any(reached)) {
    return 'Delivered';
  }
  return 'Sent';
}

class ChatState {
  const ChatState({
    this.messages = const [],
    this.loading = false,
    this.sending = false,
    this.error,
    this.cursor,
    this.sent = 0,
    this.pending = const [],
    this.typing = const [],
    this.receipts = const {},
  });
  final List<Entity> messages;
  final bool loading, sending;
  final String? error, cursor;
  final int sent;

  /// CHAT-5: messages of this chat not sent yet, who is typing, receipt positions.
  final List<OutboxItem> pending;
  final List<String> typing;
  final Json receipts;
  ChatState copy({
    List<Entity>? messages,
    bool? loading,
    bool? sending,
    String? error,
    String? cursor,
    int? sent,
    List<OutboxItem>? pending,
    List<String>? typing,
    Json? receipts,
  }) => ChatState(
    messages: messages ?? this.messages,
    loading: loading ?? this.loading,
    sending: sending ?? this.sending,
    error: error,
    cursor: cursor ?? this.cursor,
    sent: sent ?? this.sent,
    pending: pending ?? this.pending,
    typing: typing ?? this.typing,
    receipts: receipts ?? this.receipts,
  );
}

class ChatBloc extends Bloc<ChatEvent, ChatState> {
  ChatBloc(
    this.repository,
    this.realtime,
    this.id, {
    ChatOutbox? outbox,
    this.account = 'me',
    this.signedInAs,
  }) : outbox = outbox ?? ChatOutbox(MemoryOutboxStore()),
       super(const ChatState()) {
    on<ChatLiveChanged>((event, emit) {
      final now = DateTime.now();
      _typing.removeWhere((_, until) => until.isBefore(now));
      emit(
        state.copy(
          pending: this.outbox.items(account, id),
          typing: _typing.keys.toList(),
          receipts: _receipts,
        ),
      );
    });
    _outboxChanges = this.outbox.changes.stream.listen(
      (_) => isClosed ? null : add(ChatLiveChanged()),
    );
    unawaited(
      this.outbox.load().then((_) => isClosed ? null : add(ChatLiveChanged())),
    );
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
        unawaited(this.outbox.wake(account, _post)); // CHAT-5
        return;
      }
      if (event.payload['conversationId'] != id) return;
      // CHAT-5: typing (opt-in on the server; expires here) and receipts.
      if (event.name == 'chat:typing') {
        final who = '${event.payload['userId']}';
        if (event.payload['typing'] == true) {
          _typing[who] = DateTime.now().add(typingTtl);
          Timer(typingTtl + const Duration(milliseconds: 50), () {
            if (!isClosed) add(ChatLiveChanged());
          });
        } else {
          _typing.remove(who);
        }
        add(ChatLiveChanged());
        return;
      }
      if (event.name == 'chat:delivered') {
        _loadReceipts();
        return;
      }
      final message = event.payload['message'];
      switch (event.name) {
        case 'chat:message' when message is Map:
          final incoming = withSender(asJson(message));
          add(ChatIncoming(incoming));
          _scheduleRead(incoming.id);
          final from = entityId(incoming.data['senderId']);
          if (_typing.remove(from) != null) add(ChatLiveChanged());
          if (from != account) _scheduleDelivered(incoming.id);
        case 'chat:message_updated' when message is Map:
          add(ChatPatch(Entity(asJson(message))));
        case 'chat:message_deleted' when event.payload['messageId'] is String:
          add(ChatRemove(event.payload['messageId'] as String));
        // CHAT-1: joined, left or removed: reload (a removed member gets a 403).
        case 'chat:conversation_changed':
          add(ChatLoad());
        case 'chat:read':
          _loadReceipts();
        default:
          _scheduleReload(); // reactions and unknown shapes: one reload per burst
      }
    });
    // Fallback only: while the socket is down, poll every 15 s.
    _poll = Timer.periodic(const Duration(seconds: 15), (_) {
      if (active && !realtime.connected) add(ChatLoad());
      // CHAT-5: messages waiting for the connection are tried again.
      if (this.outbox.due) unawaited(this.outbox.flush(account, _post));
    });
    add(ChatLoad());
    _loadReceipts();
  }

  static Duration typingTtl = const Duration(seconds: 6);
  final ChatOutbox outbox;
  final String account;
  final String Function()? signedInAs;
  late final StreamSubscription<void> _outboxChanges;
  final _typing = <String, DateTime>{};
  Json _receipts = const {};
  Timer? _deliveredTimer;
  String? _deliveredUpTo;

  /// A queued message sent later appears like a pushed one (once, by its id).
  Future<dynamic> _post(String conversationId, Json body) async {
    // CHAT-5: a message queued by one account is never sent with another's session.
    if (signedInAs != null && signedInAs!() != account) {
      throw const AppFailure(
        'Signed in as someone else',
        code: 'ACCOUNT_CHANGED',
      );
    }
    final sent = await repository.request(
      'conversations/$conversationId/messages',
      method: 'POST',
      body: body,
    );
    if (!isClosed && conversationId == id && sent is Map) {
      add(ChatIncoming(withSender(asJson(sent))));
    }
    return sent;
  }

  Future<void> _loadReceipts() async {
    try {
      _receipts = asJson(
        await repository.request('conversations/$id/receipts'),
      );
      if (!isClosed) add(ChatLiveChanged());
    } catch (_) {
      /* Receipts are optional (older servers, clans). */
    }
  }

  /// CHAT-5: this device received messages (one acknowledgement per burst).
  void _scheduleDelivered(String upTo) {
    _deliveredUpTo = upTo;
    _deliveredTimer ??= Timer(const Duration(seconds: 1), () {
      _deliveredTimer = null;
      final position = _deliveredUpTo;
      _deliveredUpTo = null;
      if (position == null) return;
      repository
          .request(
            'conversations/delivered',
            method: 'POST',
            body: {
              'items': [
                {'conversationId': id, 'upTo': position},
              ],
            },
          )
          .catchError((_) => null);
    });
  }

  /// CHAT-5: at most every 4 s while typing, and once when stopping (opt-in on the server).
  DateTime? _typedAt;
  Timer? _typingStop;
  void typed() {
    _typingStop?.cancel();
    _typingStop = Timer(const Duration(seconds: 5), stoppedTyping);
    final now = DateTime.now();
    if (_typedAt != null &&
        now.difference(_typedAt!) < const Duration(seconds: 4)) {
      return;
    }
    _typedAt = now;
    repository
        .request(
          'conversations/$id/typing',
          method: 'POST',
          body: {'typing': true},
        )
        .catchError((_) => null);
  }

  void stoppedTyping() {
    _typingStop?.cancel();
    if (_typedAt == null) return;
    _typedAt = null;
    repository
        .request(
          'conversations/$id/typing',
          method: 'POST',
          body: {'typing': false},
        )
        .catchError((_) => null);
  }

  Future<void> retryPending(String clientMessageId) =>
      outbox.retry(account, clientMessageId, _post);
  Future<void> discardPending(String clientMessageId) =>
      outbox.discard(clientMessageId);

  Timer? _readTimer;
  Timer? _reloadTimer;

  /// CHAT-1 (F03): one read receipt per burst, up to the newest message shown.
  /// Loading a page marks nothing on the server.
  String? _readUpTo;
  void _scheduleRead(String upTo) {
    _readUpTo = upTo;
    _readTimer?.cancel();
    _readTimer = Timer(const Duration(seconds: 1), () {
      final position = _readUpTo;
      _readUpTo = null;
      if (!active || isClosed || position == null) return;
      repository
          .request(
            'conversations/$id/read',
            method: 'PATCH',
            body: {'upTo': position},
          )
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
      // CHAT-4: after a long interruption the newest page may not reach what is
      // already loaded. Showing both would hide the messages in between with no
      // way to load them, so the list starts again from the newest page.
      final gap =
          !event.older &&
          !firstLoad &&
          page.cursor != null &&
          state.messages.isNotEmpty &&
          !page.items.any((m) => state.messages.any((s) => s.id == m.id));
      if (gap) _historyExhausted = false;
      final rows = event.older
          ? [...state.messages, ...page.items]
          : gap
          ? page.items
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
          cursor: event.older || firstLoad || gap ? page.cursor : state.cursor,
          sent: state.sent,
        ),
      );
      // CHAT-1 (F03): read up to the newest message now on screen (the list
      // opens at the newest message); loading older pages marks nothing more.
      if (!event.older && messages.isNotEmpty) _scheduleRead(messages.first.id);
    } catch (error) {
      if (!emit.isDone) {
        emit(state.copy(loading: false, error: error.toString()));
      }
    }
  }

  /// CHAT-5: through the persistent outbox: sent now, or kept until the
  /// connection is back (also after the app is closed). The input is cleared
  /// either way; a refusal is shown on the message itself.
  Future<void> _send(ChatSend event, Emitter<ChatState> emit) async {
    emit(state.copy(sending: true));
    stoppedTyping();
    try {
      final result = await outbox.send(account, id, event.body, _post);
      if (emit.isDone) return;
      final row = result.queued ? null : Entity(asJson(result.message));
      emit(
        state.copy(
          messages: row == null
              ? state.messages
              : [row, ...state.messages.where((m) => m.id != row.id)],
          sending: false,
          sent: state.sent + 1,
          pending: outbox.items(account, id),
          error: result.queued
              ? 'Waiting for connection. It will be sent automatically.'
              : null,
        ),
      );
    } catch (error) {
      if (!emit.isDone) {
        emit(
          state.copy(
            sending: false,
            sent: state.sent + 1,
            error: error.toString(),
          ),
        );
      }
    }
  }

  @override
  Future<void> close() async {
    _poll.cancel();
    stoppedTyping();
    _deliveredTimer?.cancel();
    _readTimer?.cancel();
    _reloadTimer?.cancel();
    await _socket.cancel();
    await _outboxChanges.cancel();
    return super.close();
  }
}
