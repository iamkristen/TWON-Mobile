import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/models.dart';
import '../../shared/widgets.dart';
import '../../shared/forms.dart';
import '../feed/feed_pages.dart';
import '../account/account_pages.dart';

const clanTitles = [
  'Alpha',
  'Beta Alpha',
  'Den Master',
  'Pack Captain',
  'Howler',
  'Pathrunner',
  'Bloodrunner',
  'Denmate',
  'Pup',
];

class ClansPage extends StatefulWidget {
  const ClansPage({super.key});
  @override
  State<ClansPage> createState() => _ClansPageState();
}

class _ClansPageState extends State<ClansPage> {
  String q = '';
  @override
  Widget build(BuildContext c) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Search clans',
                  prefixIcon: Icon(Icons.search),
                ),
                onSubmitted: (v) => setState(() => q = v.trim()),
              ),
            ),
            const SizedBox(width: 10),
            IconButton.filled(
              tooltip: 'Create clan',
              onPressed: () => c.push('/clans/new'),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ),
      Expanded(
        child: CollectionView(
          key: ValueKey(q),
          path: 'clans',
          emptyAsset: 'no-clan-found',
          query: {if (q.isNotEmpty) 'q': q},
          empty: q.isEmpty
              ? 'No pack has claimed this territory yet.'
              : 'No clans found.',
          builder: (d, clan, r) => Card(
            child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              leading: MemberAvatar({
                'avatar': clan.text('logo'),
                'fullName': clan.text('name'),
              }),
              title: Text(
                clan.text('name'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                '${clan.text('country')} · ${clan.number('memberCount')} members',
              ),

              trailing: const Icon(Icons.chevron_right),
              onTap: () => d.push('/clans/${clan.id}'),
            ),
          ),
        ),
      ),
    ],
  );
}

