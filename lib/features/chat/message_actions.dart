import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/models.dart';

const quickMessageReactions = ['👍', '❤️', '😂', '😮', '😢', '🙏', '🙄'];
const extraMessageReactions = ['🔥', '👏', '🎉', '💯', '👎', '😍', '🤔'];

class MessageActionResult {
  const MessageActionResult({this.action, this.emoji});
  final String? action, emoji;
}

String messagePreview(Entity message) {
  if (message.flag('isDeleted')) return 'This message was deleted';
  if (message.text('body').isNotEmpty) return message.text('body');
  if (message.text('attachment').isNotEmpty ||
      message.rows('attachments').isNotEmpty) {
    return 'Attachment';
  }
  return 'Message';
}

Future<MessageActionResult?> showMessageActions({
  required BuildContext context,
  required Entity message,
  required String userId,
}) => showGeneralDialog<MessageActionResult>(
  context: context,
  barrierDismissible: true,
  barrierLabel: 'Close message actions',
  barrierColor: Colors.black.withValues(alpha: .25),
  transitionDuration: MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 160),
  pageBuilder: (c, _, _) =>
      MessageActionsPanel(message: message, userId: userId),
);

class MessageActionsPanel extends StatefulWidget {
  const MessageActionsPanel({
    super.key,
    required this.message,
    required this.userId,
  });
  final Entity message;
  final String userId;
  @override
  State<MessageActionsPanel> createState() => _MessageActionsPanelState();
}

class _MessageActionsPanelState extends State<MessageActionsPanel> {
  bool expanded = false;
  @override
  Widget build(BuildContext c) {
    final own = entityId(widget.message.data['senderId']) == widget.userId;
    final scheme = Theme.of(c).colorScheme;
    final selected = widget.message
        .rows('reactions')
        .where((r) => entityId(r['userId']) == widget.userId)
        .map((r) => r['emoji'])
        .toSet();
    void choose(String action) =>
        Navigator.pop(c, MessageActionResult(action: action));
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Material(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(24),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Message actions',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Close message actions',
                            onPressed: () => Navigator.pop(c),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        messagePreview(widget.message),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          for (final emoji in [
                            ...quickMessageReactions,
                            if (expanded) ...extraMessageReactions,
                          ])
                            Semantics(
                              selected: selected.contains(emoji),
                              child: IconButton.filledTonal(
                                key: ValueKey('react-$emoji'),
                                tooltip: selected.contains(emoji)
                                    ? 'Remove $emoji reaction'
                                    : 'React $emoji',
                                style: IconButton.styleFrom(
                                  minimumSize: const Size(48, 48),
                                  backgroundColor: selected.contains(emoji)
                                      ? scheme.primaryContainer
                                      : scheme.surfaceContainer,
                                  side: selected.contains(emoji)
                                      ? BorderSide(color: scheme.primary)
                                      : BorderSide.none,
                                ),
                                onPressed: () => Navigator.pop(
                                  c,
                                  MessageActionResult(emoji: emoji),
                                ),
                                icon: Text(
                                  emoji,
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontFamilyFallback: [
                                      'Apple Color Emoji',
                                      'Noto Color Emoji',
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          IconButton.filledTonal(
                            tooltip: expanded
                                ? 'Fewer reactions'
                                : 'More reactions',
                            onPressed: () =>
                                setState(() => expanded = !expanded),
                            icon: Icon(expanded ? Icons.remove : Icons.add),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.reply_rounded),
                      title: const Text('Reply'),
                      onTap: () => choose('reply'),
                    ),
                    if (widget.message.text('body').isNotEmpty)
                      ListTile(
                        leading: const Icon(Icons.copy_outlined),
                        title: const Text('Copy message'),
                        onTap: () => choose('copy'),
                      ),
                    if (own && widget.message.text('body').isNotEmpty)
                      ListTile(
                        leading: const Icon(Icons.edit_outlined),
                        title: const Text('Edit message'),
                        onTap: () => choose('edit'),
                      ),
                    ListTile(
                      leading: const Icon(Icons.flag_outlined),
                      title: const Text('Report message'),
                      onTap: () => choose('report'),
                    ),
                    if (own)
                      ListTile(
                        leading: Icon(
                          Icons.delete_outline,
                          color: scheme.error,
                        ),
                        title: Text(
                          'Delete for everyone',
                          style: TextStyle(color: scheme.error),
                        ),
                        onTap: () => choose('delete'),
                      ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MessageReactionChips extends StatelessWidget {
  const MessageReactionChips({
    super.key,
    required this.reactions,
    required this.userId,
    required this.onReact,
    this.busy = false,
  });
  final List<Json> reactions;
  final String userId;
  final ValueChanged<String> onReact;
  final bool busy;
  @override
  Widget build(BuildContext c) {
    final counts = <String, int>{};
    final mine = <String>{};
    for (final reaction in reactions) {
      final emoji = '${reaction['emoji'] ?? ''}';
      if (emoji.isEmpty) continue;
      counts.update(emoji, (n) => n + 1, ifAbsent: () => 1);
      if (entityId(reaction['userId']) == userId) mine.add(emoji);
    }
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        for (final entry in counts.entries)
          InputChip(
            key: ValueKey('reaction-${entry.key}'),
            selected: mine.contains(entry.key),
            showCheckmark: false,
            tooltip: mine.contains(entry.key)
                ? 'Remove ${entry.key} reaction'
                : 'React ${entry.key}',
            label: Text('${entry.key} ${entry.value}'),
            onPressed: busy ? null : () => onReact(entry.key),
          ),
      ],
    );
  }
}
