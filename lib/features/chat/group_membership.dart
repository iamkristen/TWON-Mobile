import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/api.dart';
import '../../core/collection_cubit.dart';
import '../../core/models.dart';
import '../../core/realtime.dart';
import '../../shared/widgets.dart';
import '../auth/auth_cubit.dart';

/// CHAT-1 (CHAT-F01): the server sends each attachment's `kind`; older
/// messages fall back to the URL. No placeholder text is needed.
String chatAttachmentKind(String url, [Object? kind]) {
  const kinds = {'image', 'gif', 'audio', 'video', 'file'};
  if (kind is String && kinds.contains(kind)) return kind;
  final path = Uri.tryParse(url)?.path.toLowerCase() ?? url.toLowerCase();
  if (url.contains('giphy.com/') || path.endsWith('.gif')) return 'gif';
  if (path.contains('/audio/') ||
      RegExp(r'\.(m4a|mp3|aac|wav|ogg|opus)$').hasMatch(path)) {
    return 'audio';
  }
  if (path.contains('/videos/') || RegExp(r'\.(mp4|mov)$').hasMatch(path)) {
    return 'video';
  }
  if (RegExp(r'\.(png|jpg|jpeg|webp)$').hasMatch(path)) return 'image';
  return 'file';
}

final _legacyPlaceholder = RegExp(
  r'^(voice message|sent a gif|sent a photo|sent \d+ photos?( and \d+ documents?)?|📎 .+)$',
  caseSensitive: false,
);

/// The caption to show: empty for placeholder text older clients sent with
/// attachments; a text-only message is always shown.
String chatCaption(String body, bool hasAttachments) {
  final text = body.trim();
  return hasAttachments && _legacyPlaceholder.hasMatch(text) ? '' : text;
}

/// A user-created group (not a DM, not a clan chat).
bool isManagedGroup(Json conversation) =>
    conversation['type'] == 'group' &&
    (conversation['clanId'] == null || '${conversation['clanId']}'.isEmpty) &&
    '${conversation['clanName'] ?? ''}'.isEmpty;

/// CHAT-1 (S01): pending group invitations above the conversation list.
/// Nobody is added to a group without accepting here. Also refreshes the list
/// when membership or read state changes on another device.
class GroupInvitesPanel extends StatefulWidget {
  const GroupInvitesPanel({super.key});
  @override
  State<GroupInvitesPanel> createState() => _GroupInvitesPanelState();
}

class _GroupInvitesPanelState extends State<GroupInvitesPanel> {
  List<Json> invites = const [];
  bool busy = false;
  StreamSubscription<RealtimeEvent>? events;

