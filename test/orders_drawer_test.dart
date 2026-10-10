import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twon_mobile/app.dart';
import 'package:twon_mobile/core/api.dart';
import 'package:twon_mobile/core/token_store.dart';
import 'package:twon_mobile/features/auth/auth_cubit.dart';

void main() {
  testWidgets('My orders is reachable from the gear drawer', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider<AuthCubit>(
            create: (_) => AuthCubit(_FakeApi()),
            child: const TwonDrawer(path: '/merch'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // On the gear page the Pack Gear group starts expanded, because
    // `initiallyExpanded` is true when the current path is one of its entries.
    expect(find.text('My orders'), findsOneWidget);

    final tile = tester.widget<ListTile>(
      find.ancestor(
        of: find.text('My orders'),
        matching: find.byType(ListTile),
      ),
    );
    expect(tile.title, isA<Text>());
    expect((tile.title! as Text).data, 'My orders');
  });

  testWidgets('My orders is one tap from another section too', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider<AuthCubit>(
            create: (_) => AuthCubit(_FakeApi()),
            child: const TwonDrawer(path: '/feed'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Pack Gear'), 200);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pack Gear'));
    await tester.pumpAndSettle();

    expect(find.text('My orders'), findsOneWidget);
  });
}

class _FakeApi extends DioRepository {
  _FakeApi()
    : super(
        baseUrl: 'https://test.invalid/api/v1',
        store: SecureSessionStore(),
      );
}
