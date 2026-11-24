import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../core/collection_cubit.dart';
import '../../core/models.dart';
import '../../core/realtime.dart';
import '../../shared/widgets.dart';
import '../auth/auth_cubit.dart';

/// CHAT-2: message requests, clan chat moderation, the member's own decisions.
/// The server enforces every rule; this only offers what it allows.
const moderationReasons = {
  'harassment': 'Harassment',
  'spam': 'Spam',
  'hate': 'Hate speech',
  'impersonation': 'Impersonation',
  'nudity': 'Nudity',
  'violence': 'Violence',
  'scam': 'Scam',
  'other': 'Other',
};

/// Asks for a reason code; null when cancelled.
Future<String?> chooseReason(BuildContext c, String title) =>
    showDialog<String>(
      context: c,
      builder: (d) => SimpleDialog(
        title: Text(title),
        children: [
          for (final r in moderationReasons.entries)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(d, r.key),
              child: Text(r.value),
            ),
        ],
      ),
    );

class MessageRequestsPanel extends StatefulWidget {
  const MessageRequestsPanel({super.key});
  @override
  State<MessageRequestsPanel> createState() => _MessageRequestsPanelState();
}

class _MessageRequestsPanelState extends State<MessageRequestsPanel> {
  List<Json> requests = const [];
  StreamSubscription<RealtimeEvent>? events;

  @override
  void initState() {
    super.initState();
    load();
    events = context.read<RealtimeService>().events.stream.listen((event) {
      if (!mounted) return;
      if (event.name == 'chat:conversation_changed' ||
          event.name == 'connect') {
        load();
      }
    });
  }

  @override
  void dispose() {
    events?.cancel();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final rows = await repository(context).request('conversations/requests');
      if (mounted && rows is List) {
        setState(() => requests = rows.map(asJson).toList());
      }
    } catch (_) {
      // The list itself shows connection errors.
    }
  }

  @override
  Widget build(BuildContext c) => requests.isEmpty
      ? const SizedBox.shrink()
      : Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  'Message requests',
                  style: Theme.of(c).textTheme.labelLarge,
                ),
              ),
              for (final r in requests) ...[
                ListTile(
                  title: Text(
                    '${asJson(r['from'])['fullName'] ?? 'Pack member'}',
                  ),
                  subtitle: Text(
                    '${r['preview']}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => c.push('/messages/${r['conversationId']}'),
                ),
                RequestActions(
                  conversationId: '${r['conversationId']}',
                  senderId: entityId(r['from']),
                  onAnswered: (accepted) {
                    load();
                    c.read<CollectionCubit>().load();
                    if (accepted) c.push('/messages/${r['conversationId']}');
                  },
                ),
              ],
            ],
          ),
        );
}

/// Accept, decline (the sender is not told), block, and optionally report.
class RequestActions extends StatefulWidget {
  const RequestActions({
    super.key,
    required this.conversationId,
    required this.senderId,
    required this.onAnswered,
    this.onReport,
  });
  final String conversationId, senderId;
  final void Function(bool accepted) onAnswered;
  final VoidCallback? onReport;
  @override
  State<RequestActions> createState() => _RequestActionsState();
}

class _RequestActionsState extends State<RequestActions> {
  bool busy = false;

  Future<void> answer(String how) async {
    final api = repository(context);
    final auth = context.read<AuthCubit>();
    if (how == 'block' &&
        !await confirm(
          context,
          'Block account?',
          'They will not be able to message you.',
        )) {
      return;
    }
    if (!mounted) return;
    setState(() => busy = true);
    try {
      await api.request(
        'conversations/${widget.conversationId}/request/${how == 'accept' ? 'accept' : 'decline'}',
        method: 'POST',
      );
      if (how == 'block') {
        await api.request(
          'users/me/blocked-users',
          method: 'POST',
          body: {'userId': widget.senderId},
        );
        await auth.refreshProfile();
      }
      if (mounted) widget.onAnswered(how == 'accept');
    } catch (error) {
      if (mounted) notice(context, error.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext c) => Wrap(
    children: [
      for (final (how, label) in const [
        ('accept', 'Accept'),
        ('decline', 'Decline'),
        ('block', 'Block'),
      ])
        TextButton(
          onPressed: busy ? null : () => answer(how),
          child: Text(label),
        ),
      if (widget.onReport != null)
        TextButton(onPressed: widget.onReport, child: const Text('Report')),
    ],
  );
}

Future<void> showClanModeration(
  BuildContext c,
  String conversationId,
  Json conversation,
) => showModalBottomSheet<void>(
  context: c,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => RepositoryProvider.value(
    value: repository(c),
    child: ClanModerationSheet(
      conversationId: conversationId,
      conversation: conversation,
      me: c.read<AuthCubit>().userId,
    ),
  ),
);

class ClanModerationSheet extends StatefulWidget {
  const ClanModerationSheet({
    super.key,
    required this.conversationId,
    required this.conversation,
    required this.me,
  });
  final String conversationId, me;
  final Json conversation;
  @override
  State<ClanModerationSheet> createState() => _ClanModerationSheetState();
}

class _ClanModerationSheetState extends State<ClanModerationSheet> {
  Json state = const {};
  bool busy = false;
  String get base => 'moderation/chats/${widget.conversationId}';

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final data = asJson(await repository(context).request(base));
      if (mounted) setState(() => state = data);
    } catch (error) {
      if (mounted) notice(context, error.toString());
    }
  }

