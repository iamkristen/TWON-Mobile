import 'dart:async';
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/models.dart';
import 'chat_bloc.dart' show isRetryableSend, newClientMessageId;

/// CHAT-5: messages waiting to be sent survive a lost connection and the app
/// being closed (encrypted device storage, per account, cleared on sign-out).
/// Each keeps one id for every attempt, so the server stores it once however
/// often it is retried (CHAT-4). Order is kept per conversation. Not promised: a
/// message on a device that is lost or reset, or one older than [outboxMaxAge]
/// (then the member is asked before it is sent).
const outboxMaxAge = Duration(hours: 40);
const outboxMaxItems = 50;
const _delays = [1, 3, 10, 30, 60];

abstract class OutboxStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> clear();
}

class SecureOutboxStore implements OutboxStore {
  final _storage = const FlutterSecureStorage();
  static const key = 'twon.chat-outbox.v1';
  @override
  Future<String?> read() => _storage.read(key: key);
  @override
  Future<void> write(String value) => _storage.write(key: key, value: value);
  @override
  Future<void> clear() => _storage.delete(key: key);
}

class MemoryOutboxStore implements OutboxStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String v) async => value = v;
  @override
  Future<void> clear() async => value = null;
}

enum OutboxState { queued, sending, failed }

class OutboxItem {
  OutboxItem({
    required this.clientMessageId,
    required this.account,
    required this.conversationId,
    required this.body,
    required this.createdAt,
    this.state = OutboxState.queued,
    this.attempts = 0,
    this.nextAttemptAt,
    this.error,
  });
  String clientMessageId;
  final String account, conversationId;
  final Json body;
  DateTime createdAt;
  OutboxState state;
  int attempts;
  DateTime? nextAttemptAt;
  String? error;

  Json toJson() => {
    'id': clientMessageId,
    'account': account,
    'conversationId': conversationId,
    'body': body,
    'createdAt': createdAt.toIso8601String(),
    'state': state.name,
    'attempts': attempts,
    'error': ?error,
  };
  static OutboxItem fromJson(Json j) => OutboxItem(
    clientMessageId: '${j['id']}',
    account: '${j['account']}',
    conversationId: '${j['conversationId']}',
    body: asJson(j['body']),
    createdAt: DateTime.tryParse('${j['createdAt']}') ?? DateTime.now(),
    // A send interrupted by the app closing is queued again (its id makes that safe).
    state: j['state'] == 'failed' ? OutboxState.failed : OutboxState.queued,
    attempts: (j['attempts'] as num?)?.toInt() ?? 0,
    error: j['error'] as String?,
  );
}

typedef OutboxPost = Future<dynamic> Function(String conversationId, Json body);

/// The answer to one send: stored ([message]) or waiting ([queued]).
class SendResult {
  const SendResult.sent(this.message) : queued = false;
  const SendResult.queued() : message = null, queued = true;
  final dynamic message;
  final bool queued;
}

class ChatOutbox {
  ChatOutbox(this.store);
  final OutboxStore store;
  final _items = <OutboxItem>[];
  final changes = StreamController<void>.broadcast();
  final _running = <String>{};
  final _waiting = <String, Completer<SendResult>>{};
  Future<void>? _loaded;

  static ChatOutbox shared = ChatOutbox(MemoryOutboxStore());

  Future<void> load() => _loaded ??= () async {
    try {
      final raw = await store.read();
      if (raw != null) {
        _items.addAll(
          (jsonDecode(raw) as List).map((e) => OutboxItem.fromJson(asJson(e))),
        );
      }
    } catch (_) {
      await store.clear();
    }
  }();

  List<OutboxItem> items(String account, [String? conversationId]) => _items
      .where(
        (i) =>
            i.account == account &&
            (conversationId == null || i.conversationId == conversationId),
      )
      .toList();
  bool get due => _items.any((i) => i.state == OutboxState.queued);

  Future<void> _save() async {
    changes.add(null);
    try {
      if (_items.isEmpty) {
        await store.clear();
      } else {
        await store.write(jsonEncode(_items.map((i) => i.toJson()).toList()));
      }
    } catch (_) {
      /* The queue still works until the app closes. */
    }
  }

