import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twon_mobile/app.dart';
import 'package:twon_mobile/core/api.dart';
import 'api_session_test.dart' show MemoryStore, ApiAdapter, response;

void main() {
  for (final succeeds in [true, false]) {
    testWidgets('password reset success=$succeeds only redirects on success', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final api = DioRepository(
        baseUrl: 'https://test.invalid/api/v1',
        store: MemoryStore(),
      );
      api.dio.httpClientAdapter = ApiAdapter((request) async {
        expect(request.path, 'auth/forgot-password');
        expect(request.data, {'email': 'member@example.com'});
        return succeeds
            ? response(200, {'success': true, 'data': {}})
            : response(500, {
                'success': false,
                'error': {'message': 'Try again later.'},
              });
      });
      await tester.pumpWidget(TwonApp(api: api, preferences: preferences));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Forgot password?'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'member@example.com');
      await tester.ensureVisible(find.text('Continue'));
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      if (succeeds) {
        expect(find.text('Welcome back to the pack.'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(SnackBar),
            matching: find.text(
              'If an account exists for this email, a password reset link has been sent.',
            ),
          ),
          findsOneWidget,
        );
      } else {
        expect(find.text('Reset your password'), findsOneWidget);
        expect(find.text('Try again later.'), findsOneWidget);
        expect(find.byType(SnackBar), findsNothing);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      api.dio.close();
      await api.expired.close();
      await api.tokensChanged.close();
    });
  }
}
