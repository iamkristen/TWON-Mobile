import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/models.dart';
import '../../core/env_config.dart';
import '../../shared/widgets.dart';
import '../../shared/forms.dart';
import '../auth/auth_cubit.dart';
import '../feed/feed_pages.dart';

Future<void> showReport(BuildContext c, String kind, String target) async {
  await showModalBottomSheet(
    context: c,
    isScrollControlled: true,
    builder: (sheet) => SizedBox(
      height: MediaQuery.sizeOf(c).height * .8,
      child: FeatureForm(
        title: 'Report $kind',
        description: 'Tell our moderation team what happened.',
        button: 'Submit report',
        fields: const [
          FieldSpec(
            'reason',
            'Reason',
            kind: FieldKind.select,
            options: [
              'spam',
              'harassment',
              'hate',
              'impersonation',
              'nudity',
              'violence',
              'scam',
              'other',
            ],
          ),
          FieldSpec(
            'details',
            'Details',
            kind: FieldKind.multiline,
            required: false,
            maxLength: 5000,
          ),
        ],
        submit: (v) => repository(c).request(
          'reports',
          method: 'POST',
          body: {
            ...v,
            'kind': kind,
            switch (kind) {
              'profile' => 'targetUserId',
              'post' => 'postId',
              'clan' => 'clanId',
              _ => 'messageId',
            }: target,
          },
        ),
        onSuccess: (_) {
          Navigator.pop(sheet);
          notice(c, 'Report submitted.');
        },
      ),
    ),
  );
}

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key, this.handle});
  final String? handle;
  @override
  Widget build(BuildContext c) => DetailView(
    path: handle == null ? 'users/me' : 'users/${Uri.encodeComponent(handle!)}',
    builder: (d, user, refresh) {
      final me = c.read<AuthCubit>();
      final own = user.id == me.userId;
      final follows = user.strings('followers').contains(me.userId);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ProfileIdentity(user: user),
          if (user.text('bio').isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(user.text('bio')),
          ],
          if (user.text('city').isNotEmpty || user.text('country').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                children: [
                  Icon(
                    Icons.place_outlined,
                    size: 16,
                    color: Theme.of(c).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      [
                        user.text('city'),
                        user.text('country'),
                      ].where((v) => v.isNotEmpty).join(', '),
                      style: TextStyle(
                        color: Theme.of(c).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
            decoration: BoxDecoration(
              color: Theme.of(c).colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                for (final stat in [
                  ('followerCount', 'Followers'),
                  ('followingCount', 'Following'),
                  ('packPoints', 'Pack points'),
                ])
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          '${user.object('stats')[stat.$1] ?? 0}',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          stat.$2,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(c).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (own)
            Wrap(
              spacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => c.push('/profile/edit', extra: user.data),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit profile'),
                ),
                TextButton.icon(
                  onPressed: () => c.push('/settings'),
                  icon: const Icon(Icons.settings_outlined),
                  label: const Text('Settings'),
                ),
              ],
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionButton(
                  label: follows ? 'Unfollow' : 'Follow',
                  action: () => repository(c).request(
                    'users/${user.id}/follow',
                    method: follows ? 'DELETE' : 'POST',
                  ),
                  onSuccess: (_) => refresh(),
                ),
                ActionButton(
                  tonal: true,
                  label: 'Message',
                  action: () => repository(c).request(
                    'conversations',
                    method: 'POST',
                    body: {
                      'type': 'dm',
                      'participantIds': [user.id],
                    },
                  ),
                  onSuccess: (v) =>
                      c.push('/messages/${entityId(v)}', extra: asJson(v)),
                ),
                ActionButton(
                  label:
                      ((me.state.user?['blockedUserIds'] as List?) ?? [])
                          .contains(user.id)
                      ? 'Unblock'
                      : 'Block',
                  tonal: true,
                  confirmation: 'Change messaging access for this member?',
                  action: () => repository(c).request(
                    ((me.state.user?['blockedUserIds'] as List?) ?? [])
                            .contains(user.id)
                        ? 'users/me/blocked-users/${user.id}'
                        : 'users/me/blocked-users',
                    method:
                        ((me.state.user?['blockedUserIds'] as List?) ?? [])
                            .contains(user.id)
                        ? 'DELETE'
                        : 'POST',
                    body: {'userId': user.id},
                  ),
                  onSuccess: (_) async {
                    await me.refreshProfile();
                    refresh();
                  },
                ),
                TextButton(
                  onPressed: () => showReport(c, 'profile', user.id),
                  child: const Text('Report'),
                ),
              ],
            ),
          if (user.strings('skills').isNotEmpty)
            Wrap(
              spacing: 8,
              children: user
                  .strings('skills')
                  .map((v) => Chip(label: Text(v)))
                  .toList(),
            ),
          if (user.rows('badges').isNotEmpty)
            ...user
                .rows('badges')
                .map(
                  (b) => ListTile(
                    leading: const Icon(Icons.workspace_premium_outlined),
                    title: Text('${b['title']}'),
                    subtitle: Text('${b['description']}'),
                  ),
                ),
          ListTile(
            leading: const Icon(Icons.dynamic_feed_outlined),
            title: Text(own ? 'My posts' : 'Member posts'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => c.push('/members/${user.id}/posts'),
          ),
        ],
      );
    },
  );
}

