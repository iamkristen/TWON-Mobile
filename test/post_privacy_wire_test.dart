import 'package:flutter_test/flutter_test.dart';
import 'package:twon_mobile/core/models.dart';
import 'social_experience_test.dart' show Harness, samplePost;

// Mirrors the backend F-02 placeholder (`post-privacy.ts::ANONYMOUS_AUTHOR_ID`).
const anonymousAuthor = {
  '_id': '000000000000000000000000',
  'handle': '',
  'fullName': 'Anonymous Wolf',
  'avatar': '',
};

void main() {
  test('placeholder author id never matches a viewer id', () {
    expect(entityId(anonymousAuthor), '000000000000000000000000');
    expect(entityId(anonymousAuthor) == 'viewer', isFalse);
  });

  testWidgets('masked anonymous post renders anonymously with report-only actions', (
    tester,
  ) async {
    final h = Harness(
      fixtures: {
        'posts': [
          {...samplePost(0), 'isAnonymous': true, 'authorId': anonymousAuthor},
        ],
      },
    );
    await h.mount(tester);
    expect(find.text('Anonymous Wolf'), findsOneWidget);
    expect(find.text('Aayush Shrestha'), findsNothing);
    await tester.tap(find.byTooltip('Post options').first);
    await tester.pumpAndSettle();
    expect(find.text('Report post'), findsOneWidget);
    expect(find.text('Edit post'), findsNothing);
    await h.close(tester);
  });

  testWidgets('author keeps edit actions on their own anonymous post', (
    tester,
  ) async {
    final h = Harness(
      fixtures: {
        'posts': [
          {
            ...samplePost(0),
            'isAnonymous': true,
            'authorId': {'_id': 'viewer', 'fullName': 'Demo Explorer'},
          },
        ],
      },
    );
    await h.mount(tester);
    await tester.tap(find.byTooltip('Post options').first);
    await tester.pumpAndSettle();
    expect(find.text('Edit post'), findsOneWidget);
    await h.close(tester);
  });

  testWidgets('withheld shared original renders no preview; masked original still renders', (
    tester,
  ) async {
    final h = Harness(
      fixtures: {
        'posts': [
          {...samplePost(0), 'body': 'Withheld share', 'sharedPostId': null},
          {
            ...samplePost(1),
            'body': 'Visible share',
            'sharedPostId': {
              '_id': '65f0000000000000000000bb',
              'body': 'Original body',
              'isAnonymous': true,
              'visibility': 'public',
              'authorId': anonymousAuthor,
            },
          },
        ],
      },
    );
    await h.mount(tester);
    expect(find.text('Shared with the pack'), findsOneWidget);
    expect(find.text('Original body'), findsOneWidget);
    await h.close(tester);
  });
}
