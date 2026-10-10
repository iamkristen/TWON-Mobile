import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:twon_mobile/core/models.dart';
import 'package:twon_mobile/features/chat/message_actions.dart';
import 'social_experience_test.dart' show Harness;

Json chatMessage({bool deleted = false}) => {
  'id': 'm1',
  'senderId': {'id': 'maya', 'fullName': 'Maya Sherpa'},
  'body': deleted ? '' : 'See you at the gathering!',
  'isDeleted': deleted,
  'createdAt': '2026-10-08T10:00:00Z',
  'reactions': [
    {'emoji': '❤️', 'userId': 'viewer'},
    {'emoji': '❤️', 'userId': 'other'},
  ],
};
Future<void> openChat(WidgetTester tester, Harness h) async {
  GoRouter.of(
    tester.element(find.text('What’s on your mind?')),
  ).go('/messages/c1');
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

  testWidgets(
    'long press opens reaction menu; swipe reply focuses composer and sends reply id',
    (tester) async {
      final h = Harness(
        fixtures: {
          'conversations/c1/messages': [chatMessage()],
        },
      );
      await h.mount(tester);
      await openChat(tester, h);
      final bubble = find.byKey(const ValueKey('message-bubble-m1'));
      await tester.longPress(bubble);
      await tester.pumpAndSettle();
      expect(find.text('Message actions'), findsOneWidget);
      expect(find.text('Edit message'), findsNothing);
      await tester.tap(find.text('Reply'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Cancel reply'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
        isTrue,
      );
      await tester.tap(find.byTooltip('Cancel reply'));
      await tester.drag(bubble, const Offset(100, 0));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Cancel reply'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'I will be there');
      await tester.tap(find.byTooltip('Send message'));
      await tester.pumpAndSettle();
      final write = h.calls.lastWhere(
        (r) => r.path == 'conversations/c1/messages' && r.method == 'POST',
      );
      expect(asJson(write.data)['replyTo'], 'm1');
      expect(asJson(write.data)['body'], 'I will be there');
      await h.close(tester);
    },
  );

  testWidgets(
    'double tap expands emoji choices; counts group and tapping own reaction removes it',
    (tester) async {
      final fixtures = <String, dynamic>{
        'conversations/c1/messages': [chatMessage()],
      };
      fixtures['conversations/c1/messages/m1/reactions'] = {
        ...chatMessage(),
        'senderId': 'maya',
        'reactions': [
          {'emoji': '🔥', 'userId': 'viewer'},
        ],
      };
      final h = Harness(fixtures: fixtures);
      await h.mount(tester);
      await openChat(tester, h);
      expect(find.text('❤️ 2'), findsOneWidget);
      final bubble = find.byKey(const ValueKey('message-bubble-m1'));
      await tester.tap(bubble);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(bubble);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More reactions'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('react-🔥')));
      await tester.pumpAndSettle();
      final add = h.calls.lastWhere((r) => r.path.endsWith('/reactions'));
      expect(add.method, 'POST');
      expect(asJson(add.data)['emoji'], '🔥');
      expect(find.text('🔥 1'), findsOneWidget);
      expect(find.text('Maya Sherpa'), findsOneWidget);
      fixtures['conversations/c1/messages/m1/reactions'] = {
        ...chatMessage(),
        'reactions': [],
      };
      await tester.tap(find.byKey(const ValueKey('reaction-🔥')));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(
        h.calls.lastWhere((r) => r.path.endsWith('/reactions')).method,
        'DELETE',
      );
      expect(find.text('🔥 1'), findsNothing);
      await h.close(tester);
    },
  );

  testWidgets('deleted messages ignore reply and context gestures', (
    tester,
  ) async {
    final h = Harness(
      fixtures: {
        'conversations/c1/messages': [chatMessage(deleted: true)],
      },
    );
    await h.mount(tester);
    await openChat(tester, h);
    final bubble = find.byKey(const ValueKey('message-bubble-m1'));
    await tester.longPress(bubble);
    await tester.drag(bubble, const Offset(100, 0));
    await tester.pumpAndSettle();
    expect(find.text('Message actions'), findsNothing);
    expect(find.byTooltip('Cancel reply'), findsNothing);
    await h.close(tester);
  });

  testWidgets(
    'reaction menu fits narrow screens and large text without losing draft',
    (tester) async {
      final fonts = FontLoader('Inter')
        ..addFont(rootBundle.load('assets/fonts/Inter-Regular.ttf'))
        ..addFont(rootBundle.load('assets/fonts/Inter-Bold.ttf'));
      await fonts.load();
      final h = Harness(
        fixtures: {
          'conversations/c1/messages': [chatMessage()],
        },
      );
      await h.mount(tester, width: 320, scale: 1.8);
      await openChat(tester, h);
      await tester.enterText(find.byType(TextField), 'Keep my draft');
      await tester.longPress(find.byKey(const ValueKey('message-bubble-m1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More reactions'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byKey(const ValueKey('react-🤔')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('react-🤔')).hitTestable(),
        findsOneWidget,
      );
      await tester.ensureVisible(find.byTooltip('Close message actions'));
      await tester.tap(find.byTooltip('Close message actions'));
      await tester.pumpAndSettle();
      expect(find.text('Keep my draft'), findsOneWidget);
      expect(h.calls.where((r) => r.path.endsWith('/reactions')), isEmpty);
      expect(tester.takeException(), isNull);
      await h.close(tester);
    },
  );

  testWidgets(
    'own message offers copy edit delete and selected reaction can be removed',
    (tester) async {
      MessageActionResult? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (c) => TextButton(
                child: const Text('Actions'),
                onPressed: () async {
                  result = await showMessageActions(
                    context: c,
                    message: Entity({...chatMessage(), 'senderId': 'viewer'}),
                    userId: 'viewer',
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Actions'));
      await tester.pumpAndSettle();
      expect(find.text('Edit message'), findsOneWidget);
      expect(find.text('Copy message'), findsOneWidget);
      expect(find.text('Delete for everyone'), findsOneWidget);
      expect(find.byTooltip('Remove ❤️ reaction'), findsOneWidget);
      await tester.tap(find.byTooltip('Remove ❤️ reaction'));
      await tester.pumpAndSettle();
      expect(result?.emoji, '❤️');
    },
  );
}
