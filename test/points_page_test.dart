import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'social_experience_test.dart' show Harness;

/// Pack Points 2.0 (Flutter): no fabricated points; pending never shown as confirmed.
const _rules = {
  'enabled': true,
  'version': 'v1',
  'season': {'id': '2026-S4', 'start': '2026-10-01T00:00:00Z', 'end': '2027-01-01T00:00:00Z'},
  'normalizedFloor': 5,
  'rules': {
    'post': {'enabled': true, 'disabledReason': null, 'userXp': 10, 'clanCp': 5, 'holdHours': 24, 'limits': []},
    'comment': {'enabled': true, 'disabledReason': null, 'userXp': 3, 'clanCp': 1, 'holdHours': 24, 'limits': []},
    'lookbook': {'enabled': true, 'disabledReason': null, 'userXp': 15, 'clanCp': 0, 'holdHours': 0, 'limits': []},
    'event_attendance': {
      'enabled': false,
      'disabledReason': 'No verified attendance (check-in) exists yet; RSVPs are self-declared.',
      'userXp': 25, 'clanCp': 15, 'holdHours': 0, 'limits': [],
    },
  },
};

Map<String, dynamic> _item(Map<String, dynamic> over) => {
  '_id': '${over.hashCode}', 'kind': 'award', 'sourceType': 'post', 'status': 'confirmed', 'userXp': 10, 'clanCp': 5,
  'clanId': 'c1', 'seasonId': '2026-S4', 'occurredAt': '2026-10-18T09:00:00Z', 'confirmAfter': null,
  'confirmedAt': '2026-10-19T09:00:00Z', 'reversedAt': null, 'reason': '', ...over,
};

Future<void> open(WidgetTester tester, Harness h) async {
  await h.mount(tester);
  GoRouter.of(tester.element(find.text('What’s on your mind?'))).push('/points');
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows no numbers while V2 is not live', (tester) async {
    final h = Harness(fixtures: {'points/me': {'enabled': false}, 'points/rules': {..._rules, 'enabled': false}});
    await open(tester, h);
    expect(find.text('Pack Points 2.0 isn’t live yet'), findsOneWidget);
    expect(find.text('Pending review'), findsNothing);
    expect(h.calls.where((r) => r.path == 'points/me/history'), isEmpty);
    await tester.scrollUntilVisible(find.textContaining('No verified attendance'), 200);
    expect(find.textContaining('No verified attendance'), findsOneWidget);
    await h.close(tester);
  });

  testWidgets('separates pending from confirmed and labels each history state', (tester) async {
    final h = Harness(fixtures: {
      'points/rules': _rules,
      'points/me': {
        'enabled': true,
        'season': {'id': '2026-S4', 'start': '', 'end': '', 'confirmed': 40, 'pending': 13, 'reversed': 10, 'rank': 7},
        'lifetime': {'confirmed': 340, 'pending': 13, 'reversed': 10},
        'clan': {
          'clanId': 'c1', 'name': 'Phewa Howlers', 'handle': 'phewa',
          'season': {'confirmed': 25, 'pending': 6, 'reversed': 0, 'contributors': 3, 'normalized': 5}, 'rank': 2,
        },
      },
      'points/me/history': {
        'enabled': true,
        'nextCursor': null,
        'items': [
          _item({'status': 'pending', 'confirmedAt': null}),
          _item({'kind': 'reversal', 'userXp': -10, 'clanCp': -5}),
          _item({'status': 'reversed', 'confirmedAt': null, 'sourceType': 'comment', 'userXp': 3}),
        ],
      },
      'points/leaderboard': {
        'enabled': true, 'nextCursor': null,
        'items': [{'rank': 1, 'id': 'u1', 'handle': 'luna', 'name': 'Luna', 'avatar': '', 'points': 120}],
      },
    });
    await open(tester, h);
    expect(find.text('40 XP'), findsOneWidget); // confirmed season score
    expect(find.text('13 XP'), findsOneWidget); // pending, shown separately
    expect(find.text('Not counted until confirmed'), findsOneWidget);
    expect(find.text('25 CP'), findsOneWidget);
    for (final label in ['Pending review', 'Reversed', 'Not awarded']) {
      await tester.scrollUntilVisible(find.bySemanticsLabel(RegExp('^$label:')), 200);
      expect(find.bySemanticsLabel(RegExp('^$label:')), findsOneWidget);
    }
    await tester.scrollUntilVisible(find.text('Luna'), 200);
    expect(find.text('Luna'), findsOneWidget);
    await h.close(tester);
  });
}
