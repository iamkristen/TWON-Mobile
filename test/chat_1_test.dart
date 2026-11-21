import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:twon_mobile/core/api.dart';
import 'package:twon_mobile/core/models.dart';
import 'package:twon_mobile/core/realtime.dart';
import 'package:twon_mobile/features/chat/chat_bloc.dart';
import 'package:twon_mobile/features/chat/group_membership.dart';
import 'social_experience_test.dart' show Harness;

/// CHAT-1 on Mobile: one attachment contract, read positions instead of
/// read-on-load, group invitations and membership.
class ReadApi implements AppRepository {
  final calls = <String>[];
  final bodies = <Object?>[];
  @override
  Future<ApiPage> page(String path, {Json? query, CancelToken? cancel}) async {
    calls.add('GET $path');
    return ApiPage([
      Entity({
        '_id': 'newest',
        'body': 'b',
        'createdAt': '2026-10-01T00:00:02Z',
      }),
      Entity({
        '_id': 'older',
        'body': 'a',
        'createdAt': '2026-10-01T00:00:01Z',
      }),
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
    bodies.add(body);
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const uid = 'aaaaaaaaaaaaaaaaaaaaaaaa';
String key(String category, String ext) =>
    'https://cdn.example.test/$category/$uid/123e4567-e89b-12d3-a456-426614174000.$ext';

Json groupJson({required String owner}) => {
  '_id': 'g1',
  'type': 'group',
  'name': 'Hikers',
  'ownerId': owner,
  'admins': [owner],
  'participants': [
    {'_id': 'owner', 'fullName': 'Olive'},
    {'_id': 'viewer', 'fullName': 'Kristen Lama'},
    {'_id': 'maya', 'fullName': 'Maya'},
  ],
  'invites': [],
};

Future<void> go(WidgetTester tester, String location, {Object? extra}) async {
  GoRouter.of(
    tester.element(find.text('What’s on your mind?')),
  ).go(location, extra: extra);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.llfbandit.record/messages'),
          (_) async => null,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.llfbandit.record/messages'),
          null,
        );
  });

  group('CHAT-F01: attachment contract', () {
    test('the server kind decides, else the URL', () {
      expect(chatAttachmentKind(key('files', 'pdf'), 'audio'), 'audio');
      expect(chatAttachmentKind(key('audio', 'm4a')), 'audio');
      expect(chatAttachmentKind(key('audio', 'webm')), 'audio');
      expect(chatAttachmentKind(key('videos', 'webm')), 'video');
      expect(chatAttachmentKind(key('images', 'webp')), 'image');
      expect(
        chatAttachmentKind('https://media.giphy.com/media/x/giphy.gif'),
        'gif',
      );
      expect(chatAttachmentKind(key('files', 'pdf'), ''), 'file');
    });

    test(
      'captions are optional; placeholder text from older clients is hidden',
      () {
        expect(chatCaption('  sunset ', true), 'sunset');
        expect(chatCaption('Voice message', true), '');
        expect(chatCaption('Sent 2 photos', true), '');
        expect(chatCaption('📎 report.pdf', true), '');
        expect(chatCaption('Voice message', false), 'Voice message');
      },
    );
  });

  group('CHAT-F03: read positions', () {
    test(
      'loading marks nothing by itself; one read up to the newest message shown',
      () async {
        final realtime = RealtimeService(Harness().api);
        final api = ReadApi();
        final bloc = ChatBloc(api, realtime, 'c1');
        await bloc.stream.firstWhere(
          (s) => s.messages.length == 2 && !s.loading,
        );
        expect(api.calls, ['GET conversations/c1/messages']);
        await Future<void>.delayed(const Duration(milliseconds: 1200));
        expect(api.calls, [
          'GET conversations/c1/messages',
          'PATCH conversations/c1/read',
        ]);
        expect(api.bodies.last, {'upTo': 'newest'});
        await bloc.close();
      },
    );

    test(
      'incoming messages are read up to the newest one; membership changes reload',
      () async {
        final realtime = RealtimeService(Harness().api);
        final api = ReadApi();
        final bloc = ChatBloc(api, realtime, 'c1');
        await bloc.stream.firstWhere(
          (s) => s.messages.length == 2 && !s.loading,
        );
        for (var i = 0; i < 3; i++) {
          realtime.events.add(
            RealtimeEvent('chat:message', {
              'conversationId': 'c1',
              'message': {
                '_id': 'm$i',
                'body': '',
                'createdAt': '2026-10-02T00:00:0${i}Z',
              },
            }),
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 1200));
        expect(api.calls.where((c) => c.startsWith('PATCH')), hasLength(1));
        expect(api.bodies.last, {'upTo': 'm2'});
        realtime.events.add(
          const RealtimeEvent('chat:conversation_changed', {
            'conversationId': 'c1',
            'reason': 'removed',
          }),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(
          api.calls.where((c) => c == 'GET conversations/c1/messages'),
          hasLength(2),
        );
        await bloc.close();
      },
    );
  });

  testWidgets(
    'CHAT-S01: invitations can be declined or accepted from the chat list',
    (tester) async {
      final h = Harness(
        fixtures: {
          'conversations': [],
          'conversations/invites': [
            {
              'conversationId': 'g1',
              'name': 'Hikers',
              'memberCount': 3,
              'invitedAt': '',
              'invitedBy': {'_id': 'maya', 'fullName': 'Maya'},
            },
          ],
        },
      );
      await h.mount(tester);
      await go(tester, '/messages');
      expect(find.text('Group invitations'), findsOneWidget);
      expect(find.text('Hikers'), findsOneWidget);
      expect(
        find.textContaining('Maya invited you · 3 members'),
        findsOneWidget,
      );
      await tester.tap(find.text('Decline'));
      await tester.pumpAndSettle();
      expect(
        h.calls.where(
          (r) =>
              r.method == 'POST' &&
              r.path == 'conversations/g1/invites/decline',
        ),
        hasLength(1),
      );
      await tester.tap(find.text('Join'));
      await tester.pumpAndSettle();
      expect(
        h.calls.where(
          (r) =>
              r.method == 'POST' && r.path == 'conversations/g1/invites/accept',
        ),
        hasLength(1),
      );
    },
  );

  testWidgets('CHAT-S01: a plain member only sees Leave; leaving asks first', (
    tester,
  ) async {
    final h = Harness(fixtures: {'conversations/g1/messages': []});
    await h.mount(tester);
    await go(tester, '/messages/g1', extra: groupJson(owner: 'owner'));
    await tester.tap(find.byTooltip('Chat options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Group members'));
    await tester.pumpAndSettle();
    expect(find.text('Owner'), findsOneWidget);
    expect(find.byTooltip('Member options for Maya'), findsNothing);
    await tester.tap(find.text('Leave group'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('You will need a new invitation'),
      findsOneWidget,
    );
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(
      h.calls.where(
        (r) => r.method == 'POST' && r.path == 'conversations/g1/leave',
      ),
      hasLength(1),
    );
  });

  testWidgets(
    'CHAT-S01: the owner can remove members, change admins and transfer ownership',
    (tester) async {
      final h = Harness(
        fixtures: {
          'conversations/g1/messages': [],
          'conversations': [groupJson(owner: 'viewer')],
        },
      );
      await h.mount(tester);
      await go(tester, '/messages/g1', extra: groupJson(owner: 'viewer'));
      await tester.tap(find.byTooltip('Chat options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Group members'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Member options for Maya'));
      await tester.pumpAndSettle();
      expect(find.text('Make admin'), findsOneWidget);
      expect(find.text('Make owner'), findsOneWidget);
      await tester.tap(find.text('Remove from group'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(
        h.calls.where(
          (r) =>
              r.method == 'DELETE' && r.path == 'conversations/g1/members/maya',
        ),
        hasLength(1),
      );
    },
  );
}
