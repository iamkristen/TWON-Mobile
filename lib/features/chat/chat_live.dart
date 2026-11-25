import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/api.dart';
import '../../core/models.dart';
import '../../shared/widgets.dart';
import 'chat_bloc.dart';
import 'chat_outbox.dart';

/// CHAT-5 chat pieces: messages waiting to be sent, who is typing or online,
/// and search. States are said in words (screen readers), not only by icons.

class PendingMessages extends StatelessWidget {
  const PendingMessages({super.key, required this.items, required this.bloc});
  final List<OutboxItem> items;
  final ChatBloc bloc;
  @override
  Widget build(BuildContext c) {
    final scheme = Theme.of(c).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.fromLTRB(48, 4, 12, 4),
            child: Semantics(
              liveRegion: true,
              label: switch (item.state) {
                OutboxState.failed => 'Not sent: ${item.error ?? ''}',
                OutboxState.sending => 'Sending',
                OutboxState.queued => 'Waiting for connection',
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: item.state == OutboxState.failed
                          ? scheme.errorContainer
                          : scheme.primary.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Text(
                        '${item.body['body'] ?? ''}'.isNotEmpty
                            ? '${item.body['body']}'
                            : 'Attachment',
                        style: TextStyle(
                          color: item.state == OutboxState.failed
                              ? scheme.onErrorContainer
                              : scheme.onPrimary,
                        ),
                      ),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        item.state == OutboxState.failed
                            ? Icons.error_outline
                            : Icons.schedule,
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(switch (item.state) {
                          OutboxState.failed => item.error ?? 'Not sent',
                          OutboxState.sending => 'Sending…',
                          OutboxState.queued =>
                            'Waiting for connection. It will be sent automatically.',
                        }, style: Theme.of(c).textTheme.labelSmall),
                      ),
                      if (item.state == OutboxState.failed)
                        TextButton(
                          onPressed: () =>
                              bloc.retryPending(item.clientMessageId),
                          child: const Text('Retry'),
                        ),
                      if (item.state != OutboxState.sending)
                        TextButton(
                          onPressed: () =>
                              bloc.discardPending(item.clientMessageId),
                          child: const Text('Delete'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// "typing…", or "Online" in a direct message when both people share it.
class ChatStatusLine extends StatefulWidget {
  const ChatStatusLine({
    super.key,
    required this.id,
    required this.isDm,
    required this.typing,
    required this.names,
  });
  final String id;
  final bool isDm;
  final List<String> typing;
  final Map<String, String> names;
  @override
  State<ChatStatusLine> createState() => _ChatStatusLineState();
}

class _ChatStatusLineState extends State<ChatStatusLine> {
  String presence = 'hidden';
  Timer? timer;
  @override
  void initState() {
    super.initState();
    if (widget.isDm) {
      load();
      timer = Timer.periodic(const Duration(seconds: 30), (_) => load());
    }
  }

  Future<void> load() async {
    try {
      final r = asJson(
        await repository(
          context,
        ).request('conversations/${widget.id}/presence'),
      );
      if (mounted) setState(() => presence = '${r['status']}');
    } catch (_) {}
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final names = widget.typing.map((id) => widget.names[id] ?? 'Someone');
    final text = widget.typing.isNotEmpty
        ? (widget.isDm ? 'typing…' : '${names.take(2).join(', ')} typing…')
        : presence == 'online'
        ? 'Online'
        : null;
    if (text == null) return const SizedBox.shrink();
    return Semantics(
      liveRegion: true,
      child: Text(
        text,
        style: Theme.of(c).textTheme.labelSmall?.copyWith(
          color: Theme.of(c).colorScheme.primary,
          fontStyle: widget.typing.isNotEmpty ? FontStyle.italic : null,
        ),
      ),
    );
  }
}

/// Searches one chat (only the member's own period; terms are sent in the body).
class MessageSearchPage extends StatefulWidget {
  const MessageSearchPage(this.id, {super.key});
  final String id;
  @override
  State<MessageSearchPage> createState() => _MessageSearchPageState();
}

class _MessageSearchPageState extends State<MessageSearchPage> {
  final input = TextEditingController();
  final hits = <Json>[];
  String? cursor, error;
  bool loading = false, searched = false;
  String term = '';
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  Future<void> search({bool more = false}) async {
    final q = more ? term : input.text.trim();
    if (q.length < 2) return;
    setState(() {
      loading = true;
      error = null;
      if (!more) {
        hits.clear();
        cursor = null;
        term = q;
      }
    });
    try {
      final r = asJson(
        await repository(context).request(
          'conversations/${widget.id}/search',
          method: 'POST',
          body: {'q': q, if (more && cursor != null) 'cursor': cursor},
        ),
      );
      if (!mounted) return;
      setState(() {
        hits.addAll(((r['items'] as List?) ?? const []).map(asJson));
        cursor = r['nextCursor'] as String?;
        searched = true;
      });
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is AppFailure ? e.message : 'Search did not work.',
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(
      title: TextField(
        controller: input,
        autofocus: true,
        maxLength: 80,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => search(),
        decoration: const InputDecoration(
          hintText: 'Search this chat',
          counterText: '',
        ),
      ),
      actions: [
        IconButton(
          tooltip: 'Search',
          onPressed: () => search(),
          icon: const Icon(Icons.search),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (error != null) ErrorPanel(error!, retry: () => search()),
        for (final h in hits)
          ListTile(
            title: Text('${h['body']}', maxLines: 3),
            subtitle: Text(
              '${asJson(h['sender'])['fullName'] ?? ''} · ${DateTime.tryParse('${h['createdAt']}')?.toLocal().toString().substring(0, 16) ?? ''}',
            ),
          ),
        if (loading) const Center(child: CircularProgressIndicator()),
        if (!loading && searched && hits.isEmpty && cursor == null)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('No messages found.', textAlign: TextAlign.center),
          ),
        if (!loading && cursor != null)
          TextButton(
            onPressed: () => search(more: true),
            child: Text(
              hits.isEmpty
                  ? 'Nothing recent. Search older messages'
                  : 'Search older messages',
            ),
          ),
      ],
    ),
  );
}

void openMessageSearch(BuildContext c, String id) => Navigator.of(
  c,
).push(MaterialPageRoute<void>(builder: (_) => MessageSearchPage(id)));

/// Chats found on the server (beyond the loaded list) for the conversation search.
Future<List<Entity>> searchChatsOnServer(AppRepository api, String q) async {
  if (q.trim().length < 2) return const [];
  try {
    final rows = await api.request(
      'conversations/search',
      method: 'POST',
      body: {'q': q.trim()},
    );
    return ((rows as List?) ?? const []).map((r) => Entity(asJson(r))).toList();
  } catch (_) {
    return const [];
  }
}

void openChat(BuildContext c, String id) => c.push('/messages/$id');
