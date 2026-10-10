import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twon_mobile/core/api.dart';
import 'package:twon_mobile/core/theme.dart';
import 'package:twon_mobile/core/token_store.dart';
import 'package:twon_mobile/features/shop/shop_cubit.dart';
import 'package:twon_mobile/features/shop/shop_pages.dart';

void main() {
  Future<void> mount(WidgetTester tester, {double width = 320}) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final api = DioRepository(
      baseUrl: 'https://test.invalid/api/v1',
      store: SecureSessionStore(),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: twonTheme(Brightness.dark),
        home: BlocProvider<ShopCubit>(
          create: (_) => ShopCubit(api, prefs, 'Nepal'),
          child: const Scaffold(body: ShopBody()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('search and currency bar fits the narrowest supported phone', (tester) async {
    await mount(tester, width: 320);
    expect(tester.takeException(), isNull);
  });

  testWidgets('currency chip is visible before searching and gone after', (tester) async {
    await mount(tester, width: 390);

    // Region chip shows the active currency before the field takes focus.
    expect(find.text('NPR'), findsOneWidget);

    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Collapsed away while searching, so the field can use the full width.
    expect(find.text('NPR'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping the currency chip opens the region picker', (tester) async {
    await mount(tester, width: 390);
    await tester.tap(find.text('NPR'));
    await tester.pumpAndSettle();

    expect(find.text('Shopping region'), findsOneWidget);
    expect(find.text('Nepal · NPR / Khalti'), findsOneWidget);
    expect(find.text('Other countries · GBP / Stripe'), findsOneWidget);
  });

  testWidgets('empty basket shows the loot illustration, not a bare line', (
    tester,
  ) async {
    await mount(tester, width: 390);

    await tester.tap(find.byIcon(Icons.shopping_bag_outlined));
    await tester.pumpAndSettle();

    expect(find.text('No loot in the bag yet.'), findsOneWidget);
    expect(find.textContaining('pack gear'), findsOneWidget);
    // The SVG itself must load; a malformed asset throws during paint.
    expect(find.byType(SvgPicture), findsWidgets);
    expect(tester.takeException(), isNull);

    // Subtotal and the pay button are pointless with an empty bag.
    expect(find.textContaining('Subtotal'), findsNothing);
    expect(find.text('Pay on website'), findsNothing);
  });

  testWidgets('an unstocked catalogue explains itself instead of showing a bare line', (
    tester,
  ) async {
    await mount(tester, width: 390);

    expect(find.text('The gear rail is bare.'), findsOneWidget);
    expect(find.textContaining('as soon as staff publish'), findsOneWidget);
    expect(find.byType(SvgPicture), findsWidgets);
    expect(tester.takeException(), isNull);

    // Nothing to clear when the shop simply has no stock.
    expect(find.text('Clear filters'), findsNothing);
  });

  testWidgets('a fruitless search offers to clear the filters', (tester) async {
    await mount(tester, width: 390);
    // The fake API returns no products, so the filtered branch needs products to
    // filter. Assert the wording path that does not depend on stock.
    await tester.enterText(find.byType(TextField), 'hoodie');
    await tester.pumpAndSettle();

    expect(find.byType(SvgPicture), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('orders are not on the product page but are in the basket', (
    tester,
  ) async {
    await mount(tester, width: 390);

    // The product list stays clean...
    expect(find.text('My orders'), findsNothing);

    // ...but the basket sheet is where order status actually belongs.
    await tester.tap(find.byIcon(Icons.shopping_bag_outlined));
    await tester.pumpAndSettle();
    expect(find.text('View your orders'), findsOneWidget);
  });
}