class ProfileIdentity extends StatelessWidget {
  const ProfileIdentity({super.key, required this.user});
  final Entity user;
  @override
  Widget build(BuildContext c) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        height: 205,
        child: Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 165,
              child: user.text('coverImage').isEmpty
                  ? const WolfLandscape()
                  : BrandImage(
                      user.text('coverImage'),
                      height: 165,
                      width: double.infinity,
                    ),
            ),
            Positioned(
              bottom: 0,
              left: 18,
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Theme.of(c).scaffoldBackgroundColor,
                ),
                child: MemberAvatar(user.data, radius: 40),
              ),
            ),
            Positioned(
              bottom: 6,
              right: 4,
              child: IconButton.filledTonal(
                tooltip: 'Share profile',
                onPressed: () => SharePlus.instance.share(
                  ShareParams(
                    text: '${AppConfig.websiteUrl}/u/${user.text('handle')}',
                  ),
                ),
                icon: const Icon(Icons.ios_share_rounded, size: 20),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        children: [
          Text(
            user.text('fullName'),
            style: Theme.of(c).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -.6,
            ),
          ),
          if (user.flag('isIdentityVerified'))
            Tooltip(
              message: 'Identity verified',
              child: Icon(
                Icons.verified_rounded,
                size: 20,
                color: Theme.of(c).colorScheme.primary,
              ),
            ),
        ],
      ),
      const SizedBox(height: 4),
      Text(
        '@${user.text('handle')}',
        style: TextStyle(color: Theme.of(c).colorScheme.onSurfaceVariant),
      ),
    ],
  );
}

class ProfilePostsPage extends StatelessWidget {
  const ProfilePostsPage(this.id, {super.key});
  final String id;
  @override
  Widget build(BuildContext c) => CollectionView(
    path: 'posts/author/$id',
    builder: (d, p, r) => PostCard(post: p, refresh: r),
  );
}

class ProfileEditor extends StatelessWidget {
  const ProfileEditor({super.key, this.initial = const {}});
  final Json initial;
  @override
  Widget build(BuildContext c) => FeatureForm(
    title: 'Your profile',

    fields: [
      FieldSpec(
        'fullName',
        'Full name',
        initial: initial['fullName'],
        maxLength: 100,
      ),
      FieldSpec(
        'handle',
        'Handle',
        initial: initial['handle'],
        maxLength: 30,
        hint: 'Handle changes have a six-month cooldown.',
      ),
      FieldSpec(
        'bio',
        'About you',
        kind: FieldKind.multiline,
        required: false,
        initial: initial['bio'],
        maxLength: 500,
      ),
      FieldSpec(
        'country',
        'Country',
        required: false,
        initial: initial['country'],
      ),
      FieldSpec('city', 'City', required: false, initial: initial['city']),
      FieldSpec(
        'status',
        'Current status',
        kind: FieldKind.select,
        options: const ['student', 'working', 'jobSeeker'],
        initial: initial['status'] ?? 'student',
      ),
      FieldSpec(
        'avatar',
        'Profile photo',
        kind: FieldKind.image,
        required: false,
        initial: initial['avatar'],
      ),
      FieldSpec(
        'coverImage',
        'Cover photo',
        kind: FieldKind.image,
        required: false,
        initial: initial['coverImage'],
      ),
    ],
    submit: (v) => repository(c).request('users/me', method: 'PATCH', body: v),
    onSuccess: (_) async {
      await c.read<AuthCubit>().refreshProfile();
      if (c.mounted) c.pop();
    },
  );
}

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  String q = '';
  Timer? debounce;
  @override
  void dispose() {
    debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Find pack members',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (v) {
            debounce?.cancel();
            debounce = Timer(const Duration(milliseconds: 350), () {
              if (mounted) setState(() => q = v.trim());
            });
          },
        ),
      ),
      Expanded(
        child: q.isEmpty
            ? const Center(child: Text('Search by name or handle.'))
            : CollectionView(
                key: ValueKey(q),
                path: 'users/search',
                query: {'q': q},
                empty: 'No members found.',
                builder: (d, user, r) => Card(
                  child: ListTile(
                    leading: MemberAvatar(user.data),
                    title: Text(user.text('fullName')),
                    subtitle: Text('@${user.text('handle')}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => c.push('/members/${user.text('handle')}'),
                  ),
                ),
              ),
      ),
    ],
  );
}

