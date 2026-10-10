import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import '../../shared/forms.dart';
import '../auth/auth_cubit.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});
  @override
  Widget build(BuildContext c) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      const PageHeading('Settings', ''),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: BlocBuilder<ThemeCubit, ThemeMode>(
            builder: (d, mode) => DropdownButtonFormField<ThemeMode>(
              initialValue: mode,
              decoration: const InputDecoration(labelText: 'Appearance'),
              items: ThemeMode.values
                  .map((v) => DropdownMenuItem(value: v, child: Text(v.name)))
                  .toList(),
              onChanged: (v) => d.read<ThemeCubit>().change(v!),
            ),
          ),
        ),
      ),
      Card(
        child: Column(
          children:
              [
                    (
                      Icons.notifications_outlined,
                      'Notifications & privacy',
                      '/settings/preferences',
                    ),
                    (Icons.lock_outline, 'Password', '/settings/password'),
                    (
                      Icons.verified_user_outlined,
                      'Two-step verification',
                      '/settings/2fa',
                    ),
                    (
                      Icons.devices_outlined,
                      'Signed-in devices',
                      '/settings/sessions',
                    ),
                    (Icons.support_agent, 'Support', '/support'),
                    (
                      Icons.person_remove_outlined,
                      'Account deletion',
                      '/settings/deletion',
                    ),
                  ]
                  .map(
                    (row) => ListTile(
                      leading: Icon(row.$1),
                      title: Text(row.$2),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => c.push(row.$3),
                    ),
                  )
                  .toList(),
        ),
      ),
      ActionButton(
        label: 'Sign out',
        tonal: true,
        confirmation: 'Sign out of TWON on this device?',
        action: () => c.read<AuthCubit>().logout(),
      ),
    ],
  );
}

class PreferencesPage extends StatelessWidget {
  const PreferencesPage({super.key});
  @override
  Widget build(BuildContext c) => ResourcePanel(
    path: 'users/me',
    builder: (d, user, r) {
      final prefs = user.object('preferences');
      final n = asJson(prefs['notifications']), p = asJson(prefs['privacy']);
      return FeatureForm(
        title: 'Notifications & privacy',

        fields: [
          FieldSpec(
            'inApp',
            'In-app notifications',
            kind: FieldKind.toggle,
            initial: n['inApp'] ?? true,
          ),
          FieldSpec(
            'mentions',
            'Mentions',
            kind: FieldKind.toggle,
            initial: n['mentions'] ?? true,
          ),
          FieldSpec(
            'messages',
            'Messages',
            kind: FieldKind.toggle,
            initial: n['messages'] ?? true,
          ),
          FieldSpec(
            'showLocation',
            'Show location on my profile',
            kind: FieldKind.toggle,
            initial: p['showLocation'] ?? true,
          ),
        ],
        submit: (v) => repository(c).request(
          'users/me',
          method: 'PATCH',
          body: {
            'preferences': {
              'notifications': {
                'inApp': v['inApp'],
                'mentions': v['mentions'],
                'messages': v['messages'],
              },
              'privacy': {'showLocation': v['showLocation']},
            },
          },
        ),
        onSuccess: (_) {
          c.read<AuthCubit>().refreshProfile();
          notice(c, 'Preferences saved.');
        },
      );
    },
  );
}

class PasswordPage extends StatelessWidget {
  const PasswordPage({super.key});
  @override
  Widget build(BuildContext c) => FeatureForm(
    title: 'Change password',
    description: 'Your other sessions will be signed out.',
    fields: const [
      FieldSpec(
        'currentPassword',
        'Current password',
        kind: FieldKind.password,
      ),
      FieldSpec('newPassword', 'New password', kind: FieldKind.password),
      FieldSpec(
        'confirmation',
        'Confirm new password',
        kind: FieldKind.password,
      ),
    ],
    submit: (v) async {
      if (v['newPassword'] != v['confirmation']) {
        throw const AppFailure('New passwords do not match.');
      }
      if ((v['newPassword'] as String).length < 8) {
        throw const AppFailure('Use at least 8 characters.');
      }
      return repository(c).request(
        'auth/change-password',
        method: 'POST',
        body: {
          'currentPassword': v['currentPassword'],
          'newPassword': v['newPassword'],
        },
      );
    },
    onSuccess: (v) async {
      await c.read<AuthCubit>().accept(asJson(v));
      if (c.mounted) {
        notice(c, 'Password updated.');
        c.pop();
      }
    },
  );
}