class ClanPage extends StatelessWidget {
  const ClanPage(this.id, {super.key});
  final String id;
  @override
  Widget build(BuildContext c) => DetailView(
    path: 'clans/$id',
    builder: (d, clan, refresh) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BrandImage(clan.text('logo'), height: 160),
        const SizedBox(height: 16),
        PageHeading(
          clan.text('name'),
          '${clan.number('memberCount')} members · ${clan.text('country')}',
        ),
        Text(clan.text('description')),
        if (clan.text('clanRules').isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Clan rules\n${clan.text('clanRules')}'),
            ),
          ),
        if (clan.object('broadcastMessage').isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '📣 ${clan.object('broadcastMessage')['body'] ?? ''}',
              ),
            ),
          ),
        ResourcePanel(
          path: 'clans/$id/membership',
          builder: (m, membership, refreshMembership) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!membership.flag('isMember')) ...[
                if (membership.text('inviteStatus') == 'pending')
                  Wrap(
                    spacing: 8,
                    children: [
                      ActionButton(
                        label: 'Accept invitation',
                        action: () => repository(
                          c,
                        ).request('clans/$id/invites/accept', method: 'POST'),
                        onSuccess: (_) {
                          refresh();
                          refreshMembership();
                        },
                      ),
                      ActionButton(
                        label: 'Decline invitation',
                        tonal: true,
                        action: () => repository(
                          c,
                        ).request('clans/$id/invites/decline', method: 'POST'),
                        onSuccess: (_) => refreshMembership(),
                      ),
                    ],
                  )
                else
                  ActionButton(
                    label:
                        clan.object('joinRequirements')['requireApproval'] ==
                            true
                        ? 'Request to join'
                        : 'Join clan',
                    enabled:
                        membership.text('requestStatus') != 'pending' &&
                        clan.flag('isRecruiting'),
                    action: () => repository(c).request(
                      'clans/$id/${clan.object('joinRequirements')['requireApproval'] == true ? 'requests' : 'join'}',
                      method: 'POST',
                    ),
                    onSuccess: (_) {
                      refresh();
                      refreshMembership();
                    },
                  ),
                if (membership.text('requestStatus') == 'pending')
                  const Text('Your join request is awaiting approval.'),
              ],
              if (membership.flag('isMember')) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Your title · ${membership.text('title', 'Pup')}',
                          style: Theme.of(c).textTheme.titleMedium,
                        ),
                        Text(
                          '${membership.number('titleScore')} promotion points',
                        ),
                        if (membership.text('nextTitle').isNotEmpty &&
                            membership.data['nextTitle'] != null)
                          Text(
                            '${membership.number('pointsToNext')} points to ${membership.text('nextTitle')}',
                          ),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value:
                              (membership.data['titleProgress'] as num? ?? 0)
                                  .toDouble()
                                  .clamp(0, 100) /
                              100,
                        ),
                        if (membership.flag('canRequestPromotion'))
                          ActionButton(
                            label: 'Request promotion',
                            action: () => repository(c).request(
                              'clans/$id/title-requests',
                              method: 'POST',
                            ),
                            onSuccess: (_) => refreshMembership(),
                          ),
                      ],
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.dynamic_feed_outlined),
                  title: const Text('Clan posts'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => c.push('/clans/$id/feed'),
                ),
                if (clan.text('chatConversationId').isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.forum_outlined),
                    title: const Text('Clan chat'),
                    onTap: () =>
                        c.push('/messages/${clan.text('chatConversationId')}'),
                  ),
                ListTile(
                  leading: const Icon(Icons.group_outlined),
                  title: const Text('Members'),
                  onTap: () =>
                      c.push('/clans/$id/members', extra: membership.data),
                ),
                if (membership.flag('canEditClan'))
                  ListTile(
                    leading: const Icon(Icons.tune),
                    title: const Text('Clan settings'),
                    onTap: () => c.push('/clans/$id/edit', extra: clan.data),
                  ),
                if (membership.flag('canInvite'))
                  ListTile(
                    leading: const Icon(Icons.person_add_outlined),
                    title: const Text('Invite a member'),
                    onTap: () => c.push('/clans/$id/invite'),
                  ),
                if (membership.flag('canApproveJoinRequests'))
                  ListTile(
                    leading: const Icon(Icons.how_to_reg_outlined),
                    title: const Text('Join requests'),
                    onTap: () => c.push('/clans/$id/requests'),
                  ),
                if (membership.flag('canManageMembers'))
                  ListTile(
                    leading: const Icon(Icons.workspace_premium_outlined),
                    title: const Text('Promotion requests'),
                    onTap: () => c.push('/clans/$id/promotions'),
                  ),
                if (membership.flag('canBroadcast'))
                  ListTile(
                    leading: const Icon(Icons.campaign_outlined),
                    title: const Text('Broadcast to clan'),
                    onTap: () => c.push('/clans/$id/broadcast'),
                  ),
                if (membership.flag('canHostEvents'))
                  ListTile(
                    leading: const Icon(Icons.event_outlined),
                    title: const Text('Publish a gathering'),
                    onTap: () => c.push('/events/new'),
                  ),
                if (!membership.flag('isLeader'))
                  ActionButton(
                    label: 'Leave clan',
                    tonal: true,
                    confirmation:
                        'Leave this clan? Your clan membership will end.',
                    action: () => repository(
                      c,
                    ).request('clans/$id/leave', method: 'DELETE'),
                    onSuccess: (_) {
                      refresh();
                      refreshMembership();
                    },
                  ),
              ],
              TextButton(
                onPressed: () => showReport(c, 'clan', id),
                child: const Text('Report clan'),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class ClanEditor extends StatelessWidget {
  const ClanEditor({super.key, this.id, this.initial});
  final String? id;
  final Json? initial;
  @override
  Widget build(BuildContext c) {
    final requirements = asJson(initial?['joinRequirements']);
    return FeatureForm(
      title: id == null ? 'Build your pack' : 'Clan settings',
      fields: [
        FieldSpec('name', 'Clan name', initial: initial?['name']),
        FieldSpec(
          'handle',
          'Handle',
          initial: initial?['handle'],
          maxLength: 30,
        ),
        FieldSpec(
          'description',
          'About this clan',
          initial: initial?['description'],
          kind: FieldKind.multiline,
        ),
        FieldSpec(
          'clanRules',
          'Clan rules',
          initial: initial?['clanRules'],
          kind: FieldKind.multiline,
          required: false,
        ),
        FieldSpec('country', 'Country', initial: initial?['country']),
        FieldSpec('cityId', 'City', initial: initial?['cityId']),
        FieldSpec(
          'logo',
          'Clan logo',
          kind: FieldKind.image,
          required: false,
          initial: initial?['logo'],
        ),
        FieldSpec(
          'isRecruiting',
          'Open to new members',
          kind: FieldKind.toggle,
          initial: initial?['isRecruiting'] ?? true,
        ),
        FieldSpec(
          'requireApproval',
          'Approve join requests',
          kind: FieldKind.toggle,
          initial: requirements['requireApproval'] ?? true,
        ),
        FieldSpec(
          'sameCity',
          'Members must be in the same city',
          kind: FieldKind.toggle,
          initial: requirements['sameCity'],
        ),
        FieldSpec(
          'sameCountry',
          'Members must be in the same country',
          kind: FieldKind.toggle,
          initial: requirements['sameCountry'],
        ),
        FieldSpec(
          'requireVerified',
          'Members must have verified email',
          kind: FieldKind.toggle,
          initial: requirements['requireVerified'],
        ),
        FieldSpec(
          'minPackPoints',
          'Minimum pack points',
          kind: FieldKind.integer,
          initial: '${requirements['minPackPoints'] ?? 0}',
        ),
        FieldSpec(
          'minAccountDays',
          'Minimum account age (days)',
          kind: FieldKind.integer,
          initial: '${requirements['minAccountDays'] ?? 0}',
        ),
      ],
      submit: (v) {
        final keys = [
          'requireApproval',
          'sameCity',
          'sameCountry',
          'requireVerified',
          'minPackPoints',
          'minAccountDays',
        ];
        final requirements = {for (final key in keys) key: v.remove(key)};
        return repository(c).request(
          id == null ? 'clans' : 'clans/$id',
          method: id == null ? 'POST' : 'PATCH',
          body: {...v, 'joinRequirements': requirements},
        );
      },
      onSuccess: (_) => c.pop(),
    );
  }
}

class ClanMembersPage extends StatelessWidget {
  const ClanMembersPage(this.id, {super.key, this.membership = const {}});
  final String id;
  final Json membership;
  @override
  Widget build(BuildContext c) => CollectionView(
    path: 'clans/$id/members',
    builder: (d, row, refresh) {
      final user = row.object('userId');
      final uid = entityId(user);
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              ListTile(
                leading: MemberAvatar(user),
                title: Text('${user['fullName'] ?? ''}'),
                subtitle: Text(
                  '${row.text('title')} · ${row.text('role')}\n${row.number('titleScore')} points',
                ),
                onTap: () => c.push('/members/${user['handle']}'),
              ),
              if (membership['canManageMembers'] == true)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton(
                      onPressed: () => showModalBottomSheet(
                        context: c,
                        isScrollControlled: true,
                        builder: (sheet) => SizedBox(
                          height: 480,
                          child: FeatureForm(
                            title: 'Manage ${user['fullName']}',
                            fields: [
                              FieldSpec(
                                'role',
                                'Role',
                                kind: FieldKind.select,
                                options: const ['admin', 'officer', 'member'],
                                initial: row.text('role') == 'leader'
                                    ? 'admin'
                                    : row.text('role'),
                              ),
                              FieldSpec(
                                'title',
                                'Title',
                                kind: FieldKind.select,
                                options: clanTitles,
                                initial: row.text('title', 'Pup'),
                              ),
                            ],
                            submit: (v) async {
                              await repository(c).request(
                                'clans/$id/members/$uid/role',
                                method: 'PATCH',
                                body: {'role': v['role']},
                              );
                              if (!c.mounted) return null;
                              return repository(c).request(
                                'clans/$id/members/$uid/title',
                                method: 'PATCH',
                                body: {'title': v['title']},
                              );
                            },
                            onSuccess: (_) {
                              Navigator.pop(sheet);
                              refresh();
                            },
                          ),
                        ),
                      ),
                      child: const Text('Manage'),
                    ),
                    ActionButton(
                      label: 'Remove',
                      tonal: true,
                      confirmation: 'Remove ${user['fullName']} from the clan?',
                      action: () => repository(
                        c,
                      ).request('clans/$id/members/$uid', method: 'DELETE'),
                      onSuccess: (_) => refresh(),
                    ),
                    if (membership['isLeader'] == true)
                      ActionButton(
                        label: 'Transfer leadership',
                        tonal: true,
                        confirmation:
                            'Make ${user['fullName']} the clan leader? You will give up leadership.',
                        action: () => repository(c).request(
                          'clans/$id/transfer-leader',
                          method: 'POST',
                          body: {'memberId': uid},
                        ),
                        onSuccess: (_) => refresh(),
                      ),
                  ],
                ),
            ],
          ),
        ),
      );
    },
  );
}

