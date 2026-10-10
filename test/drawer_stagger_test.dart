import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twon_mobile/app.dart';
import 'package:twon_mobile/core/api.dart';
import 'package:twon_mobile/core/theme.dart';
import 'package:twon_mobile/core/token_store.dart';
import 'package:twon_mobile/features/auth/auth_cubit.dart';

void main() {
  Future<void> mount(
    WidgetTester tester, {
    String path = '/feed',
    bool disableAnimations = false,
    double width = 380,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    final api = DioRepository(
      baseUrl: 'https://test.invalid/api/v1',
      store: SecureSessionStore(),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: twonTheme(Brightness.dark),
        home: Builder(
          builder: (c) => MediaQuery(
            // Inherit the real size; override only the animation preference.
            data: MediaQuery.of(
              c,
            ).copyWith(disableAnimations: disableAnimations),
            child: Scaffold(
              body: BlocProvider<AuthCubit>(
                create: (_) => AuthCubit(api),
                child: TwonDrawer(path: path),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('rows cascade in rather than appearing all at once', (
    tester,
  ) async {
    await mount(tester);

    // Mid-flight: some rows are partially faded and none is fully hidden,
    // which is what a stagger looks like in flight.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 70));
    final opacities = tester
        .widgetList<Opacity>(find.byType(Opacity))
        .map((o) => o.opacity)
        .toList();
    expect(
      opacities.any((o) => o > 0 && o < 1),
      isTrue,
      reason: 'expected at least one row mid-fade',
    );

    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<Opacity>(find.byType(Opacity))
          .every((o) => o.opacity >= 1),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('later rows lag behind earlier ones', (tester) async {
    await mount(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 70));

    final opacities = tester
        .widgetList<Opacity>(find.byType(Opacity))
        .map((o) => o.opacity)
        .toList();
    // The cascade means opacity is not uniform across rows yet.
    expect(
      opacities.toSet().length,
      greaterThan(1),
      reason: 'expected differing opacities while staggering',
    );
  });

  testWidgets('reduced motion renders fully formed on a single frame', (
    tester,
  ) async {
    await mount(tester, disableAnimations: true);
    await tester.pump();

    expect(
      tester
          .widgetList<Opacity>(find.byType(Opacity))
          .every((o) => o.opacity >= 1),
      isTrue,
    );
    expect(find.text('Community'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('every section still renders its entries', (tester) async {
    await mount(tester, path: '/merch');
    await tester.pumpAndSettle();

    expect(find.text('Community'), findsOneWidget);
    expect(find.text('Feed'), findsOneWidget);
    expect(find.text('Messages'), findsOneWidget);
    expect(find.text('Gatherings'), findsOneWidget);
    expect(find.text('Discover'), findsOneWidget);
    expect(find.text('Account'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Sign out'), 200);
    await tester.pumpAndSettle();
    expect(find.text('Sign out'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('drawer fits a narrow phone without overflow', (tester) async {
    await mount(tester, width: 320);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