class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});
  @override
  Widget build(BuildContext c) => CollectionView(
    path: 'notifications',
    header: Row(
      children: [
        const Expanded(child: PageHeading('Your Signals', '')),
        ActionButton(
          label: 'Read all',
          tonal: true,
          action: () =>
              repository(c).request('notifications/read-all', method: 'PATCH'),
          onSuccess: (_) => notice(c, 'Notifications marked as read.'),
        ),
      ],
    ),
    builder: (d, n, r) => Card(
      child: ListTile(
        leading: Badge(
          isLabelVisible: !n.flag('isRead'),
          child: MemberAvatar(n.object('actorId')),
        ),
        title: Text(n.text('content')),
        subtitle: Text(dateLabel(n.text('createdAt'))),
        onTap: () async {
          try {
            await repository(
              c,
            ).request('notifications/${n.id}/read', method: 'PATCH');
            r();
            if (!c.mounted) return;
            if (n.text('postId').isNotEmpty) {
              c.push('/posts/${entityId(n.data['postId'])}');
            } else if (n.text('clanId').isNotEmpty) {
              c.push('/clans/${entityId(n.data['clanId'])}');
            } else if (n.object('actorId')['handle'] != null) {
              c.push('/members/${n.object('actorId')['handle']}');
            }
          } catch (error) {
            if (c.mounted) notice(c, error.toString());
          }
        },
      ),
    ),
  );
}

class SupportPage extends StatefulWidget {
  const SupportPage({super.key});
  @override
  State<SupportPage> createState() => _SupportPageState();
}

