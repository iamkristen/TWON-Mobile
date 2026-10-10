import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/models.dart';
import '../../core/realtime.dart';
import '../../shared/widgets.dart';
import '../../shared/forms.dart';
import '../auth/auth_cubit.dart';
import '../account/account_pages.dart';
import 'chat_bloc.dart';
import 'message_actions.dart';

class ConversationsPage extends StatelessWidget {
  const ConversationsPage({super.key});
  @override
  Widget build(BuildContext c) => CollectionView(
    path: 'conversations',
    empty: 'Start a conversation with a pack member.',
    builder: (d, row, r) {
      return ConversationTile(row: row);
    },
  );
}

class ConversationTile extends StatelessWidget {
  const ConversationTile({super.key, required this.row, this.onTap});
  final Entity row;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext c) {
    final me = c.read<AuthCubit>().userId;
    final others = row
        .rows('participants')
        .where((p) => entityId(p) != me)
        .toList();
    final title = row.text('name').isNotEmpty
        ? row.text('name')
        : others
              .map((p) => p['fullName'] ?? p['handle'] ?? 'Member')
              .join(', ');
    return ListTile(
      contentPadding: const EdgeInsets.all(14),
      leading: MemberAvatar(others.firstOrNull ?? {'fullName': title}),
      title: Text(
        title.isEmpty ? 'Pack chat' : title,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Text(
        row.object('lastMessage')['text']?.toString() ?? 'Say hello',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: row.number('unreadCount') > 0
          ? Badge(
              label: Text('${row.number('unreadCount')}'),
              child: const Icon(Icons.chevron_right),
            )
          : const Icon(Icons.chevron_right),
      onTap: onTap ?? () => c.push('/messages/${row.id}', extra: row.data),
    );
  }
}

Future<void> searchConversations(BuildContext c) async {
  final delegate = ConversationSearch(c);
  try {
    await showSearch<void>(context: c, delegate: delegate);
  } finally {
    await delegate.routeCompleted;
    delegate.dispose();
  }
}

class ConversationSearch extends SearchDelegate<void> {
  ConversationSearch(this.origin) : super(searchFieldLabel: 'Search chats') {
    results = load();
  }
  final BuildContext origin;
  Future<dynamic>? routeCompleted;
  late Future<List<Entity>> results;
  final cancel = CancelToken();
  @override
  void dispose() {
    cancel.cancel();
    super.dispose();
  }

  Future<List<Entity>> load() async {
    final api = repository(origin);
    final rows = <String, Entity>{};
    final cursors = <String>{};
    String? cursor;
    do {
      final page = await api.page(
        'conversations',
        query: {'limit': 100, 'cursor': ?cursor},
        cancel: cancel,
      );
      for (final row in page.items) {
        rows[row.id] = row;
      }
      cursor = page.cursor;
    } while (cursor != null && cursors.add(cursor));
    return rows.values.toList();
  }

  @override
  List<Widget> buildActions(BuildContext c) => [
    if (query.isNotEmpty)
      IconButton(
        tooltip: 'Clear search',
        onPressed: () => query = '',
        icon: const Icon(Icons.close_rounded),
      ),
  ];
  @override
  Widget buildLeading(BuildContext c) =>
      BackButton(onPressed: () => close(c, null));
  @override
  Widget buildSuggestions(BuildContext c) => buildResults(c);
  @override
  Widget buildResults(BuildContext c) {
    routeCompleted ??= ModalRoute.of(c)?.completed;
    return StatefulBuilder(
      builder: (c, update) => FutureBuilder<List<Entity>>(
        future: results,
        builder: (d, snapshot) {
          final needle = query.trim().toLowerCase();
          final me = origin.read<AuthCubit>().userId;
          final rows = (snapshot.data ?? [])
              .where(
                (row) => [
                  row.text('name'),
                  for (final p
                      in row
                          .rows('participants')
                          .where((p) => entityId(p) != me)) ...[
                    '${p['fullName'] ?? ''}',
                    '${p['handle'] ?? ''}',
                  ],
                  '${row.object('lastMessage')['text'] ?? ''}',
                ].join(' ').toLowerCase().contains(needle),
              )
              .toList();
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              ListTile(
                leading: const Icon(Icons.person_add_alt_rounded),
                title: const Text('New conversation'),
                onTap: () {
                  close(c, null);
                  origin.push('/messages/new');
                },
              ),
              const Divider(height: 24),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Center(child: CircularProgressIndicator())
              else if (snapshot.hasError)
                ErrorPanel(
                  snapshot.error.toString(),
                  retry: () {
                    update(() => results = load());
                  },
                )
              else if (rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No chats found.', textAlign: TextAlign.center),
                )
              else
                ...rows.map(
                  (row) => ConversationTile(
                    row: row,
                    onTap: () {
                      close(c, null);
                      origin.push('/messages/${row.id}', extra: row.data);
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class NewConversationPage extends StatefulWidget {
  const NewConversationPage({super.key});
  @override
  State<NewConversationPage> createState() => _NewConversationPageState();
}

class _NewConversationPageState extends State<NewConversationPage> {
  String q = '';
  final selected = <String, Json>{};
  final name = TextEditingController();
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          decoration: const InputDecoration(
            labelText: 'Search members',
            prefixIcon: Icon(Icons.search),
          ),
          onSubmitted: (v) => setState(() => q = v.trim()),
        ),
      ),
      if (selected.length > 1)
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: name,
            decoration: const InputDecoration(labelText: 'Group name'),
            onChanged: (_) => setState(() {}),
          ),
        ),
      if (selected.isNotEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            children: selected.values
                .map(
                  (u) => InputChip(
                    label: Text('${u['fullName']}'),
                    onDeleted: () =>
                        setState(() => selected.remove(entityId(u))),
                  ),
                )
                .toList(),
          ),
        ),
      Expanded(
        child: q.isEmpty
            ? const Center(child: Text('Search for someone to message.'))
            : CollectionView(
                key: ValueKey(q),
                path: 'users/search',
                query: {'q': q},
                builder: (d, user, r) => CheckboxListTile(
                  secondary: MemberAvatar(user.data),
                  title: Text(user.text('fullName')),
                  subtitle: Text('@${user.text('handle')}'),
                  value: selected.containsKey(user.id),
                  onChanged: (value) => setState(() {
                    if (value == true) {
                      selected[user.id] = user.data;
                    } else {
                      selected.remove(user.id);
                    }
                  }),
                ),
              ),
      ),
      Padding(
        padding: const EdgeInsets.all(16),
        child: ActionButton(
          label: selected.length > 1 ? 'Create group' : 'Start conversation',
          enabled:
              selected.isNotEmpty &&
              (selected.length < 2 || name.text.trim().isNotEmpty),
          action: () => repository(c).request(
            'conversations',
            method: 'POST',
            body: {
              'participantIds': selected.keys.toList(),
              'type': selected.length > 1 ? 'group' : 'dm',
              if (selected.length > 1) 'name': name.text.trim(),
            },
          ),
          onSuccess: (v) =>
              c.pushReplacement('/messages/${entityId(v)}', extra: asJson(v)),
        ),
      ),
    ],
  );
}

class ChatPage extends StatelessWidget {
  const ChatPage(this.id, {super.key, this.conversation = const {}});
  final String id;
  final Json conversation;
  @override
  Widget build(BuildContext c) => BlocProvider(
    create: (d) => ChatBloc(repository(d), d.read<RealtimeService>(), id),
    child: ChatBody(id, conversation),
  );
}

class ChatBody extends StatefulWidget {
  const ChatBody(this.id, this.conversation, {super.key});
  final String id;
  final Json conversation;
  @override
  State<ChatBody> createState() => _ChatBodyState();
}

class _ChatBodyState extends State<ChatBody> with WidgetsBindingObserver {
  int lastSent = 0;
  final input = TextEditingController();
  final inputFocus = FocusNode();
  final reacting = <String>{};
  bool menuOpen = false;
  final recorder = AudioRecorder();
  Entity? reply;
  bool uploading = false, recording = false;
  String? attachment, thumbnail, voicePath;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    input.dispose();
    inputFocus.dispose();
    recorder.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    context.read<ChatBloc>().active = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.resumed && mounted) {
      context.read<ChatBloc>().add(ChatLoad());
    }
    if (state != AppLifecycleState.resumed && recording) stopRecording();
  }

  Future<void> upload({bool file = false}) async {
    try {
      String? path;
      if (file) {
        final result = await FilePicker.pickFile();
        path = result?.path;
      } else {
        path = (await ImagePicker().pickImage(
          source: ImageSource.gallery,
          maxWidth: 1800,
          imageQuality: 85,
        ))?.path;
      }
      if (path == null || !mounted) return;
      setState(() => uploading = true);
      final data = await repository(context).upload(path);
      if (mounted) {
        setState(() {
          attachment = data['url'];
          thumbnail = data['thumbnailUrl'];
        });
      }
    } catch (error) {
      if (mounted) notice(context, error.toString());
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  Future<void> startRecording() async {
    try {
      if (!await recorder.hasPermission()) {
        throw const AppFailure(
          'Microphone permission is required to record a voice message.',
        );
      }
      final dir = await getTemporaryDirectory();
      voicePath =
          '${dir.path}/twon-voice-${DateTime.now().microsecondsSinceEpoch}.m4a';
      await recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: voicePath!,
      );
      if (mounted) setState(() => recording = true);
    } catch (error) {
      if (mounted) notice(context, error.toString());
    }
  }

  Future<void> stopRecording() async {
    try {
      final path = await recorder.stop();
      if (mounted) setState(() => recording = false);
      if (path == null || !mounted) return;
      setState(() => uploading = true);
      final data = await repository(context).upload(path);
      await File(path).delete().catchError((_) => File(path));
      if (mounted) setState(() => attachment = data['url']);
    } catch (error) {
      if (mounted) notice(context, error.toString());
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  void startReply(Entity message) {
    if (message.flag('isDeleted')) return;
    setState(() => reply = message);
    inputFocus.requestFocus();
  }

  Future<void> react(Entity message, String emoji) async {
    if (message.flag('isDeleted') || reacting.contains(message.id)) return;
    final bloc = context.read<ChatBloc>();
    final me = context.read<AuthCubit>().userId;
    final rows = bloc.state.messages.where((m) => m.id == message.id);
    final current = rows.isEmpty ? message : rows.first;
    final remove = current
        .rows('reactions')
        .any((r) => entityId(r['userId']) == me && r['emoji'] == emoji);
    setState(() => reacting.add(message.id));
    HapticFeedback.selectionClick();
    try {
      final result = await repository(context).request(
        'conversations/${widget.id}/messages/${message.id}/reactions',
        method: remove ? 'DELETE' : 'POST',
        body: {'emoji': emoji},
      );
      if (!mounted) return;
      bloc.add(ChatPatch(Entity(asJson(result))));
    } catch (error) {
      if (mounted) notice(context, error.toString());
    } finally {
      if (mounted) setState(() => reacting.remove(message.id));
    }
  }

  Future<void> menu(Entity message) async {
    if (menuOpen || message.flag('isDeleted')) return;
    menuOpen = true;
    HapticFeedback.mediumImpact();
    final me = context.read<AuthCubit>().userId;
    final bloc = context.read<ChatBloc>();
    final api = repository(context);
    final own = entityId(message.data['senderId']) == me;
    MessageActionResult? selected;
    try {
      selected = await showMessageActions(
        context: context,
        message: message,
        userId: me,
      );
    } finally {
      menuOpen = false;
    }
    if (!mounted || selected == null) return;
    if (selected.emoji != null) {
      await react(message, selected.emoji!);
      return;
    }
    switch (selected.action) {
      case 'reply':
        startReply(message);
      case 'copy':
        await Clipboard.setData(ClipboardData(text: message.text('body')));
        if (mounted) notice(context, 'Message copied');
      case 'report':
        showReport(context, 'message', message.id);
      case 'edit':
        if (!own) return;
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          builder: (d) => SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(d).bottom,
              ),
              child: SizedBox(
                height: MediaQuery.sizeOf(d).height * .7,
                child: FeatureForm(
                  title: 'Edit message',
                  fields: [
                    FieldSpec(
                      'body',
                      'Message',
                      kind: FieldKind.multiline,
                      initial: message.text('body'),
                      maxLength: 50000,
                    ),
                  ],
                  submit: (v) => api.request(
                    'conversations/${widget.id}/messages/${message.id}',
                    method: 'PATCH',
                    body: v,
                  ),
                  onSuccess: (result) {
                    if (!mounted || !d.mounted) return;
                    bloc.add(ChatPatch(Entity(asJson(result))));
                    Navigator.pop(d);
                  },
                ),
              ),
            ),
          ),
        );
      case 'delete':
        if (!own ||
            !await confirm(
              context,
              'Delete message',
              'Delete this message for everyone?',
            )) {
          return;
        }
        if (!mounted) return;
        try {
          await api.request(
            'conversations/${widget.id}/messages/${message.id}',
            method: 'DELETE',
          );
          if (!mounted) return;
          bloc.add(
            ChatPatch(
              Entity({
                ...message.data,
                'isDeleted': true,
                'body': '',
                'attachments': [],
                'attachment': '',
                'reactions': [],
              }),
            ),
          );
          if (reply?.id == message.id) setState(() => reply = null);
        } catch (error) {
          if (mounted) notice(context, error.toString());
        }
    }
  }

  @override
  Widget build(BuildContext c) => BlocConsumer<ChatBloc, ChatState>(
    listenWhen: (a, b) => a.sent != b.sent || a.error != b.error,
    listener: (d, s) {
      if (s.error != null) notice(d, s.error!);
      if (s.sent > lastSent) {
        lastSent = s.sent;
        input.clear();
        setState(() {
          reply = null;
          attachment = null;
          thumbnail = null;
        });
      }
    },
    builder: (d, s) {
      final bloc = d.read<ChatBloc>();
      final blocked = widget.conversation['dmMessagingBlocked'] == true;
      return Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    widget.conversation['name']?.toString().isNotEmpty == true
                        ? '${widget.conversation['name']}'
                        : 'Pack conversation',
                    style: Theme.of(c).textTheme.titleMedium,
                  ),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Chat options',
                onSelected: (value) async {
                  try {
                    await repository(c).request(
                      'conversations/${widget.id}/mute',
                      method: value == 'unmute' ? 'DELETE' : 'POST',
                      body: value == 'unmute' ? null : {'until': null},
                    );
                    if (c.mounted) {
                      notice(
                        c,
                        value == 'unmute' ? 'Chat unmuted.' : 'Chat muted.',
                      );
                    }
                  } catch (error) {
                    if (c.mounted) notice(c, error.toString());
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'mute',
                    child: Text('Mute notifications'),
                  ),
                  const PopupMenuItem(
                    value: 'unmute',
                    child: Text('Unmute notifications'),
                  ),
                ],
              ),
            ],
          ),
          Expanded(
            child: s.loading && s.messages.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.all(16),
                    itemCount: s.messages.length + (s.cursor != null ? 1 : 0),
                    itemBuilder: (d, index) {
                      if (index == s.messages.length) {
                        return TextButton(
                          onPressed: () => bloc.add(ChatLoad(older: true)),
                          child: const Text('Load earlier messages'),
                        );
                      }
                      final message = s.messages[index];
                      final own =
                          entityId(message.data['senderId']) ==
                          c.read<AuthCubit>().userId;
                      return Align(
                        alignment: own
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: SwipeReply(
                          enabled: !message.flag('isDeleted'),
                          onReply: () => startReply(message),
                          child: GestureDetector(
                            key: ValueKey('message-bubble-${message.id}'),
                            onDoubleTap: message.flag('isDeleted')
                                ? null
                                : () => menu(message),
                            onLongPress: message.flag('isDeleted')
                                ? null
                                : () => menu(message),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(12),
                              constraints: BoxConstraints(
                                maxWidth: MediaQuery.sizeOf(c).width * .82,
                              ),
                              decoration: BoxDecoration(
                                color: own
                                    ? Theme.of(c).colorScheme.primaryContainer
                                    : Theme.of(c).colorScheme.surfaceContainer,
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (!own)
                                    Text(
                                      message
                                              .object('senderId')['fullName']
                                              ?.toString() ??
                                          'Member',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  if (message.object('replyPreview').isNotEmpty)
                                    Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        border: Border(
                                          left: BorderSide(
                                            color: Theme.of(
                                              c,
                                            ).colorScheme.primary,
                                            width: 3,
                                          ),
                                        ),
                                      ),
                                      child: Text(
                                        message
                                                .object('replyPreview')['body']
                                                ?.toString() ??
                                            'Reply to attachment',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  if (message.flag('isDeleted'))
                                    const Text(
                                      'This message was deleted',
                                      style: TextStyle(
                                        fontStyle: FontStyle.italic,
                                      ),
                                    )
                                  else ...[
                                    if (message.text('body').isNotEmpty)
                                      Text(message.text('body')),
                                    if (message.text('attachment').isNotEmpty)
                                      MessageAttachment(
                                        message.text('attachment'),
                                        thumbnail: message.text(
                                          'attachmentThumbnail',
                                        ),
                                      ),
                                    ...message
                                        .rows('attachments')
                                        .map(
                                          (a) => MessageAttachment(
                                            '${a['url']}',
                                            thumbnail:
                                                '${a['thumbnail'] ?? ''}',
                                          ),
                                        ),
                                    MessageReactionChips(
                                      reactions: message.rows('reactions'),
                                      userId: c.read<AuthCubit>().userId,
                                      busy: reacting.contains(message.id),
                                      onReact: (emoji) => react(message, emoji),
                                    ),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          '${DateTime.tryParse(message.text('createdAt'))?.toLocal().hour ?? ''}:${(DateTime.tryParse(message.text('createdAt'))?.toLocal().minute ?? 0).toString().padLeft(2, '0')}${message.flag('isEdited') ? ' · edited' : ''}',
                                          style: Theme.of(
                                            c,
                                          ).textTheme.labelSmall,
                                        ),
                                        if (own)
                                          Icon(
                                            message.strings('readBy').length > 1
                                                ? Icons.done_all
                                                : Icons.done,
                                            size: 15,
                                          ),
                                        IconButton(
                                          tooltip: 'Reply or react',
                                          visualDensity: VisualDensity.compact,
                                          onPressed: () => menu(message),
                                          icon: const Icon(
                                            Icons.more_horiz,
                                            size: 18,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          if (reply != null)
            ListTile(
              dense: true,
              title: const Text('Replying to'),
              subtitle: Text(
                messagePreview(reply!),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: IconButton(
                tooltip: 'Cancel reply',
                onPressed: () => setState(() => reply = null),
                icon: const Icon(Icons.close),
              ),
            ),
          if (attachment != null)
            ListTile(
              dense: true,
              leading: const Icon(Icons.attachment),
              title: const Text('Attachment ready'),
              trailing: IconButton(
                tooltip: 'Remove attachment',
                onPressed: () => setState(() => attachment = null),
                icon: const Icon(Icons.close),
              ),
            ),
          if (uploading) const LinearProgressIndicator(),
          if (blocked)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Messaging is unavailable for this conversation.'),
            )
          else
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    PopupMenuButton<String>(
                      tooltip: 'Add attachment',
                      enabled: !uploading && !s.sending && !recording,
                      onSelected: (v) => upload(file: v == 'file'),
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'photo',
                          child: Text('Photo'),
                        ),
                        const PopupMenuItem(value: 'file', child: Text('File')),
                      ],
                    ),
                    Expanded(
                      child: TextField(
                        controller: input,
                        focusNode: inputFocus,
                        enabled: !recording,
                        maxLines: 4,
                        minLines: 1,
                        decoration: InputDecoration(
                          hintText: recording
                              ? 'Recording voice message…'
                              : 'Message',
                          contentPadding: const EdgeInsets.all(12),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: recording
                          ? 'Stop recording'
                          : 'Record voice message',
                      onPressed: uploading || s.sending
                          ? null
                          : recording
                          ? stopRecording
                          : startRecording,
                      icon: Icon(
                        recording ? Icons.stop_circle : Icons.mic_none,
                      ),
                    ),
                    IconButton.filled(
                      tooltip: 'Send message',
                      onPressed: s.sending || uploading || recording
                          ? null
                          : () {
                              if (input.text.trim().isEmpty &&
                                  attachment == null) {
                                return;
                              }
                              bloc.add(
                                ChatSend({
                                  'body': input.text.trim(),
                                  if (attachment != null)
                                    'attachment': attachment,
                                  if (thumbnail != null)
                                    'attachmentThumbnail': thumbnail,
                                  if (reply != null) 'replyTo': reply!.id,
                                }),
                              );
                            },
                      icon: s.sending
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );
}

class MessageAttachment extends StatefulWidget {
  const MessageAttachment(this.url, {super.key, this.thumbnail = ''});
  final String url, thumbnail;
  @override
  State<MessageAttachment> createState() => _MessageAttachmentState();
}

class _MessageAttachmentState extends State<MessageAttachment> {
  final player = AudioPlayer();
  bool playing = false;
  StreamSubscription<void>? done;
  @override
  void initState() {
    super.initState();
    done = player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => playing = false);
    });
  }

  @override
  void dispose() {
    done?.cancel();
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final path = Uri.tryParse(widget.url)?.path.toLowerCase() ?? '';
    if (RegExp(r'\.(m4a|mp3|aac|wav|ogg)$').hasMatch(path)) {
      return TextButton.icon(
        onPressed: () async {
          try {
            if (playing) {
              await player.pause();
            } else {
              await player.play(UrlSource(widget.url));
            }
            if (mounted) setState(() => playing = !playing);
          } catch (error) {
            if (c.mounted) notice(c, 'Could not play this recording.');
          }
        },
        icon: Icon(playing ? Icons.pause : Icons.play_arrow),
        label: const Text('Voice message'),
      );
    }
    if (widget.thumbnail.isNotEmpty ||
        RegExp(r'\.(png|jpg|jpeg|webp|gif)$').hasMatch(path)) {
      return InkWell(
        onTap: () => openUrl(widget.url),
        child: BrandImage(
          widget.thumbnail.isNotEmpty ? widget.thumbnail : widget.url,
          height: 170,
        ),
      );
    }
    return TextButton.icon(
      onPressed: () => openUrl(widget.url),
      icon: const Icon(Icons.attach_file),
      label: const Text('Open attachment'),
    );
  }
}