  Future<SendResult> send(
    String account,
    String conversationId,
    Json body,
    OutboxPost post,
  ) async {
    await load();
    if (_items.length >= outboxMaxItems) {
      throw const AppFailure(
        'Too many messages are waiting to be sent. Reconnect first.',
      );
    }
    final item = OutboxItem(
      clientMessageId: newClientMessageId(),
      account: account,
      conversationId: conversationId,
      body: body,
      createdAt: DateTime.now(),
    );
    _items.add(item);
    await _save();
    final done = Completer<SendResult>();
    _waiting[item.clientMessageId] = done;
    unawaited(
      _flushConversation(account, conversationId, post).then((_) {
        if (item.state == OutboxState.queued &&
            _items.contains(item) &&
            !_running.contains('$account:$conversationId')) {
          _settle(item.clientMessageId, const SendResult.queued());
        }
      }),
    );
    return done.future;
  }

  void _settle(String id, Object outcome) {
    final done = _waiting.remove(id);
    if (done == null || done.isCompleted) return;
    if (outcome is SendResult) {
      done.complete(outcome);
    } else {
      done.completeError(outcome);
    }
  }

  Future<void> flush(String account, OutboxPost post) async {
    await load();
    final chats = items(account).map((i) => i.conversationId).toSet();
    await Future.wait(chats.map((c) => _flushConversation(account, c, post)));
  }

  /// Back online or reconnected: try everything now.
  Future<void> wake(String account, OutboxPost post) async {
    await load();
    for (final i in items(account)) {
      if (i.state == OutboxState.queued) i.nextAttemptAt = null;
    }
    await flush(account, post);
  }

  Future<void> _flushConversation(
    String account,
    String conversationId,
    OutboxPost post,
  ) async {
    final key = '$account:$conversationId';
    if (!_running.add(key)) return;
    try {
      while (true) {
        final list = items(account, conversationId);
        if (list.isEmpty) return;
        final item = list.first;
        if (item.state == OutboxState.failed) return;
        if (DateTime.now().difference(item.createdAt) > outboxMaxAge) {
          item
            ..state = OutboxState.failed
            ..error = 'This message waited too long. Send it again?';
          await _save();
          _settle(item.clientMessageId, AppFailure(item.error!));
          return;
        }
        final next = item.nextAttemptAt;
        if (next != null && next.isAfter(DateTime.now())) return;
        item
          ..state = OutboxState.sending
          ..attempts += 1;
        await _save();
        try {
          final message = await post(conversationId, {
            ...item.body,
            'clientMessageId': item.clientMessageId,
          });
          _items.remove(item);
          await _save();
          _settle(item.clientMessageId, SendResult.sent(message));
        } catch (error) {
          if (!_items.contains(item)) return; // discarded meanwhile
          final retry =
              isRetryableSend(error) ||
              (error is AppFailure && error.status == 429);
          if (retry) {
            item
              ..state = OutboxState.queued
              ..nextAttemptAt = DateTime.now().add(
                Duration(
                  seconds:
                      _delays[(item.attempts - 1).clamp(0, _delays.length - 1)],
                ),
              );
            await _save();
            _settle(item.clientMessageId, const SendResult.queued());
          } else {
            item
              ..state = OutboxState.failed
              ..error = error is AppFailure ? error.message : 'Not sent';
            await _save();
            _settle(item.clientMessageId, error);
          }
          return;
        }
      }
    } finally {
      _running.remove(key);
    }
  }

  Future<void> retry(String account, String id, OutboxPost post) async {
    final item = _items.where((i) => i.clientMessageId == id).firstOrNull;
    if (item == null) return;
    if (DateTime.now().difference(item.createdAt) > outboxMaxAge) {
      // The server no longer remembers the old id: a new one, as a new message.
      item
        ..clientMessageId = newClientMessageId()
        ..createdAt = DateTime.now()
        ..attempts = 0;
    }
    item
      ..state = OutboxState.queued
      ..error = null
      ..nextAttemptAt = null;
    await _save();
    await flush(account, post);
  }

  Future<void> discard(String id) async {
    _items.removeWhere((i) => i.clientMessageId == id);
    await _save();
    _settle(id, const AppFailure('Discarded'));
  }

  /// Another account signed in on this device: only its own messages are kept.
  Future<void> keepOnly(String account) async {
    await load();
    final others = _items.where((i) => i.account != account).toList();
    if (others.isEmpty) return;
    _items.removeWhere((i) => i.account != account);
    for (final i in others) {
      _settle(i.clientMessageId, const AppFailure('Signed in as someone else'));
    }
    await _save();
  }

  /// Sign-out: nothing typed by one account is left for the next person.
  Future<void> clear() async {
    _items.clear();
    for (final id in [..._waiting.keys]) {
      _settle(id, const AppFailure('Signed out'));
    }
    await _save();
  }
}