class _SupportPageState extends State<SupportPage> {
  String status = 'all';
  int revision = 0;
  @override
  Widget build(BuildContext c) => DefaultTabController(
    length: 2,
    child: Column(
      children: [
        const TabBar(
          tabs: [
            Tab(text: 'New request'),
            Tab(text: 'My requests'),
          ],
        ),
        Expanded(
          child: TabBarView(
            children: [
              FeatureForm(
                title: 'Pack support',
                description: 'Staff replies will appear in My requests.',
                button: 'Send request',
                fields: const [
                  FieldSpec(
                    'category',
                    'Category',
                    kind: FieldKind.select,
                    options: [
                      'general',
                      'technical',
                      'harassment',
                      'scam',
                      'suggestion',
                      'other',
                    ],
                  ),
                  FieldSpec('subject', 'Subject', maxLength: 500),
                  FieldSpec(
                    'description',
                    'Details',
                    kind: FieldKind.multiline,
                    maxLength: 20000,
                  ),
                  FieldSpec(
                    'contactChannel',
                    'Contact details',
                    required: false,
                    maxLength: 500,
                  ),
                  FieldSpec(
                    'attachments',
                    'Attachments',
                    kind: FieldKind.files,
                    required: false,
                  ),
                ],
                submit: (v) => repository(
                  c,
                ).request('support/tickets', method: 'POST', body: v),
                onSuccess: (_) {
                  setState(() => revision++);
                  notice(
                    c,
                    'Request sent. Follow its progress in My requests.',
                  );
                },
              ),
              Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: DropdownButtonFormField(
                      initialValue: status,
                      decoration: const InputDecoration(labelText: 'Status'),
                      items:
                          ['all', 'open', 'in_progress', 'resolved', 'closed']
                              .map(
                                (v) => DropdownMenuItem(
                                  value: v,
                                  child: Text(v.replaceAll('_', ' ')),
                                ),
                              )
                              .toList(),
                      onChanged: (v) => setState(() => status = v!),
                    ),
                  ),
                  Expanded(
                    child: CollectionView(
                      key: ValueKey('$status:$revision'),
                      path: 'support/tickets',
                      query: {if (status != 'all') 'status': status},
                      empty: 'Your requests will appear here.',
                      builder: (d, t, r) => Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t.text('subject'),
                                style: Theme.of(c).textTheme.titleMedium,
                              ),
                              Text(
                                '${t.text('status').replaceAll('_', ' ')} · ${dateLabel(t.text('createdAt'))}',
                              ),
                              const SizedBox(height: 12),
                              Text(t.text('description')),
                              ...t
                                  .strings('attachments')
                                  .asMap()
                                  .entries
                                  .map(
                                    (e) => TextButton.icon(
                                      onPressed: () => openUrl(e.value),
                                      icon: const Icon(Icons.attach_file),
                                      label: Text('Attachment ${e.key + 1}'),
                                    ),
                                  ),
                              if (t.text('response').isNotEmpty)
                                Container(
                                  margin: const EdgeInsets.only(top: 12),
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Theme.of(
                                      c,
                                    ).colorScheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    'Support reply\n${t.text('response')}',
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class VerificationPage extends StatelessWidget {
  const VerificationPage({super.key});
  @override
  Widget build(BuildContext c) => DetailView(
    path: 'verification/status',
    builder: (d, status, r) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeading(
          'Identity verification',
          'Status: ${status.text('status', 'none')}',
        ),
        if (status.object('request')['rejectionReason'] != null)
          Text('${status.object('request')['rejectionReason']}'),
        if (!['approved', 'pending'].contains(status.text('status')))
          SizedBox(
            height: 700,
            child: FeatureForm(
              title: 'Submit verification',
              description:
                  'Only upload your own document and a clear selfie. Authorized reviewers handle your request.',
              fields: const [
                FieldSpec(
                  'documentType',
                  'Document type',
                  kind: FieldKind.select,
                  options: [
                    'passport',
                    'drivingLicense',
                    'nationalId',
                    'other',
                  ],
                ),
                FieldSpec(
                  'documentImage',
                  'Identity document',
                  kind: FieldKind.image,
                ),
                FieldSpec('selfieImage', 'Selfie', kind: FieldKind.image),
              ],
              submit: (v) => repository(
                c,
              ).request('verification/submit', method: 'POST', body: v),
              onSuccess: (_) {
                r();
                notice(c, 'Verification submitted.');
              },
            ),
          ),
      ],
    ),
  );
}

class LookbookPage extends StatelessWidget {
  const LookbookPage({super.key});
  @override
  Widget build(BuildContext c) => CollectionView(
    path: 'lookbook',
    header: Row(
      children: [
        const Expanded(child: PageHeading('Pack lookbook', '')),
        IconButton.filled(
          tooltip: 'Submit lookbook photo',
          onPressed: () => c.push('/lookbook/new'),
          icon: const Icon(Icons.add),
        ),
      ],
    ),
    builder: (d, row, r) => Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BrandImage(
              row.text('imageUrl'),
              width: double.infinity,
              height: 280,
            ),
            const SizedBox(height: 12),
            Text(row.text('title'), style: Theme.of(c).textTheme.titleMedium),
            Text(row.text('caption')),
          ],
        ),
      ),
    ),
  );
}

class LookbookEditor extends StatelessWidget {
  const LookbookEditor({super.key});
  @override
  Widget build(BuildContext c) => FeatureForm(
    title: 'Share your pack style',
    description: 'Photos appear in the lookbook after moderation.',
    fields: const [
      FieldSpec('imageUrl', 'Photo', kind: FieldKind.image),
      FieldSpec('title', 'Title'),
      FieldSpec('caption', 'Caption', kind: FieldKind.multiline),
    ],
    submit: (v) => repository(c).request('lookbook', method: 'POST', body: v),
    onSuccess: (_) {
      notice(c, 'Photo submitted for review.');
      c.pop();
    },
  );
}
