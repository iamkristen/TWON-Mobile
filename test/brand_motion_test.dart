import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twon_mobile/core/theme.dart';
import 'package:twon_mobile/shared/brand_motion.dart';
import 'package:twon_mobile/shared/widgets.dart';

Widget host(
  Widget child, {
  bool reduce = false,
  ThemeMode mode = ThemeMode.dark,
}) => MaterialApp(
  theme: twonTheme(Brightness.light),
  darkTheme: twonTheme(Brightness.dark),
  themeMode: mode,
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduce),
    child: Scaffold(body: Center(child: child)),
  ),
);

void main() {
  testWidgets('MoonPulseLoader announces its label and pulses', (t) async {
    await t.pumpWidget(host(const MoonPulseLoader(label: 'Finding your pack')));
    expect(find.bySemanticsLabel('Finding your pack…'), findsOneWidget);
    expect(t.binding.hasScheduledFrame, isTrue);
  });

  testWidgets('MoonPulseLoader is still under reduced motion', (t) async {
    await t.pumpWidget(host(const MoonPulseLoader(), reduce: true));
    await t.pumpAndSettle(); // would time out if the pulse kept looping
    expect(find.text('Loading…'), findsOneWidget);
  });

  testWidgets('TwonSplash reveals the mark and tagline in both themes', (
    t,
  ) async {
    for (final mode in [ThemeMode.dark, ThemeMode.light]) {
      await t.pumpWidget(host(const TwonSplash(), reduce: true, mode: mode));
      await t.pumpAndSettle();
      expect(find.bySemanticsLabel('The Wolves of Nepal'), findsOneWidget);
    }
  });

  testWidgets(
    'StealthEntrance renders its child immediately under reduced motion',
    (t) async {
      await t.pumpWidget(
        host(const StealthEntrance(child: Text('Pack')), reduce: true),
      );
      expect(find.byType(Opacity), findsNothing);
      expect(find.text('Pack'), findsOneWidget);
    },
  );

  testWidgets('ErrorPanel keeps a 44px+ "Try again" action that retries', (
    t,
  ) async {
    var retries = 0;
    await t.pumpWidget(host(ErrorPanel('Offline', retry: () => retries++)));
    final button = find.widgetWithText(FilledButton, 'Try again');
    expect(button, findsOneWidget);
    expect(t.getSize(button).height, greaterThanOrEqualTo(44));
    await t.tap(button);
    expect(retries, 1);
  });

  testWidgets('primary buttons press to 0.97 and stay flat when disabled', (
    t,
  ) async {
    await t.pumpWidget(
      host(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton(onPressed: () {}, child: const Text('Join')),
            const FilledButton(onPressed: null, child: Text('Off')),
          ],
        ),
      ),
    );
    double scaleOf(String label) => t
        .widget<AnimatedScale>(
          find
              .ancestor(
                of: find.text(label),
                matching: find.byType(AnimatedScale),
              )
              .first,
        )
        .scale;
    expect(scaleOf('Join'), 1);
    final gesture = await t.startGesture(t.getCenter(find.text('Join')));
    await t.pump();
    expect(scaleOf('Join'), .97);
    await gesture.up();
    await t.pumpAndSettle();
    expect(scaleOf('Join'), 1);
    expect(scaleOf('Off'), 1);
    expect(TwonMotion.base, const Duration(milliseconds: 200));
  });
}
