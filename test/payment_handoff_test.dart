import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';
import 'package:twon_mobile/core/api.dart';
import 'package:twon_mobile/core/env_config.dart';
import 'package:twon_mobile/core/theme.dart';
import 'package:twon_mobile/features/shop/shop_cubit.dart';
import 'package:twon_mobile/features/shop/shop_pages.dart';

class MockRepository extends Mock implements AppRepository {}

class BrowserLauncher extends UrlLauncherPlatform {
  @override
  get linkDelegate => null;
  String? launched;
  LaunchOptions? options;
  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched = url;
    this.options = options;
    return true;
  }
}

void main() {
  test(
    'website checkout encodes regional basket and optional pending order without tokens',
    () {
      final url = Uri.parse(
        AppConfig.paymentUrl(currency: 'npr', orderId: 'a' * 24),
      );
      expect(url.path, '/merch/pay');
      expect(url.queryParameters, {'currency': 'npr', 'order': 'a' * 24});
      expect(url.userInfo, isEmpty);
      expect(AppConfig.paymentUrl(currency: 'gbp'), contains('currency=gbp'));
    },
  );
  testWidgets(
    'payment uses an external browser, collects no card details and makes no checkout API call',
    (tester) async {
      final api = MockRepository();
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final shop = ShopCubit(api, preferences, 'NP');
      final launcher = BrowserLauncher();
      final previous = UrlLauncherPlatform.instance;
      UrlLauncherPlatform.instance = launcher;
      addTearDown(() => UrlLauncherPlatform.instance = previous);
      addTearDown(shop.close);
      await tester.pumpWidget(
        BlocProvider.value(
          value: shop,
          child: MaterialApp(
            theme: twonTheme(Brightness.dark),
            home: const Scaffold(body: CheckoutSheet()),
          ),
        ),
      );
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Pay on the website'), findsOneWidget);
      await tester.tap(find.text('Continue on website'));
      await tester.pumpAndSettle();
      expect(Uri.parse(launcher.launched!).queryParameters['currency'], 'npr');
      expect(launcher.options!.mode, PreferredLaunchMode.externalApplication);
      verifyZeroInteractions(api);
    },
  );
  testWidgets('website handoff scrolls on a small screen with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final shop = ShopCubit(
      MockRepository(),
      await SharedPreferences.getInstance(),
      'GB',
    );
    addTearDown(shop.close);
    await tester.pumpWidget(
      BlocProvider.value(
        value: shop,
        child: MaterialApp(
          theme: twonTheme(Brightness.dark),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 568),
              textScaler: TextScaler.linear(1.8),
            ),
            child: const Scaffold(body: CheckoutSheet()),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('Continue on website'), 200);
    expect(find.text('Continue on website').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
