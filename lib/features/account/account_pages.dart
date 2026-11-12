import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/models.dart';
import '../../core/env_config.dart';
import '../../shared/widgets.dart';
import '../../shared/forms.dart';
import '../auth/auth_cubit.dart';
import '../feed/feed_pages.dart';
import '../feed/post_engagement_cubit.dart' show isDefinitiveFailure;

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
              border: Border.all(
                color: TwonPalette.moonBlue.withValues(alpha: .18),
              ),
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
                  style: TwonButtonStyles.secondary(),
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
                FollowButton(
                  userId: user.id,
                  following: follows,
                  onChanged: refresh,
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
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: user.text('coverImage').isEmpty
                    ? const WolfLandscape()
                    : BrandImage(
                        user.text('coverImage'),
                        height: 165,
                        width: double.infinity,
                      ),
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
                  border: Border.all(
                    color: TwonPalette.moonBlue.withValues(alpha: .35),
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x33071A33),
                      blurRadius: 16,
                      offset: Offset(0, 6),
                    ),
                  ],
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
  const SearchPage({super.key, this.initialQuery = ''});
  final String initialQuery;
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  late String q;
  late final TextEditingController searchController;
  Timer? debounce;
  @override
  void initState() {
    super.initState();
    q = widget.initialQuery.trim();
    searchController = TextEditingController(text: q);
  }

  @override
  void didUpdateWidget(covariant SearchPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialQuery != widget.initialQuery) {
      debounce?.cancel();
      q = widget.initialQuery.trim();
      searchController.text = q;
    }
  }

  @override
  void dispose() {
    debounce?.cancel();
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          controller: searchController,
          autofocus: widget.initialQuery.isEmpty,
          decoration: const InputDecoration(
            labelText: 'Name, @handle or #hashtag',
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
            ? const Center(child: Text('Search by name, handle or #hashtag.'))
            : CollectionView(
                key: ValueKey(q),
                path: q.startsWith('#') ? 'posts' : 'users/search',
                query: q.startsWith('#') ? {'hashtag': q} : {'q': q},
                empty: q.startsWith('#') ? 'No visible posts with this hashtag.' : 'No members found.',
                builder: (d, user, r) => q.startsWith('#') ? PostCard(post: user, refresh: r) : Card(
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
    empty: 'All quiet. No signals yet.',
    emptyAsset: 'no-clan-found',
    builder: (d, n, r) => UnreadSurface(
      unread: !n.flag('isRead'),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(14, 6, 12, 6),
        leading: MemberAvatar(n.object('actorId')),
        title: Text(
          n.text('content'),
          style: TextStyle(
            fontWeight: n.flag('isRead') ? FontWeight.w400 : FontWeight.w700,
          ),
        ),
        subtitle: Text(
          dateLabel(n.text('createdAt')),
          style: TextStyle(
            color: n.flag('isRead')
                ? Theme.of(d).colorScheme.onSurfaceVariant
                : Theme.of(d).colorScheme.primary,
            fontWeight: n.flag('isRead') ? FontWeight.w400 : FontWeight.w700,
          ),
        ),
        trailing: n.flag('isRead')
            ? null
            : ExcludeSemantics(
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: Theme.of(d).colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
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
                // Private uploads (F-05 B3): submit the stable `ref`, preview `url`.
                FieldSpec(
                  'documentImage',
                  'Identity document',
                  kind: FieldKind.image,
                  uploadEndpoint: 'verification/uploads',
                  uploadReferenceKey: 'ref',
                ),
                FieldSpec(
                  'selfieImage',
                  'Selfie',
                  kind: FieldKind.image,
                  uploadEndpoint: 'verification/uploads',
                  uploadReferenceKey: 'ref',
                ),
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
          style: TwonButtonStyles.filledIcon(),
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
      // F-33: uploaded to private storage; only its reference is submitted, and
      // the photo becomes public only after a moderator approves it.
      FieldSpec(
        'imageRef',
        'Photo',
        kind: FieldKind.image,
        uploadEndpoint: 'lookbook/uploads',
        uploadReferenceKey: 'imageRef',
      ),
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


/// Task 11: optimistic follow/unfollow. The label flips at once (with a
/// progress indicator while the request runs); the server's "already
/// following" / "not following" answers count as done. A refused request rolls
/// back with a message; an uncertain one re-reads the profile.
class FollowButton extends StatefulWidget {
  const FollowButton({
    super.key,
    required this.userId,
    required this.following,
    required this.onChanged,
  });
  final String userId;
  final bool following;
  final VoidCallback onChanged;
  @override
  State<FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends State<FollowButton> {
  late bool _following = widget.following;
  bool _busy = false;

  @override
  void didUpdateWidget(FollowButton old) {
    super.didUpdateWidget(old);
    if (!_busy && old.following != widget.following) _following = widget.following;
  }

  Future<void> _toggle() async {
    if (_busy) return;
    final want = !_following;
    final api = repository(context);
    setState(() {
      _following = want;
      _busy = true;
    });
    try {
      await api.request(
        'users/${widget.userId}/follow',
        method: want ? 'POST' : 'DELETE',
      );
      widget.onChanged();
    } on AppFailure catch (error) {
      final already = want
          ? error.status == 409
          : error.status == 400 &&
                error.message.toLowerCase().contains('not following');
      if (already) {
        widget.onChanged();
      } else if (isDefinitiveFailure(error)) {
        if (mounted) {
          setState(() => _following = !want);
          notice(context, error.message);
        }
      } else {
        widget.onChanged(); // the request may have been applied: re-read
        if (mounted) notice(context, error.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => FilledButton(
    // Following reads as the quieter navy state; Follow stays the crimson CTA.
    style: _following ? TwonButtonStyles.secondary() : null,
    onPressed: _busy ? null : _toggle,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_busy)
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else
          AnimatedSwitcher(
            duration: TwonMotion.of(context, TwonMotion.slow),
            switchInCurve: Curves.easeOutBack,
            transitionBuilder: (child, a) =>
                ScaleTransition(scale: a, child: child),
            child: Icon(
              _following ? Icons.check_rounded : Icons.person_add_alt_1_rounded,
              key: ValueKey(_following),
              size: 18,
            ),
          ),
        const SizedBox(width: 8),
        Text(_following ? 'Unfollow' : 'Follow'),
      ],
    ),
  );
}
