import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twon_mobile/core/api.dart';
import 'package:twon_mobile/core/token_store.dart';
import 'package:twon_mobile/features/auth/auth_cubit.dart';
import 'package:twon_mobile/features/account/settings_pages.dart';
import 'package:twon_mobile/core/theme.dart';
import 'package:twon_mobile/features/account/account_pages.dart';
import 'package:twon_mobile/shared/widgets.dart';

Widget host(Widget child, {Brightness brightness = Brightness.dark}) =>
    MaterialApp(
      theme: twonTheme(brightness),
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Scaffold(body: Center(child: child)),
      ),
    );

void main() {
  testWidgets(
    'UnreadSurface announces unread rows and drops the edge once read',
    (t) async {
      final semantics = t.ensureSemantics();
      await t.pumpWidget(
        host(
          const UnreadSurface(
            unread: true,
            child: ListTile(title: Text('Maya liked your howl')),
          ),
        ),
      );
      expect(
        t.getSemantics(find.byType(UnreadSurface)),
        isSemantics(value: 'Unread'),
      );
      final edges = find.descendant(
        of: find.byType(UnreadSurface),
        matching: find.byType(Positioned),
      );
      expect(edges, findsOneWidget);
      await t.pumpWidget(
        host(
          const UnreadSurface(
            unread: false,
            child: ListTile(title: Text('Maya liked your howl')),
          ),
        ),
      );
      expect(
        find.descendant(
          of: find.byType(UnreadSurface),
          matching: find.byType(Positioned),
        ),
        findsNothing,
      );
      semantics.dispose();
    },
  );

  testWidgets('CountPill caps at 99+ and is hidden from screen readers', (
    t,
  ) async {
    await t.pumpWidget(
      host(
        const Row(
          mainAxisSize: MainAxisSize.min,
          children: [CountPill(7), CountPill(240)],
        ),
      ),
    );
    expect(find.text('7'), findsOneWidget);
    expect(find.text('99+'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(CountPill),
        matching: find.byType(ExcludeSemantics),
      ),
      findsNWidgets(2),
    );
    expect(
      t.getSize(find.byType(CountPill).first).height,
      greaterThanOrEqualTo(20),
    );
  });

  testWidgets('CountPill sizes to its label inside a ListTile trailing slot', (t) async {
    await t.pumpWidget(
      host(
        const UnreadSurface(
          unread: true,
          child: ListTile(title: Text('Maya Sherpa'), trailing: CountPill(3)),
        ),
      ),
    );
    expect(t.takeException(), isNull);
    expect(t.getSize(find.byType(CountPill)).width, lessThan(40));
  });

  test('shortTimeLabel is compact and relative', () {
    final now = DateTime(2026, 10, 17, 12);
    String at(Duration ago) =>
        shortTimeLabel(now.subtract(ago).toIso8601String(), now: now);
    expect(at(const Duration(seconds: 20)), 'now');
    expect(at(const Duration(minutes: 5)), '5m');
    expect(at(const Duration(hours: 3)), '3h');
    expect(at(const Duration(days: 2)), '2d');
    expect(at(const Duration(days: 30)), 'Sep 17');
    expect(shortTimeLabel('not a date'), '');
  });

  testWidgets(
    'BrandEmptyState keeps the wolf art decorative and the title as a heading',
    (t) async {
      final semantics = t.ensureSemantics();
      await t.pumpWidget(
        host(
          const BrandEmptyState(
            asset: 'pack-gathering',
            title: 'No chats yet',
            message: 'Say hello to the pack.',
          ),
        ),
      );
      expect(
        find.bySemanticsLabel('No chats yet'),
        findsOneWidget,
      ); // once: the art is not labelled
      expect(
        t.getSemantics(find.text('No chats yet')),
        matchesSemantics(label: 'No chats yet', isHeader: true),
      );
      semantics.dispose();
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'FollowButton: crimson Follow, quiet navy Unfollow ($brightness)',
      (t) async {
        await t.pumpWidget(
          host(
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FollowButton(userId: 'a', following: false, onChanged: () {}),
                FollowButton(userId: 'b', following: true, onChanged: () {}),
              ],
            ),
            brightness: brightness,
          ),
        );
        final follow = t.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Follow'),
        );
        final unfollow = t.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Unfollow'),
        );
        expect(follow.style, isNull); // theme primary: crimson gradient
        expect(
          unfollow.style?.foregroundColor?.resolve({}),
          TwonPalette.moonlight,
        );
        expect(find.byIcon(Icons.person_add_alt_1_rounded), findsOneWidget);
        expect(find.byIcon(Icons.check_rounded), findsOneWidget);
        expect(
          t.getSize(find.byType(FilledButton).first).height,
          greaterThanOrEqualTo(44),
        );
      },
    );
  }

  group('Phase 3: filled controls stay crimson in both themes', () {
    for (final brightness in Brightness.values) {
      testWidgets('switches and filled icon actions ($brightness)', (t) async {
        final theme = twonTheme(brightness);
        final track = theme.switchTheme.trackColor!.resolve({WidgetState.selected});
        final thumb = theme.switchTheme.thumbColor!.resolve({WidgetState.selected});
        expect(track, TwonPalette.crimson);
        expect(thumb, Colors.white);
        expect(theme.switchTheme.trackColor!.resolve({WidgetState.selected, WidgetState.disabled}), isNull);
        expect(theme.floatingActionButtonTheme.backgroundColor, TwonPalette.crimson);
        final style = TwonButtonStyles.filledIcon();
        expect(style.backgroundColor!.resolve({}), TwonPalette.crimson);
        expect(style.foregroundColor!.resolve({}), Colors.white);
      });
    }
  });

  testWidgets('settings shows account deletion as destructive and title-cases the theme', (t) async {
    SharedPreferences.setMockInitialValues({'theme': 'dark'});
    final prefs = await SharedPreferences.getInstance();
    final api = DioRepository(baseUrl: 'https://test.invalid/api/v1', store: SecureSessionStore());
    await t.pumpWidget(MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => ThemeCubit(prefs)),
        BlocProvider(create: (_) => AuthCubit(api)),
      ],
      child: MaterialApp(theme: twonTheme(Brightness.light), home: const Scaffold(body: SettingsPage())),
    ));
    final scheme = twonTheme(Brightness.light).colorScheme;
    final title = t.widget<Text>(find.text('Account deletion'));
    expect(title.style?.color, scheme.error);
    expect(t.widget<Text>(find.text('Password')).style?.color, isNull);
    expect(find.text('Dark'), findsOneWidget);
    expect(find.text('dark'), findsNothing);
  });
}
