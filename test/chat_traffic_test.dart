import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twon_mobile/core/api.dart';
import 'package:twon_mobile/core/models.dart';
import 'package:twon_mobile/core/realtime.dart';
import 'package:twon_mobile/features/chat/chat_bloc.dart';
import 'social_experience_test.dart' show Harness;

/// Task 15: pushed chat events update the open chat locally; read receipts are
/// debounced; a reconnect catches up once. Before, every event reloaded the
/// last 30 messages and sent a read PATCH.
class ChatApi implements AppRepository {
  final calls = <String>[];
  @override
  Future<ApiPage> page(String path, {Json? query, CancelToken? cancel}) async {
    calls.add('GET $path');
    return ApiPage([
      Entity({'_id': 'old', 'body': 'old', 'createdAt': '2026-10-01T00:00:00Z'}),
    ], null);
  }

  @override
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Object? body,
    Json? query,
    bool authenticated = true,
    CancelToken? cancel,
  }) async {
    calls.add('$method $path');
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('a burst of pushed messages is applied locally with one read receipt', () async {
    final harness = Harness();
    final realtime = RealtimeService(harness.api);
    final api = ChatApi();
    final bloc = ChatBloc(api, realtime, 'c1');
    await bloc.stream.firstWhere((s) => s.messages.length == 1 && !s.loading);
    expect(api.calls, ['GET conversations/c1/messages']); // no read PATCH after a load
    for (var i = 0; i < 10; i++) {
      realtime.events.add(RealtimeEvent('chat:message', {
        'conversationId': 'c1',
        'message': {'_id': 'm$i', 'body': 'hi $i', 'createdAt': '2026-10-02T00:00:0${i}Z'},
      }));
    }
    realtime.events.add(const RealtimeEvent('chat:message', {
      'conversationId': 'other',
      'message': {'_id': 'x', 'body': 'elsewhere', 'createdAt': '2026-10-02T00:00:00Z'},
    }));
    await bloc.stream.firstWhere((s) => s.messages.length == 11);
    expect(bloc.state.messages.first.id, 'm9'); // newest first
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    expect(api.calls, ['GET conversations/c1/messages', 'PATCH conversations/c1/read']);

    realtime.events.add(const RealtimeEvent('chat:message_deleted', {'conversationId': 'c1', 'messageId': 'm3'}));
    await bloc.stream.firstWhere((s) => s.messages.length == 10);
    realtime.events.add(const RealtimeEvent('connect', {})); // reconnected: catch up once
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(api.calls.where((c) => c.startsWith('GET')), hasLength(2));

    await bloc.close();
    await realtime.dispose();
    harness.api.dio.close();
    await harness.api.expired.close();
    await harness.api.tokensChanged.close();
  });
}
