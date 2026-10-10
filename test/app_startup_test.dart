import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twon_mobile/app.dart';
import 'package:twon_mobile/core/api.dart';
import 'api_session_test.dart' show MemoryStore;

void main() {
  testWidgets(
    'starts in dark mode on sign-in and retains usable fields with the keyboard',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final api = DioRepository(
        baseUrl: 'https://test.invalid',
        store: MemoryStore(),
      );
      await tester.pumpWidget(TwonApp(api: api, preferences: preferences));
      await tester.pumpAndSettle();
      expect(find.text('Welcome back to the pack.'), findsOneWidget);
      expect(find.byType(TextFormField), findsNWidgets(2));
      expect(
        Theme.of(
          tester.element(find.text('Welcome back to the pack.')),
        ).brightness,
        Brightness.dark,
      );
      expect(tester.takeException(), isNull);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Sign in').first);
      expect(tester.takeException(), isNull);
      tester.view.resetViewInsets();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await api.expired.close();
      await api.tokensChanged.close();
    },
  );
}
