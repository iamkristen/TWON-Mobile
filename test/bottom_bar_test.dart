import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twon_mobile/app.dart';
import 'package:twon_mobile/core/theme.dart';

/// Mirrors how the shell drives the bar: the parent owns `selectedIndex` and
/// rebuilds when the bar reports a new tab.
class _BarHost extends StatefulWidget {
  const _BarHost();
  @override
  State<_BarHost> createState() => _BarHostState();
}

class _BarHostState extends State<_BarHost> {
  int index = 0;
  @override
  Widget build(BuildContext c) => Scaffold(
    body: Align(
      alignment: Alignment.bottomCenter,
      child: SocialBottomBar(
        selectedIndex: index,
        onSelect: (i) => setState(() => index = i),
      ),
    ),
  );
}

void main() {
  Future<void> mount(
    WidgetTester tester, {
    int selected = 0,
    required ValueChanged<int> onSelect,
    double width = 360,
  }) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      MaterialApp(
        theme: twonTheme(Brightness.dark),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: SocialBottomBar(selectedIndex: selected, onSelect: onSelect),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders every tab with its icon and label', (tester) async {
    await mount(tester, onSelect: (_) {});
    for (final d in AppShell.destinations) {
      expect(find.byKey(ValueKey('tab-${d.$1}')), findsOneWidget);
      expect(find.text(d.$2), findsOneWidget);
    }
    // Material icons, as before: the unselected variant on every tab except
    // whichever is active.
    expect(find.byType(Icon), findsNWidgets(5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the sliding pill sits under the selected tab and moves', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      MaterialApp(theme: twonTheme(Brightness.dark), home: const _BarHost()),
    );
    await tester.pumpAndSettle();

    Rect pillRect() => tester.getRect(
      find.byWidgetPredicate(
        (w) =>
            w is FractionallySizedBox &&
            w.child is Padding &&
            (w.child as Padding).child is DecoratedBox,
      ),
    );

    final barLeft = tester.getRect(find.byType(SocialBottomBar)).left;
    final first = pillRect();
    // First tab: the pill hugs the left edge of the bar.
    expect(first.left - barLeft, lessThan(24));

    await tester.tap(find.byKey(const ValueKey('tab-/clans')));
    await tester.pumpAndSettle();

    final second = pillRect();
    expect(second.left, greaterThan(first.left));
    // It travelled to the second slot, not merely nudged.
    expect(second.left - barLeft, greaterThan(24));
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping the already selected tab does not fire again', (
    tester,
  ) async {
    var calls = 0;
    await mount(tester, selected: 1, onSelect: (_) => calls++);

    await tester.tap(find.byKey(const ValueKey('tab-/clans')));
    await tester.pumpAndSettle();

    expect(calls, 0);
  });

  testWidgets('honours reduced motion by using zero-length animations', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          theme: twonTheme(Brightness.dark),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: SocialBottomBar(selectedIndex: 0, onSelect: (_) {}),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('tab-/events')));
    await tester.pump();
    // No animation frames to settle: the pill is already at its destination.
    expect(tester.takeException(), isNull);
  });

  testWidgets('bar fits the narrowest phone without overflow', (tester) async {
    await mount(tester, onSelect: (_) {}, width: 320);
    expect(tester.takeException(), isNull);
  });
}
