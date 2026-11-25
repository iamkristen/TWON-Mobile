import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twon_mobile/core/api.dart';
import 'package:twon_mobile/core/models.dart';
import 'package:twon_mobile/core/push.dart';
import 'package:twon_mobile/core/realtime.dart';
import 'package:twon_mobile/features/chat/chat_bloc.dart';
import 'package:twon_mobile/features/chat/chat_outbox.dart';
import 'realtime_recovery_test.dart' show FakeSocket, MemoryStore;
import 'social_experience_test.dart' show Harness;

/// CHAT-5: offline sending, receipts, typing, push token lifecycle and the
/// reconnection pass.
class Api implements AppRepository {
  final calls = <String>[];
  final bodies = <Json>[];
  bool online = true;
  Object? refusal;
  @override
  Future<ApiPage> page(String path, {Json? query, CancelToken? cancel}) async =>
      const ApiPage([], null);
  @override
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Object? body,
    Json? query,
    bool authenticated = true,
    CancelToken? cancel,
    bool cached = false,
  }) async {
    calls.add('$method $path');
    if (body is Map) bodies.add(asJson(body));
    if (method == 'POST' && path.endsWith('/messages')) {
      if (!online) throw const AppFailure('Cannot reach TWON.');
      if (refusal != null) throw refusal!;
      return {
        '_id': 'm${bodies.length}',
        'body': asJson(body)['body'],
        'createdAt': '2026-11-25T10:00:00Z',
      };
    }
    return path.endsWith('/receipts') ? {'delivered': [], 'read': []} : null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<dynamic> Function(String, Json) poster(Api api) =>
    (c, b) => api.request('conversations/$c/messages', method: 'POST', body: b);
List<String?> ids(Api api) => api.bodies
    .where((b) => b.containsKey('clientMessageId'))
    .map((b) => b['clientMessageId'] as String?)
    .toList();

void main() {
  group('outbox', () {
    test(
      'a message sent offline survives the app closing and is sent once, with its id, after reconnecting',
      () async {
        final store = MemoryOutboxStore();
        final api = Api()..online = false;
        final first = ChatOutbox(store);
        final result = await first.send('me', 'c1', {
          'body': 'hello',
        }, poster(api));
        expect(result.queued, isTrue);
        expect(store.value, contains('hello'));
        // The app is closed and opened again.
        final reopened = ChatOutbox(store);
        await reopened.load();
        expect(reopened.items('me', 'c1').map((i) => i.state), [
          OutboxState.queued,
        ]);
        api.online = true;
        await reopened.wake('me', poster(api));
        expect(reopened.items('me'), isEmpty);
        expect(ids(api).toSet(), hasLength(1));
        expect(ids(api), hasLength(2));
        expect(store.value, isNull);
      },
    );

    test(
      'order is kept per conversation; a refusal holds later ones in that chat until it is retried or deleted',
      () async {
        final api = Api()..online = false;
        final box = ChatOutbox(MemoryOutboxStore());
        await box.send('me', 'c1', {'body': '1'}, poster(api));
        await box.send('me', 'c1', {'body': '2'}, poster(api));
        api
          ..online = true
          ..refusal = const AppFailure('Not allowed', status: 403);
        await box.wake('me', poster(api));
        expect(box.items('me', 'c1').map((i) => [i.state, i.error]), [
          [OutboxState.failed, 'Not allowed'],
          [OutboxState.queued, null],
        ]);
        api.refusal = null;
        await box.discard(box.items('me', 'c1').first.clientMessageId);
        await box.wake('me', poster(api));
        expect(box.items('me'), isEmpty);
        expect(api.bodies.last['body'], '2');
      },
    );

    test('accounts are separate; signing out clears the queue', () async {
      final api = Api()..online = false;
      final box = ChatOutbox(MemoryOutboxStore());
      await box.send('a', 'c1', {'body': 'mine'}, poster(api));
      expect(box.items('b'), isEmpty);
      await box.clear();
      expect(
        [box.items('a'), (box.store as MemoryOutboxStore).value],
        [isEmpty, isNull],
      );
    });

    test(
      'the open chat shows the queued message and sends it when the socket reconnects',
      () async {
        final api = Api()..online = false;
        final harness = Harness();
        final realtime = RealtimeService(harness.api);
        final bloc = ChatBloc(
          api,
          realtime,
          'c1',
          outbox: ChatOutbox(MemoryOutboxStore()),
          account: 'me',
        );
        final before = bloc.state.sent;
        bloc.add(ChatSend({'body': 'later'}));
        final queued = await bloc.stream.firstWhere((s) => s.sent > before);
        expect(
          [queued.pending.length, queued.error],
          [1, contains('Waiting for connection')],
        );
        api.online = true;
        realtime.events.add(const RealtimeEvent('connect', {}));
        final sent = await bloc.stream.firstWhere(
          (s) =>
              s.pending.isEmpty &&
              s.messages.any((m) => m.text('body') == 'later'),
        );
        expect(
          sent.messages.where((m) => m.text('body') == 'later'),
          hasLength(1),
        );
        await bloc.close();
        await realtime.dispose();
        harness.api.dio.close();
        await harness.api.expired.close();
        await harness.api.tokensChanged.close();
      },
    );
  });

  group('receipts and typing', () {
    test('own status: Read beats Delivered beats Sent, from others only', () {
      final m = Entity({
        '_id': 'b',
        'createdAt': '2026-11-25T10:00:00.000Z',
        'readBy': [],
      });
      Json at(String u, String id) => {
        'userId': u,
        'upTo': id,
        'at': '2026-11-25T10:00:00.000Z',
      };
      expect(ownStatus(m, 'me', const {}), 'Sent');
      expect(
        ownStatus(m, 'me', {
          'delivered': [at('me', 'z')],
        }),
        'Sent',
      );
      expect(
        ownStatus(m, 'me', {
          'delivered': [at('x', 'a')],
        }),
        'Sent',
      );
      expect(
        ownStatus(m, 'me', {
          'delivered': [at('x', 'b')],
        }),
        'Delivered',
      );
      expect(
        ownStatus(m, 'me', {
          'delivered': [at('x', 'b')],
          'read': [at('x', 'c')],
        }),
        'Read',
      );
    });

    test(
      'a burst from others is acknowledged once; typing shows and expires; a message ends it',
      () async {
        ChatBloc.typingTtl = const Duration(milliseconds: 200);
        final api = Api();
        final harness = Harness();
        final realtime = RealtimeService(harness.api);
        final bloc = ChatBloc(api, realtime, 'c1', account: 'me');
        await bloc.stream.firstWhere((s) => !s.loading);
        realtime.events.add(
          const RealtimeEvent('chat:typing', {
            'conversationId': 'c1',
            'userId': 'u1',
            'typing': true,
          }),
        );
        expect(
          (await bloc.stream.firstWhere((s) => s.typing.isNotEmpty)).typing,
          ['u1'],
        );
        await bloc.stream.firstWhere(
          (s) => s.typing.isEmpty,
        ); // expired by itself
        realtime.events.add(
          const RealtimeEvent('chat:typing', {
            'conversationId': 'c1',
            'userId': 'u1',
            'typing': true,
          }),
        );
        await bloc.stream.firstWhere((s) => s.typing.isNotEmpty);
        for (final id in ['m1', 'm2']) {
          realtime.events.add(
            RealtimeEvent('chat:message', {
              'conversationId': 'c1',
              'message': {
                '_id': id,
                'senderId': 'u1',
                'body': id,
                'createdAt': '2026-11-25T10:00:0${id[1]}Z',
              },
            }),
          );
        }
        realtime.events.add(
          const RealtimeEvent('chat:message', {
            'conversationId': 'c1',
            'message': {
              '_id': 'm3',
              'senderId': 'me',
              'body': 'mine',
              'createdAt': '2026-11-25T10:00:03Z',
            },
          }),
        );
        expect(
          (await bloc.stream.firstWhere((s) => s.typing.isEmpty)).typing,
          isEmpty,
        );
        await Future<void>.delayed(const Duration(milliseconds: 1200));
        expect(
          api.calls.where((c) => c == 'POST conversations/delivered'),
          hasLength(1),
        );
        expect(api.bodies.firstWhere((b) => b.containsKey('items'))['items'], [
          {'conversationId': 'c1', 'upTo': 'm2'},
        ]);
        ChatBloc.typingTtl = const Duration(seconds: 6);
        await bloc.close();
        await realtime.dispose();
        harness.api.dio.close();
        await harness.api.expired.close();
        await harness.api.tokensChanged.close();
      },
    );
  });

  group('push token lifecycle', () {
    test(
      'registered for this sign-in, again when it changes, removed on sign-out; only real chat ids open',
      () async {
        final api = Api();
        final source = Tokens();
        final push = PushRegistration(api, source);
        await push.start();
        source.changes.add('token-2-${'x' * 30}');
        await Future<void>.delayed(Duration.zero);
        expect(
          api.bodies
              .where((b) => b['provider'] == 'fcm')
              .map((b) => [b['platform'], b['token']]),
          [
            ['ios', 'token-1-${'x' * 30}'],
            ['ios', 'token-2-${'x' * 30}'],
          ],
        );
        final opened = <String>[];
        push.openedChats.listen(opened.add);
        source.opens
          ..add('a' * 24)
          ..add('javascript:x');
        await push.stop();
        expect(api.calls.last, 'DELETE push/devices/current');
        source.changes.add('token-3');
        await Future<void>.delayed(Duration.zero);
        expect(api.bodies.where((b) => b['provider'] == 'fcm'), hasLength(2));
        expect(opened, ['a' * 24]);
      },
    );
  });

  test(
    'realtime keeps the server’s reconnection pass for the next handshake, only for its own account',
    () async {
      String jwt(String user) =>
          'h.${base64Url.encode(utf8.encode(jsonEncode({'userId': user}))).replaceAll('=', '')}.s';
      final a = 'a' * 24, b = 'b' * 24;
      final sockets = <FakeSocket>[];
      final api = DioRepository(
        baseUrl: 'https://test.invalid',
        store: MemoryStore(),
      );
      await api.saveSession({'accessToken': jwt(a), 'refreshToken': 'r1'});
      final realtime = RealtimeService(
        api,
        createSocket: (url, options) {
          final s = FakeSocket(options);
          sockets.add(s);
          return s;
        },
      );
      realtime.connect();
      expect(sockets.last.options['query'], anyOf(isNull, isEmpty));
      final pass = '$a.mz5x2k.${'s' * 43}';
      sockets.last.fire('realtime:pass', {'pass': pass});
      realtime.connect();
      expect(sockets.last.options['query'], {'pass': pass});
      // Another account signs in on this device: the pass is not used for it.
      await api.saveSession({'accessToken': jwt(b), 'refreshToken': 'r2'});
      await Future<void>.delayed(Duration.zero);
      realtime.connect();
      expect(sockets.last.options['query'], anyOf(isNull, isEmpty));
      await realtime.dispose();
    },
  );
}

class Tokens implements PushTokenSource {
  final changes = StreamController<String>.broadcast();
  final opens = StreamController<String>.broadcast();
  @override
  String get platform => 'ios';
  @override
  Future<String?> token() async => 'token-1-${'x' * 30}';
  @override
  Stream<String> get tokenChanges => changes.stream;
  @override
  Stream<String> get opened => opens.stream;
}
