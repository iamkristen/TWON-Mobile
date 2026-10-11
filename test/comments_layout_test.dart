import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'social_experience_test.dart' show Harness;

void main() {
  testWidgets(
    'minimal comments supports likes, replies and own-comment actions on a narrow screen',
    (tester) async {
      final h = Harness(
        fixtures: {
          'posts/post-0/comments': [
            {
              'id': 'c1',
              'authorId': {'id': 'viewer', 'fullName': 'Demo Explorer'},
              'text': 'See you there!',
              'likes': [],
              'likeCount': 2,
            },
            {
              'id': 'c2',
              'authorId': {'id': 'maya', 'fullName': 'Maya'},
              'text': 'Looking forward to it.',
              'parentCommentId': 'c1',
              'likes': [],
              'likeCount': 0,
            },
          ],
        },
      );
      await h.mount(tester, width: 320);
      await tester.ensureVisible(find.byTooltip('Comment').first);
      await tester.tap(find.byTooltip('Comment').first);
      await tester.pumpAndSettle();
      expect(find.text('Comments'), findsOneWidget);
      expect(find.text('See you there!'), findsOneWidget);
      await tester.tap(find.byTooltip('Like comment').first);
      await tester.pumpAndSettle();
      expect(
        h.calls.any(
          (r) =>
              r.path == 'posts/post-0/comments/c1/like' && r.method == 'POST',
        ),
        isTrue,
      );
      await tester.tap(find.text('Reply').first);
      await tester.pumpAndSettle();
      expect(find.text('Replying to Demo Explorer'), findsOneWidget);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Count me in');
      await tester.pump();
      await tester.tap(find.byTooltip('Send reply'));
      await tester.pumpAndSettle();
      final sent = h.calls.lastWhere(
        (r) => r.path == 'posts/post-0/comments' && r.method == 'POST',
      );
      expect(sent.data, {'text': 'Count me in', 'parentCommentId': 'c1'});
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Comment options'));
      await tester.pumpAndSettle();
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await h.close(tester);
    },
  );
}