  Future<void> run(String path, String method, {Object? body}) async {
    setState(() => busy = true);
    try {
      await repository(
        context,
      ).request('$base/$path', method: method, body: body);
      await load();
    } catch (error) {
      if (mounted) notice(context, error.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> act(String action, String uid) async {
    switch (action) {
      case 'appoint':
        await run('moderators/$uid', 'POST');
      case 'dismiss':
        await run('moderators/$uid', 'DELETE');
      case 'lift':
        await run('restrictions/$uid', 'DELETE');
      case 'restrict':
        final reason = await chooseReason(context, 'Restrict for 1 day');
        if (reason != null) {
          await run(
            'restrictions',
            'POST',
            body: {'userId': uid, 'reasonCode': reason, 'hours': 24},
          );
        }
    }
  }

  @override
  Widget build(BuildContext c) {
    final moderators = [...?(state['moderators'] as List?)];
    final restricted = {
      for (final r in [...?(state['restrictions'] as List?)])
        '${asJson(r)['userId']}',
    };
    final isLeader = state['isLeader'] == true;
    final members = [...?(widget.conversation['participants'] as List?)];
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(16),
        children: [
          Text('Chat moderation', style: Theme.of(c).textTheme.titleLarge),
          for (final m in members)
            Builder(
              builder: (_) {
                final uid = entityId(m);
                final leader = moderators.isNotEmpty && moderators.first == uid;
                final moderator = moderators.skip(1).contains(uid);
                final canAct =
                    state['canModerate'] == true &&
                    uid != widget.me &&
                    !leader &&
                    (isLeader || !moderator);
                final name = uid == widget.me
                    ? 'You'
                    : '${asJson(m)['fullName'] ?? 'Pack member'}';
                final options = {
                  if (isLeader && uid != widget.me)
                    moderator ? 'dismiss' : 'appoint': moderator
                        ? 'Remove moderator'
                        : 'Make moderator',
                  if (canAct)
                    restricted.contains(uid)
                        ? 'lift'
                        : 'restrict': restricted.contains(uid)
                        ? 'Lift restriction'
                        : 'Restrict posting',
                };
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(name),
                  subtitle: Text(
                    '${leader
                        ? 'Leader'
                        : moderator
                        ? 'Moderator'
                        : 'Member'}${restricted.contains(uid) ? ' · restricted' : ''}',
                  ),
                  trailing: options.isEmpty
                      ? null
                      : PopupMenuButton<String>(
                          tooltip: 'Moderation options for $name',
                          enabled: !busy,
                          onSelected: (a) => act(a, uid),
                          itemBuilder: (_) => [
                            for (final o in options.entries)
                              PopupMenuItem(value: o.key, child: Text(o.value)),
                          ],
                        ),
                );
              },
            ),
        ],
      ),
    );
  }
}

/// Removals and restrictions affecting me, each with one appeal.
class ModerationDecisionsPage extends StatelessWidget {
  const ModerationDecisionsPage({super.key});
  @override
  Widget build(BuildContext c) => CollectionView(
    path: 'moderation/mine',
    empty: 'No moderation decisions about your messages.',
    builder: (d, row, refresh) {
      final appeal = row.object('appeal');
      return Card(
        child: ListTile(
          title: Text(
            '${row.text('action') == 'restrict' ? 'Your messaging was restricted' : 'A message of yours was removed'} by ${row.text('by') == 'clan' ? 'your clan' : 'TWON'}',
          ),
          subtitle: Text(
            [
              moderationReasons[row.text('reasonCode')] ?? '',
              if (appeal.isNotEmpty)
                switch (appeal['status']) {
                  'open' => 'Appeal under review',
                  'upheld' => 'Appeal: decision kept',
                  _ => 'Appeal: decision reversed',
                },
            ].join(' · '),
          ),
          trailing: row.flag('canAppeal')
              ? TextButton(
                  onPressed: () => _appeal(d, row.id, refresh),
                  child: const Text('Appeal'),
                )
              : null,
        ),
      );
    },
  );

  Future<void> _appeal(BuildContext c, String id, VoidCallback refresh) async {
    final api = repository(c);
    final text = await showDialog<String>(
      context: c,
      builder: (_) => const _AppealDialog(),
    );
    if (text == null) return;
    try {
      await api.request(
        'moderation/appeals',
        method: 'POST',
        body: {'actionId': id, 'statement': text},
      );
      refresh();
    } catch (error) {
      if (c.mounted) notice(c, error.toString());
    }
  }
}

class _AppealDialog extends StatefulWidget {
  const _AppealDialog();
  @override
  State<_AppealDialog> createState() => _AppealDialogState();
}

class _AppealDialogState extends State<_AppealDialog> {
  final text = TextEditingController();
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => AlertDialog(
    title: const Text('Why should this be reviewed?'),
    content: TextField(
      controller: text,
      maxLength: 2000,
      minLines: 3,
      maxLines: 6,
      onChanged: (_) => setState(() {}),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(c),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: text.text.trim().length < 10
            ? null
            : () => Navigator.pop(c, text.text.trim()),
        child: const Text('Send appeal'),
      ),
    ],
  );
}
