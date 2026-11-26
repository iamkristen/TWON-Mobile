import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'social_experience_test.dart' show Harness;

/// POST-1: the anonymous author of an anonymous post, as the server sends it
/// (placeholder id, no handle, `isPostAuthor`), is shown as such: no real name,
/// an "Author" label. Other commenters keep their names.
void main() {
  testWidgets(
    'an anonymous author\'s comment shows "Anonymous Wolf" and "Author"; others keep their names',
    (tester) async {
      final h = Harness(
        fixtures: {
          'posts/post-0/comments': [
            {
              'id': 'c1',
              'authorId': {
                '_id': '000000000000000000000000',
                'handle': '',
                'fullName': 'Anonymous Wolf',
                'avatar': '',
                'isPostAuthor': true,
              },
              'text': 'Context from the author',
              'likes': [],
              'likeCount': 0,
            },
            {
              'id': 'c2',
              'authorId': {'id': 'maya', 'fullName': 'Maya'},
              'text': 'A question',
              'likes': [],
              'likeCount': 0,
            },
          ],
        },
      );
      await h.mount(tester, width: 360);
      await tester.ensureVisible(
        find.byIcon(Icons.chat_bubble_outline_rounded).first,
      );
      await tester.tap(find.byIcon(Icons.chat_bubble_outline_rounded).first);
      await tester.pumpAndSettle();
      expect(find.text('Context from the author'), findsOneWidget);
      expect(find.text('Anonymous Wolf'), findsWidgets);
      expect(find.text('Author'), findsOneWidget);
      expect(find.text('Maya'), findsOneWidget);
    },
  );
}
