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
      expect(find.text('Cancel deletion request'), findsNothing);
      final card = tester.getRect(find.byType(Card));
      expect(card.center.dx, closeTo(195, 1));
      expect(card.center.dy, closeTo(422, 1));
      expect(tester.takeException(), isNull);
      await tester.tap(find.byType(TextFormField).first);
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isTrue);
      await tester.tap(find.text('Welcome back to the pack.'));
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isFalse);
      await tester.tap(find.byType(TextFormField).first);
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isTrue);
      await tester.dragFrom(
        tester.getTopLeft(find.byType(Card)) + const Offset(10, 10),
        const Offset(0, -80),
      );
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isFalse);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Sign in').first);
      expect(tester.takeException(), isNull);
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Join the pack'));
      await tester.pumpAndSettle();
      expect(find.text('Find your pack.'), findsOneWidget);
      expect(find.byType(TextFormField), findsNWidgets(4));
      tester.view.physicalSize = const Size(320, 568);
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Create account'));
      expect(find.text('Create account').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Back to sign in'));
      await tester.tap(find.text('Back to sign in'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Forgot password?'));
      await tester.tap(find.text('Forgot password?'));
      await tester.pumpAndSettle();
      expect(find.text('Reset your password'), findsOneWidget);
      await tester.ensureVisible(find.text('Continue'));
      expect(find.text('Continue').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      tester.view.resetViewInsets();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await api.expired.close();
      await api.tokensChanged.close();
    },
  );
}
