import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:twon_mobile/core/api.dart';
import 'package:twon_mobile/features/auth/auth_cubit.dart';
import 'api_session_test.dart' show ApiAdapter;
import 'social_experience_test.dart' show Harness, viewer;

/// SEC-007/009 (Flutter): 2FA setup and enable send the current password, the
/// fresh session returned by enable replaces the old one, and the disable form
/// names both accepted factors.
Future<void> open(WidgetTester tester, Harness h) async {
  await h.mount(tester);
  GoRouter.of(tester.element(find.text('What’s on your mind?'))).push('/settings/2fa');
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('setup and enable send the password; enable keeps this device signed in', (tester) async {
    final h = Harness(fixtures: {
      'auth/2fa/status': {'enabled': false},
      'auth/2fa/setup': {'secret': 'SECRETSECRETSECR', 'otpauthUrl': 'otpauth://totp/TWON:viewer?secret=S', 'message': 'ok'},
      'auth/2fa/enable': {
        'message': 'enabled',
        'recoveryCodes': ['ABCD-EFGH', 'JKLM-NPQR'],
        'accessToken': 'fresh-access',
        'refreshToken': 'fresh-refresh',
        'user': viewer,
      },
    });
    await open(tester, h);

    await tester.enterText(find.widgetWithText(TextFormField, 'Current password'), 'Passw0rd!');
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();
    final setup = h.calls.singleWhere((r) => r.path == 'auth/2fa/setup');
    expect(setup.data, {'currentPassword': 'Passw0rd!'});

    await tester.enterText(find.widgetWithText(TextFormField, 'Six-digit code'), '123456');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    final enable = h.calls.singleWhere((r) => r.path == 'auth/2fa/enable');
    expect(enable.data, {'token': '123456', 'currentPassword': 'Passw0rd!'});
    expect(h.store.value?['accessToken'], 'fresh-access');
    expect(h.store.value?['refreshToken'], 'fresh-refresh');
    expect(find.textContaining('ABCD-EFGH'), findsOneWidget);
    await h.close(tester);
  });

  testWidgets('the disable form accepts an authenticator code or a recovery code', (tester) async {
    final h = Harness(fixtures: {'auth/2fa/status': {'enabled': true}});
    await open(tester, h);
    expect(find.text('Authenticator code or recovery code (XXXX-XXXX)'), findsOneWidget);
    await h.close(tester);
  });

  test('an expired 2FA step returns to the password step with an explanation', () async {
    final api = DioRepository(baseUrl: 'https://test.invalid/api/v1', store: Harness().store);
    api.dio.httpClientAdapter = ApiAdapter((r) async {
      final body = r.path == 'auth/login'
          ? {'success': true, 'data': {'requiresTwoFactor': true, 'tempToken': 'pending'}}
          : {'success': false, 'error': {'code': 'TWO_FACTOR_SESSION_EXPIRED', 'message': 'This verification step has expired. Sign in again.'}};
      return ResponseBody.fromString(jsonEncode(body), r.path == 'auth/login' ? 200 : 401, headers: {
        Headers.contentTypeHeader: ['application/json'],
      });
    });
    final cubit = AuthCubit(api);
    await cubit.login('u@example.test', 'Passw0rd!');
    expect(cubit.state.status, AuthStatus.twoFactor);
    await cubit.completeTwoFactor('123456');
    expect(cubit.state.status, AuthStatus.signedOut);
    expect(cubit.state.challenge, isNull);
    expect(cubit.state.error, 'That verification step expired. Sign in again.');
    await cubit.close();
  });
}
