import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../core/models.dart';
import '../../shared/forms.dart';
import '../../shared/widgets.dart';
import 'auth_cubit.dart';

class AuthPage extends StatelessWidget {
  const AuthPage({
    super.key,
    this.mode = 'login',
    this.email = '',
    this.token = '',
  });
  final String mode, email, token;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: BlocBuilder<AuthCubit, AuthState>(
            builder: (c, state) {
              final auth = c.read<AuthCubit>();
              final api = repository(c);
              if (state.status == AuthStatus.starting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (state.status == AuthStatus.twoFactor) {
                return _AuthCard(
                  children: [
                    if (state.error != null) ErrorPanel(state.error!),
                    FeatureForm(
                      embedded: true,
                      title: 'One more step',
                      description:
                          'Enter your authenticator code or a recovery code.',
                      fields: const [
                        FieldSpec(
                          'code',
                          'Authenticator or recovery code',
                          maxLength: 9,
                        ),
                      ],
                      button: 'Verify and sign in',
                      submit: (v) => auth.completeTwoFactor(v['code']),
                      onSuccess: (_) {},
                    ),
                    TextButton(
                      onPressed: auth.cancelChallenge,
                      child: const Text('Back to sign in'),
                    ),
                  ],
                );
              }
              final fields = <FieldSpec>[];
              String title = '', button = 'Continue', description = '';
              switch (mode) {
                case 'signup':
                  title = 'Find your pack.';
                  description = 'Create your TWON account.';
                  button = 'Create account';
                  fields.addAll(const [
                    FieldSpec('fullName', 'Full name', maxLength: 100),
                    FieldSpec(
                      'handle',
                      'Handle',
                      maxLength: 30,
                      hint: 'Letters, numbers and underscores',
                    ),
                    FieldSpec('email', 'Email', kind: FieldKind.email),
                    FieldSpec(
                      'password',
                      'Password',
                      kind: FieldKind.password,
                      maxLength: 128,
                      hint: 'At least 8 characters',
                    ),
                  ]);
                case 'verify':
                  title = 'Verify your email';
                  description = 'Enter the six-digit code sent to your email.';
                  button = 'Verify email';
                  fields.addAll([
                    FieldSpec(
                      'email',
                      'Email',
                      kind: FieldKind.email,
                      initial: email,
                    ),
                    const FieldSpec('otp', 'Verification code', maxLength: 6),
                  ]);
                case 'forgot':
                  title = 'Reset your password';
                  description =
                      'We will email a reset link if this account exists.';
                  fields.add(
                    const FieldSpec('email', 'Email', kind: FieldKind.email),
                  );
                case 'reset':
                  title = 'Choose a new password';
                  description = 'Use the reset token from your email link.';
                  fields.addAll([
                    FieldSpec('token', 'Reset token', initial: token),
                    const FieldSpec(
                      'password',
                      'New password',
                      kind: FieldKind.password,
                      maxLength: 128,
                      hint: 'At least 8 characters',
                    ),
                  ]);
                case 'cancel-deletion':
                  title = 'Cancel deletion request';
                  description =
                      'Verify your credentials to cancel the pending request.';
                  fields.addAll(const [
                    FieldSpec('email', 'Email', kind: FieldKind.email),
                    FieldSpec('password', 'Password', kind: FieldKind.password),
                  ]);
                default:
                  title = 'Welcome back to the pack.';
                  description = 'Your people. Your place. Your pack.';
                  button = 'Sign in';
                  fields.addAll(const [
                    FieldSpec('email', 'Email', kind: FieldKind.email),
                    FieldSpec('password', 'Password', kind: FieldKind.password),
                  ]);
              }
              return _AuthCard(
                children: [
                  if (mode == 'login' && state.error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        state.error!,
                        style: TextStyle(color: Theme.of(c).colorScheme.error),
                      ),
                    ),
                  FeatureForm(
                    embedded: true,
                    key: ValueKey(mode),
                    title: title,
                    description: description,
                    fields: fields,
                    button: button,
                    submit: (v) async {
                      if (mode == 'login') {
                        await auth.login(v['email'], v['password']);
                        return null;
                      }
                      final path = switch (mode) {
                        'signup' => 'signup',
                        'verify' => 'verify-email',
                        'forgot' => 'forgot-password',
                        'reset' => 'reset-password',
                        'cancel-deletion' => 'cancel-deletion',
                        _ => 'login',
                      };
                      final result = await api.request(
                        'auth/$path',
                        method: 'POST',
                        body: v,
                        authenticated: false,
                      );
                      if (c.mounted) {
                        if (mode == 'signup') {
                          c.go(
                            '/auth/verify?email=${Uri.encodeComponent(v['email'])}',
                          );
                        } else {
                          notice(
                            c,
                            mode == 'forgot'
                                ? 'If an account exists for this email, a password reset link has been sent.'
                                : asJson(result)['message']?.toString() ??
                                      'Done.',
                          );
                          c.go('/auth/login');
                        }
                      }
                      return result;
                    },
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    alignment: WrapAlignment.center,
                    children: [
                      if (mode == 'login') ...[
                        TextButton(
                          onPressed: () => c.go('/auth/forgot'),
                          child: const Text('Forgot password?'),
                        ),
                        TextButton(
                          onPressed: () => c.go('/auth/signup'),
                          child: const Text('Join the pack'),
                        ),
                      ] else
                        TextButton(
                          onPressed: () => c.go('/auth/login'),
                          child: const Text('Back to sign in'),
                        ),
                      if (mode == 'verify')
                        ActionButton(
                          label: 'Resend code',
                          tonal: true,
                          action: () => api.request(
                            'auth/resend-otp',
                            method: 'POST',
                            body: {'email': email},
                            authenticated: false,
                          ),
                          onSuccess: (_) =>
                              notice(c, 'Verification code requested.'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
}

class _AuthCard extends StatelessWidget {
  const _AuthCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: (constraints.maxHeight - 48).clamp(0, double.infinity),
        ),
        child: Center(
          child: Card(
            margin: EdgeInsets.zero,
            elevation: 8,
            shadowColor: Colors.black.withValues(alpha: .12),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Image.asset(
                    'assets/branding/logo.png',
                    height: 64,
                    semanticLabel: 'TWON',
                  ),
                  const SizedBox(height: 24),
                  ...children,
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