class SessionsPage extends StatelessWidget {
  const SessionsPage({super.key});
  @override
  Widget build(BuildContext c) => CollectionView(
    path: 'auth/sessions',
    header: const PageHeading(
      'Signed-in devices',
      'Remove access for any device you do not recognize.',
    ),
    builder: (d, s, r) => Card(
      child: ListTile(
        leading: const Icon(Icons.devices),
        title: Text(s.text('deviceLabel', 'Device')),
        subtitle: Text(
          '${s.text('ip')}\nLast active ${dateLabel(s.text('lastSeenAt'))}',
        ),
        trailing: ActionButton(
          label: 'Sign out',
          tonal: true,
          confirmation:
              'Sign this session out? This can include your current device.',
          action: () => repository(
            c,
          ).request('auth/sessions/${s.text('jti')}', method: 'DELETE'),
          onSuccess: (_) => r(),
        ),
      ),
    ),
  );
}

class TwoFactorPage extends StatefulWidget {
  const TwoFactorPage({super.key});
  @override
  State<TwoFactorPage> createState() => _TwoFactorPageState();
}

class _TwoFactorPageState extends State<TwoFactorPage> {
  Json? setup;
  List<String> recovery = [];
  int revision = 0;
  @override
  Widget build(BuildContext c) => ResourcePanel(
    key: ValueKey(revision),
    path: 'auth/2fa/status',
    builder: (d, status, r) => ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const PageHeading(
          'Two-step verification',
          'Protect your account with an authenticator app.',
        ),
        if (recovery.isNotEmpty) ...[
          const Text(
            'Save these recovery codes somewhere safe. Each can be used once.',
          ),
          SelectableText(recovery.join('\n')),
          TextButton(
            onPressed: () => setState(() => recovery = []),
            child: const Text('I saved my codes'),
          ),
        ] else if (status.flag('enabled'))
          SizedBox(
            height: 420,
            child: FeatureForm(
              title: 'Disable verification',
              description: 'You will need to sign in again afterwards.',
              fields: const [
                FieldSpec('password', 'Password', kind: FieldKind.password),
                FieldSpec('token', 'Authenticator or recovery code'),
              ],
              submit: (v) => repository(
                c,
              ).request('auth/2fa/disable', method: 'POST', body: v),
              onSuccess: (_) async {
                await c.read<AuthCubit>().logout();
              },
            ),
          )
        else if (setup == null)
          ActionButton(
            label: 'Set up authenticator',
            action: () =>
                repository(c).request('auth/2fa/setup', method: 'POST'),
            onSuccess: (v) => setState(() => setup = asJson(v)),
          )
        else ...[
          Center(
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.all(16),
              child: QrImageView(
                data: setup!['otpauthUrl'] as String,
                size: 200,
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Scan this QR code, or enter this secret manually:'),
          SelectableText('${setup!['secret']}'),
          SizedBox(
            height: 320,
            child: FeatureForm(
              title: 'Confirm setup',
              fields: const [
                FieldSpec('token', 'Six-digit code', maxLength: 6),
              ],
              submit: (v) => repository(
                c,
              ).request('auth/2fa/enable', method: 'POST', body: v),
              onSuccess: (v) => setState(() {
                recovery = List<String>.from(asJson(v)['recoveryCodes'] ?? []);
                setup = null;
                revision++;
              }),
            ),
          ),
        ],
      ],
    ),
  );
}

class DeletionPage extends StatelessWidget {
  const DeletionPage({super.key});
  @override
  Widget build(BuildContext c) => DetailView(
    path: 'users/me',
    builder: (d, user, r) {
      final deletion = user.object('deletion');
      final pending =
          deletion['requestedAt'] != null ||
          user.data['accountDeletionRequestedAt'] != null;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PageHeading(
            'Account deletion',
            'A deletion request is reviewed by support after the grace period.',
          ),
          const Text(
            'Request deletion only if you want to close your TWON account. You can cancel until the request is processed.',
          ),
          const SizedBox(height: 24),
          ActionButton(
            label: pending
                ? 'Cancel deletion request'
                : 'Request account deletion',
            confirmation: pending
                ? 'Keep your account and cancel deletion?'
                : 'Request account deletion? You will be signed out.',
            action: () => repository(c).request(
              'users/me/delete-request',
              method: pending ? 'DELETE' : 'POST',
            ),
            onSuccess: (_) async {
              if (pending) {
                r();
                await c.read<AuthCubit>().refreshProfile();
              } else {
                await c.read<AuthCubit>().logout();
              }
            },
          ),
        ],
      );
    },
  );
}