  @override
  void initState() {
    super.initState();
    load();
    final list = context.read<CollectionCubit>();
    final me = context.read<AuthCubit>().userId;
    events = context.read<RealtimeService>().events.stream.listen((event) {
      if (!mounted) return;
      if (event.name == 'chat:conversation_changed' ||
          event.name == 'connect') {
        load();
        list.load();
      } else if (event.name == 'chat:read' && event.payload['userId'] == me) {
        list.load(); // read on another device
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
      final rows = await repository(context).request('conversations/invites');
      if (mounted && rows is List) {
        setState(() => invites = rows.map(asJson).toList());
      }
    } catch (_) {
      // The list itself shows connection errors.
    }
  }

  Future<void> respond(Json invite, bool join) async {
    final id = '${invite['conversationId']}';
    setState(() => busy = true);
    try {
      await repository(context).request(
        'conversations/$id/invites/${join ? 'accept' : 'decline'}',
        method: 'POST',
      );
      await load();
      if (!mounted) return;
      context.read<CollectionCubit>().load();
      if (join) context.push('/messages/$id');
    } catch (error) {
      if (mounted) notice(context, error.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext c) {
    if (invites.isEmpty) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
              child: Text(
                'Group invitations',
                style: Theme.of(c).textTheme.labelLarge,
              ),
            ),
            for (final invite in invites)
              ListTile(
                leading: const Icon(Icons.groups_rounded),
                title: Text(
                  '${invite['name'] ?? ''}'.isEmpty
                      ? 'Group chat'
                      : '${invite['name']}',
                ),
                subtitle: Text(
                  '${asJson(invite['invitedBy'])['fullName'] ?? 'A pack member'} invited you · ${invite['memberCount']} members',
                ),
                trailing: Wrap(
                  spacing: 4,
                  children: [
                    TextButton(
                      onPressed: busy ? null : () => respond(invite, false),
                      child: const Text('Decline'),
                    ),
                    FilledButton(
                      onPressed: busy ? null : () => respond(invite, true),
                      child: const Text('Join'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// CHAT-1 (S01): members of a user-created group and the actions the viewer's
/// role allows (the server enforces every rule; this hides refused actions).
Future<void> showGroupMembers(
  BuildContext c, {
  required String conversationId,
  required Json conversation,
  required VoidCallback onLeft,
}) => showModalBottomSheet<void>(
  context: c,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => GroupMembersSheet(
    conversationId: conversationId,
    conversation: conversation,
    onLeft: onLeft,
    repository: repository(c),
    me: c.read<AuthCubit>().userId,
  ),
);

class GroupMembersSheet extends StatefulWidget {
  const GroupMembersSheet({
    super.key,
    required this.conversationId,
    required this.conversation,
    required this.onLeft,
    required this.repository,
    required this.me,
  });
  final String conversationId, me;
  final Json conversation;
  final VoidCallback onLeft;
  final AppRepository repository;
  @override
  State<GroupMembersSheet> createState() => _GroupMembersSheetState();
}

class _GroupMembersSheetState extends State<GroupMembersSheet> {
  late Json conversation = widget.conversation;
  bool busy = false;

  Future<void> run(
    String path,
    String method, {
    Object? body,
    String? done,
  }) async {
    setState(() => busy = true);
    try {
      await widget.repository.request(path, method: method, body: body);
      await refresh();
      if (mounted && done != null) notice(context, done);
    } catch (error) {
      if (mounted) notice(context, error.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> refresh() async {
    final data = asJson(
      await widget.repository.request('conversations/${widget.conversationId}'),
    );
    if (mounted && data.isNotEmpty) setState(() => conversation = data);
  }

  /// CHAT-2: name, image and invitations (admins).
  Future<String?> ask(String title, String initial) => showDialog<String>(
    context: context,
    builder: (_) => _NameDialog(title: title, initial: initial),
  );

  Future<void> rename() async {
    final name = await ask('Group name', '${conversation['name'] ?? ''}');
    if (name != null) {
      await run(
        'conversations/${widget.conversationId}',
        'PATCH',
        body: {'name': name},
      );
    }
  }

  Future<void> changeImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) return;
    try {
      final data = await widget.repository.upload(picked.path);
      await run(
        'conversations/${widget.conversationId}',
        'PATCH',
        body: {'image': data['url']},
      );
    } catch (error) {
      if (mounted) notice(context, error.toString());
    }
  }

  Future<void> invite() async {
    final q = await ask('Invite: name or @handle', '');
    if (q == null || !mounted) return;
    try {
      final page = await widget.repository.page(
        'users/search',
        query: {'q': q},
      );
      if (!mounted) return;
      final taken = {
        for (final p in [...?(conversation['participants'] as List?)])
          entityId(p),
        for (final i in [...?(conversation['invites'] as List?)])
          entityId(asJson(i)['userId']),
      };
      final id = await showDialog<String>(
        context: context,
        builder: (d) => SimpleDialog(
          title: const Text('Invite to group'),
          children: [
            for (final u in page.items.where((u) => !taken.contains(u.id)))
              SimpleDialogOption(
                onPressed: () => Navigator.pop(d, u.id),
                child: Text('${u.text('fullName')} (@${u.text('handle')})'),
              ),
          ],
        ),
      );
      if (id != null) {
        await run(
          'conversations/${widget.conversationId}/invites',
          'POST',
          body: {
            'userIds': [id],
          },
          done: 'Invitation sent.',
        );
      }
    } catch (error) {
      if (mounted) notice(context, error.toString());
    }
  }

  @override
  Widget build(BuildContext c) {
    final me = widget.me;
    final id = widget.conversationId;
    final ownerId = entityId(conversation['ownerId']);
    final admins = {
      for (final a in (conversation['admins'] as List? ?? const []))
        entityId(a),
    };
    final iAmOwner = ownerId == me;
    final iAmAdmin = admins.contains(me);
    final members = (conversation['participants'] as List? ?? const [])
        .map((p) => p is Map ? asJson(p) : <String, dynamic>{'_id': '$p'})
        .toList();
    String name(Json m) => entityId(m) == me
        ? 'You'
        : '${m['fullName'] ?? (m['handle'] != null ? '@${m['handle']}' : 'Pack member')}';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Group members', style: Theme.of(c).textTheme.titleLarge),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final m in members)
                    Builder(
                      builder: (_) {
                        final uid = entityId(m);
                        final isOwner = uid == ownerId;
                        final isAdmin = admins.contains(uid);
                        final canRemove =
                            uid != me &&
                            !isOwner &&
                            (iAmOwner || (iAmAdmin && !isAdmin));
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: MemberAvatar(m),
                          title: Text(name(m)),
                          subtitle: Text(
                            isOwner ? 'Owner' : (isAdmin ? 'Admin' : 'Member'),
                          ),
                          trailing: (iAmOwner && uid != me) || canRemove
                              ? PopupMenuButton<String>(
                                  tooltip: 'Member options for ${name(m)}',
                                  enabled: !busy,
                                  onSelected: (action) async {
                                    switch (action) {
                                      case 'remove':
                                        final ok = await confirm(
                                          c,
                                          'Remove member?',
                                          '${name(m)} will lose access to this group straight away.',
                                        );
                                        if (ok) {
                                          await run(
                                            'conversations/$id/members/$uid',
                                            'DELETE',
                                            done: 'Member removed.',
                                          );
                                        }
                                      case 'admin':
                                        await run(
                                          'conversations/$id/admins/$uid',
                                          isAdmin ? 'DELETE' : 'POST',
                                        );
                                      case 'owner':
                                        final ok = await confirm(
                                          c,
                                          'Transfer ownership?',
                                          '${name(m)} will own this group. You stay an admin.',
                                        );
                                        if (ok) {
                                          await run(
                                            'conversations/$id/owner',
                                            'POST',
                                            body: {'userId': uid},
                                            done: 'Ownership transferred.',
                                          );
                                        }
                                    }
                                  },
                                  itemBuilder: (_) => [
                                    if (iAmOwner && uid != me)
                                      PopupMenuItem(
                                        value: 'admin',
                                        child: Text(
                                          isAdmin
                                              ? 'Remove admin'
                                              : 'Make admin',
                                        ),
                                      ),
                                    if (iAmOwner && uid != me)
                                      const PopupMenuItem(
                                        value: 'owner',
                                        child: Text('Make owner'),
                                      ),
                                    if (canRemove)
                                      const PopupMenuItem(
                                        value: 'remove',
                                        child: Text('Remove from group'),
                                      ),
                                  ],
                                )
                              : null,
                        );
                      },
                    ),
                  for (final i in [...?(conversation['invites'] as List?)])
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(
                        '${asJson(asJson(i)['userId'])['fullName'] ?? 'Pack member'}',
                      ),
                      subtitle: const Text('Invited'),
                      trailing: iAmAdmin
                          ? TextButton(
                              onPressed: busy
                                  ? null
                                  : () => run(
                                      'conversations/$id/invites/${entityId(asJson(i)['userId'])}',
                                      'DELETE',
                                    ),
                              child: const Text('Withdraw'),
                            )
                          : null,
                    ),
                ],
              ),
            ),
            if (iAmAdmin)
              Wrap(
                children: [
                  TextButton(
                    onPressed: busy ? null : rename,
                    child: const Text('Rename'),
                  ),
                  TextButton(
                    onPressed: busy ? null : changeImage,
                    child: const Text('Change image'),
                  ),
                  TextButton(
                    onPressed: busy ? null : invite,
                    child: const Text('Invite'),
                  ),
                ],
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: busy
                  ? null
                  : () async {
                      final ok = await confirm(
                        c,
                        'Leave group?',
                        iAmOwner
                            ? 'Ownership passes to the longest-standing admin, or member. You will need a new invitation to come back.'
                            : 'You will need a new invitation to come back, and you will not see what was said while you were away.',
                      );
                      if (!ok) return;
                      setState(() => busy = true);
                      try {
                        await widget.repository.request(
                          'conversations/$id/leave',
                          method: 'POST',
                        );
                        if (c.mounted) Navigator.of(c).pop();
                        widget.onLeft();
                      } catch (error) {
                        if (c.mounted) notice(c, error.toString());
                      } finally {
                        if (mounted) setState(() => busy = false);
                      }
                    },
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Leave group'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.title, required this.initial});
  final String title, initial;
  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final text = TextEditingController(text: widget.initial);
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: text,
      maxLength: 200,
      onChanged: (_) => setState(() {}),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(c),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: text.text.trim().isEmpty
            ? null
            : () => Navigator.pop(c, text.text.trim()),
        child: const Text('OK'),
      ),
    ],
  );
}
