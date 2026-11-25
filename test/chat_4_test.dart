import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twon_mobile/core/api.dart';
import 'package:twon_mobile/core/models.dart';
import 'package:twon_mobile/core/realtime.dart';
import 'package:twon_mobile/features/chat/chat_bloc.dart';
import 'package:twon_mobile/features/chat/chat_outbox.dart';
import 'social_experience_test.dart' show Harness;

/// CHAT-4: a message is sent once however often it is retried; a long
/// interruption leaves no hidden gap; receipts and pushed senders.
class Api implements AppRepository {
  final sent = <Json>[];
  final failures = <Object>[];
  List<ApiPage> pages = [const ApiPage([], null)];
  final queries = <Json?>[];
  @override
  Future<ApiPage> page(String path, {Json? query, CancelToken? cancel}) async {
    queries.add(query);
    return pages.length > 1 ? pages.removeAt(0) : pages.first;
  }

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
    if (method != 'POST') return null;
    sent.add(asJson(body));
    if (failures.isNotEmpty) throw failures.removeAt(0);
    return {
      '_id': 'm${sent.length}',
      'body': 'x',
      'createdAt': '2026-11-25T00:00:00Z',
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const offline = AppFailure('Cannot reach TWON.');
Entity message(int n) => Entity({
  '_id': 'm$n',
  'body': '$n',
  'createdAt':
      '2026-11-25T00:${(n ~/ 60).toString().padLeft(2, '0')}:${(n % 60).toString().padLeft(2, '0')}Z',
});

void main() {
  late Api api;
  late Harness harness;
  late RealtimeService realtime;
  late ChatBloc bloc;
  Future<void> start() async {
    bloc = ChatBloc(api, realtime, 'c1');
    await bloc.stream.firstWhere((s) => !s.loading);
  }

  setUp(() {
    api = Api();
    harness = Harness();
    realtime = RealtimeService(harness.api);
  });
  tearDown(() async {
    await bloc.close();
    await realtime.dispose();
    harness.api.dio.close();
    await harness.api.expired.close();
    await harness.api.tokensChanged.close();
  });
  // CHAT-5: outbox changes also publish states; wait for this send's answer.
  Future<ChatState> send(Json body) {
    final before = bloc.state.sent;
    final done = bloc.stream.firstWhere((s) => s.sent > before);
    bloc.add(ChatSend(body));
    return done;
  }

  // CHAT-5: sends go through the persistent outbox. An unknown outcome is no
  // longer retried twice and then dropped: the message waits (same id) and is
  // retried until stored or refused.
  test('a lost answer is retried under the same id, and shown once', () async {
    await start();
    api.failures.addAll([offline, const AppFailure('busy', status: 503)]);
    final queued = await send({'body': 'hi'});
    expect([queued.pending.length, queued.messages.length], [1, 0]);
    await bloc.outbox.wake(
      'me',
      (c, b) =>
          api.request('conversations/$c/messages', method: 'POST', body: b),
    );
    await bloc.outbox.wake(
      'me',
      (c, b) =>
          api.request('conversations/$c/messages', method: 'POST', body: b),
    );
    expect(api.sent, hasLength(3));
    expect(api.sent.map((b) => b['clientMessageId']).toSet(), hasLength(1));
    expect(
      api.sent.first['clientMessageId'],
      matches(RegExp(r'^[A-Za-z0-9-]{16,64}$')),
    );
    expect(bloc.outbox.items('me'), isEmpty);
  });

  test(
    'a waiting message keeps its id; the same words sent again are a new message',
    () async {
      await start();
      api.failures.addAll([offline, offline]);
      await send({'body': 'hi'});
      await bloc.outbox.wake(
        'me',
        (c, b) =>
            api.request('conversations/$c/messages', method: 'POST', body: b),
      );
      await bloc.outbox.wake(
        'me',
        (c, b) =>
            api.request('conversations/$c/messages', method: 'POST', body: b),
      );
      expect(api.sent.map((b) => b['clientMessageId']).toSet(), hasLength(1));
      await send({
        'body': 'hi',
      }); // sent: the same words again are a new message
      await send({'body': 'other'});
      expect(api.sent.map((b) => b['clientMessageId']).toSet(), hasLength(3));
    },
  );

  test(
    'an answer is never retried; rate limits and an attempt in progress are',
    () async {
      await start();
      for (final status in [400, 401, 403, 404, 409, 500]) {
        api.sent.clear();
        api.failures.add(AppFailure('no', status: status));
        expect((await send({'body': 'r$status'})).error, 'no');
        expect(api.sent, hasLength(1), reason: '$status');
        final failed = bloc.outbox.items('me').single;
        expect([failed.state, failed.error], [OutboxState.failed, 'no']);
        await bloc.discardPending(failed.clientMessageId);
      }
      for (final failure in [
        const AppFailure('wait', status: 409, code: 'MESSAGE_IN_PROGRESS'),
        const AppFailure('slow down', status: 429),
      ]) {
        api.sent.clear();
        api.failures.add(failure);
        expect(
          (await send({'body': 'p${failure.status}'})).pending,
          hasLength(1),
        );
        await bloc.outbox.wake(
          'me',
          (c, b) =>
              api.request('conversations/$c/messages', method: 'POST', body: b),
        );
        expect(api.sent, hasLength(2));
        expect(bloc.outbox.items('me'), isEmpty);
      }
    },
  );

  test(
    'after a long interruption the list restarts at the newest page, with no hidden gap',
    () async {
      api.pages = [
        ApiPage([for (var n = 30; n > 0; n--) message(n)], null),
        ApiPage([for (var n = 200; n > 170; n--) message(n)], 'older'),
        ApiPage([for (var n = 170; n > 140; n--) message(n)], 'older2'),
      ];
      await start();
      expect(bloc.state.messages, hasLength(30));
      realtime.events.add(const RealtimeEvent('connect', {}));
      await bloc.stream.firstWhere((s) => s.messages.first.id == 'm200');
      expect(bloc.state.messages, hasLength(30));
      expect(bloc.state.cursor, 'older');
      bloc.add(ChatLoad(older: true)); // the missed messages can be loaded
      await bloc.stream.firstWhere((s) => s.messages.length == 60);
      expect(api.queries.last!['cursor'], 'older');
      expect(bloc.state.messages.last.id, 'm141');
    },
  );

  test('a short interruption keeps what is loaded', () async {
    api.pages = [
      ApiPage([for (var n = 60; n > 30; n--) message(n)], 'older'),
      ApiPage([for (var n = 65; n > 35; n--) message(n)], 'newer-cursor'),
    ];
    await start();
    realtime.events.add(const RealtimeEvent('connect', {}));
    await bloc.stream.firstWhere((s) => s.messages.length == 35);
    expect(bloc.state.cursor, 'older');
  });

  test('a pushed message shows its sender', () async {
    await start();
    realtime.events.add(
      const RealtimeEvent('chat:message', {
        'conversationId': 'c1',
        'message': {
          '_id': 'p',
          'senderId': 'u1',
          'sender': {'_id': 'u1', 'fullName': 'Synthetic Person'},
          'createdAt': '2026-11-25T00:00:00Z',
        },
      }),
    );
    await bloc.stream.firstWhere((s) => s.messages.isNotEmpty);
    expect(
      bloc.state.messages.first.object('senderId')['fullName'],
      'Synthetic Person',
    );
  });

  test('one other reader is enough for a receipt', () {
    Entity read(List<String> by) => Entity({'_id': 'm', 'readBy': by});
    expect(readByOthers(read([]), 'me'), isFalse);
    expect(readByOthers(read(['me']), 'me'), isFalse);
    expect(readByOthers(read(['other']), 'me'), isTrue);
  });
}
