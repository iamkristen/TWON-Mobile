import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:twon_mobile/core/models.dart';
import 'social_experience_test.dart' show Harness;

/// CHAT-2 on Mobile: message requests, group management (also from a deep
/// link), clan moderation, decisions and appeals.
Json groupJson(String owner) => {
  '_id': 'g1',
  'type': 'group',
  'name': 'Hikers',
  'ownerId': owner,
  'admins': [owner],
  'participants': [
    {'_id': 'viewer', 'fullName': 'Kristen Lama'},
    {'_id': 'maya', 'fullName': 'Maya'},
  ],
  'invites': [
    {
      'userId': {'_id': 'ned', 'fullName': 'Ned'},
    },
  ],
};

Future<void> go(WidgetTester tester, String location) async {
  GoRouter.of(tester.element(find.text('What’s on your mind?'))).go(location);
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

List<String> writes(Harness h) => [
  for (final r in h.calls)
    if (r.method != 'GET' && !r.path.endsWith('/read')) '${r.method} ${r.path}',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.llfbandit.record/messages');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() => messenger.setMockMethodCallHandler(channel, (_) async => null));
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  Json requests() => {
    'conversations': [],
    'conversations/requests': [
      {
        'conversationId': 'c9',
        'from': {'_id': 'maya', 'fullName': 'Maya'},
        'preview': 'hello there',
        'sentAt': '',
      },
    ],
  };
  testWidgets('a request is declined without opening it', (tester) async {
    final h = Harness(fixtures: requests());
    await h.mount(tester);
    await go(tester, '/messages');
    expect(find.text('hello there'), findsOneWidget);
    await tap(tester, find.text('Decline'));
    expect(writes(h), ['POST conversations/c9/request/decline']);
  });
  testWidgets('blocking asks first, then declines and blocks', (tester) async {
    final h = Harness(fixtures: requests());
    await h.mount(tester);
    await go(tester, '/messages');
    await tap(tester, find.text('Block'));
    expect(writes(h), isEmpty);
    await tap(tester, find.text('Confirm'));
    expect(writes(h), [
      'POST conversations/c9/request/decline',
      'POST users/me/blocked-users',
    ]);
  });
  testWidgets('an incoming request opened by link can be accepted', (
    tester,
  ) async {
    final h = Harness(
      fixtures: {
        'conversations/c9': {
          '_id': 'c9',
          'type': 'dm',
          'requestState': 'incoming',
          'participants': [
            {'_id': 'viewer'},
            {'_id': 'maya', 'fullName': 'Maya'},
          ],
        },
        'conversations/c9/messages': [],
      },
    );
    await h.mount(tester);
    await go(tester, '/messages/c9');
    await tap(tester, find.text('Accept'));
    expect(writes(h), ['POST conversations/c9/request/accept']);
  });

  testWidgets(
    'CHAT-1 gap: a chat opened without data (Join, deep link) has its members menu',
    (tester) async {
      final h = Harness(
        fixtures: {
          'conversations/g1': groupJson('viewer'),
          'conversations/g1/messages': [],
        },
      );
      await h.mount(tester);
      await go(tester, '/messages/g1');
      await tap(tester, find.byTooltip('Chat options'));
      await tap(tester, find.text('Group members'));
      await tap(tester, find.text('Withdraw'));
      await tap(tester, find.text('Rename'));
      await tap(tester, find.text('OK'));
      expect(writes(h), [
        'DELETE conversations/g1/invites/ned',
        'PATCH conversations/g1',
      ]);
    },
  );
  testWidgets('a plain member manages nothing', (tester) async {
    final h = Harness(
      fixtures: {
        'conversations/g1': groupJson('maya'),
        'conversations/g1/messages': [],
      },
    );
    await h.mount(tester);
    await go(tester, '/messages/g1');
    await tap(tester, find.byTooltip('Chat options'));
    await tap(tester, find.text('Group members'));
    expect(find.text('Ned'), findsOneWidget);
    for (final label in ['Withdraw', 'Rename', 'Change image', 'Invite']) {
      expect(find.text(label), findsNothing);
    }
  });

  Json clan(bool canModerate) => {
    'conversations/k1': {
      '_id': 'k1',
      'type': 'group',
      'clanId': 'x',
      'name': 'Clan',
      'participants': [
        {'_id': 'lead', 'fullName': 'Lead'},
        {'_id': 'viewer', 'fullName': 'Kristen Lama'},
        {'_id': 'zed', 'fullName': 'Zed'},
      ],
    },
    'conversations/k1/messages': [
      {
        '_id': 'm1',
        'senderId': {'_id': 'zed', 'fullName': 'Zed'},
        'body': 'rude',
        'createdAt': '2026-11-20T10:00:00Z',
        'reactions': [],
      },
    ],
    'moderation/chats/k1': {
      'canModerate': canModerate,
      'isLeader': false,
      'moderators': ['lead', if (canModerate) 'viewer'],
      'restrictions': [],
    },
  };
  testWidgets('a clan moderator removes a message and restricts a member', (
    tester,
  ) async {
    final h = Harness(fixtures: clan(true));
    await h.mount(tester);
    await go(tester, '/messages/k1');
    await tester.longPress(find.byKey(const ValueKey('message-bubble-m1')));
    await tester.pumpAndSettle();
    await tap(tester, find.text('Remove as moderator'));
    await tap(tester, find.text('Hate speech'));
    await tap(tester, find.byTooltip('Chat options'));
    await tap(tester, find.text('Chat moderation'));
    expect(find.byTooltip('Moderation options for Lead'), findsNothing);
    await tap(tester, find.byTooltip('Moderation options for Zed'));
    await tap(tester, find.text('Restrict posting'));
    await tap(tester, find.text('Spam'));
    expect(writes(h), [
      'POST moderation/chats/k1/messages/m1/remove',
      'POST moderation/chats/k1/restrictions',
    ]);
  });
  testWidgets('a clan member gets no moderation actions', (tester) async {
    final h = Harness(fixtures: clan(false));
    await h.mount(tester);
    await go(tester, '/messages/k1');
    await tester.longPress(find.byKey(const ValueKey('message-bubble-m1')));
    await tester.pumpAndSettle();
    expect(find.text('Report message'), findsOneWidget);
    expect(find.text('Remove as moderator'), findsNothing);
  });

  testWidgets('a decision is appealed with a reason', (tester) async {
    final h = Harness(
      fixtures: {
        'moderation/mine': [
          {
            'id': 'a1',
            'action': 'restrict',
            'by': 'staff',
            'reasonCode': 'spam',
            'canAppeal': true,
          },
        ],
      },
    );
    await h.mount(tester);
    await go(tester, '/settings/moderation');
    await tap(tester, find.text('Appeal'));
    await tester.enterText(find.byType(EditableText).last, 'short');
    await tester.pump();
    await tap(tester, find.text('Send appeal'));
    expect(writes(h), isEmpty);
    await tester.enterText(find.byType(EditableText).last, 'this was not spam');
    await tester.pump();
    await tap(tester, find.text('Send appeal'));
    expect(writes(h), ['POST moderation/appeals']);
  });
}