class ClanRequestsPage extends StatelessWidget {
  const ClanRequestsPage(this.id, {super.key, this.promotions = false});
  final String id;
  final bool promotions;
  @override
  Widget build(BuildContext c) {
    final resource = promotions ? 'title-requests' : 'requests';
    return CollectionView(
      path: 'clans/$id/$resource',
      empty: 'No pending requests.',
      builder: (d, row, r) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                row.object('userId')['fullName']?.toString() ?? 'Pack member',
                style: Theme.of(c).textTheme.titleMedium,
              ),
              Text(
                promotions
                    ? 'Requested title: ${row.text('requestedTitle')}'
                    : dateLabel(row.text('createdAt')),
              ),
              Text(row.text('status')),
              if (row.text('status') == 'pending')
                Wrap(
                  spacing: 8,
                  children: [
                    ActionButton(
                      label: 'Approve',
                      action: () => repository(c).request(
                        'clans/$id/$resource/${row.id}/approve',
                        method: 'POST',
                      ),
                      onSuccess: (_) => r(),
                    ),
                    ActionButton(
                      label: 'Decline',
                      tonal: true,
                      action: () => repository(c).request(
                        'clans/$id/$resource/${row.id}/deny',
                        method: 'POST',
                      ),
                      onSuccess: (_) => r(),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class ClanActionPage extends StatelessWidget {
  const ClanActionPage(this.id, this.action, {super.key});
  final String id, action;
  @override
  Widget build(BuildContext c) => FeatureForm(
    title: action == 'invite' ? 'Invite a member' : 'Clan broadcast',
    fields: action == 'invite'
        ? const [FieldSpec('handle', 'Member handle')]
        : const [
            FieldSpec('message', 'Announcement', kind: FieldKind.multiline),
            FieldSpec(
              'durationDays',
              'Show for (days)',
              kind: FieldKind.integer,
              initial: '3',
            ),
          ],
    button: action == 'invite' ? 'Send invitation' : 'Publish broadcast',
    submit: (v) =>
        repository(c).request('clans/$id/$action', method: 'POST', body: v),
    onSuccess: (_) => c.pop(),
  );
}

class ClanFeedPage extends StatelessWidget {
  const ClanFeedPage(this.id, {super.key});
  final String id;
  @override
  Widget build(BuildContext c) => FeedPage(clanId: id);
}
