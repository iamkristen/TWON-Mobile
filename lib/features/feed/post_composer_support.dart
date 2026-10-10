import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../core/api.dart';
import '../../core/models.dart';
import '../../shared/widgets.dart';

final socialTokens = RegExp(
  r'(?<![A-Za-z0-9_])(?:@[A-Za-z0-9_]+|#[\p{L}\p{M}\p{N}_]+)',
  unicode: true,
);

class SocialTextController extends TextEditingController {
  SocialTextController({super.text});
  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    // Keep the platform's composing underline intact for IME input.
    if (withComposing &&
        value.composing.isValid &&
        !value.composing.isCollapsed) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    final spans = <InlineSpan>[];
    var offset = 0;
    for (final token in socialTokens.allMatches(text)) {
      spans.add(TextSpan(text: text.substring(offset, token.start)));
      spans.add(
        TextSpan(
          text: token.group(0),
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
      offset = token.end;
    }
    spans.add(TextSpan(text: text.substring(offset)));
    return TextSpan(style: style, children: spans);
  }
}

class MentionRange {
  const MentionRange(this.start, this.end, this.query);
  final int start, end;
  final String query;
  String get key => '$start:$end:$query';
}

MentionRange? activeMention(String text, TextSelection selection) {
  if (!selection.isValid || !selection.isCollapsed) return null;
  final cursor = selection.baseOffset;
  if (cursor < 1 || cursor > text.length) return null;
  var i = cursor - 1;
  final handleChar = RegExp(r'[A-Za-z0-9_]');
  while (i >= 0 && handleChar.hasMatch(text[i])) {
    i--;
  }
  if (i < 0 ||
      text[i] != '@' ||
      i > 0 && !RegExp(r'\s').hasMatch(text[i - 1])) {
    return null;
  }
  var end = cursor;
  while (end < text.length && handleChar.hasMatch(text[end])) {
    end++;
  }
  return MentionRange(i, end, text.substring(i + 1, cursor));
}

class MentionState {
  const MentionState({
    this.range,
    this.items = const [],
    this.loading = false,
    this.error,
  });
  final MentionRange? range;
  final List<Entity> items;
  final bool loading;
  final String? error;
}

class MentionCubit extends Cubit<MentionState> {
  MentionCubit(this.api) : super(const MentionState());
  final AppRepository api;
  Timer? _debounce;
  CancelToken? _cancel;
  int _generation = 0;
  void update(MentionRange? range, {bool retry = false}) {
    if (!retry && range?.key == state.range?.key) return;
    final generation = ++_generation;
    _debounce?.cancel();
    _cancel?.cancel();
    emit(
      MentionState(
        range: range,
        loading: range != null && range.query.isNotEmpty,
      ),
    );
    if (range == null || range.query.isEmpty) return;
    _debounce = Timer(const Duration(milliseconds: 220), () async {
      final cancel = _cancel = CancelToken();
      try {
        final page = await api.page(
          'users/search',
          query: {'q': range.query, 'limit': 5},
          cancel: cancel,
        );
        if (!isClosed && generation == _generation) {
          emit(MentionState(range: range, items: page.items));
        }
      } catch (error) {
        if (!isClosed && generation == _generation && !cancel.isCancelled) {
          emit(MentionState(range: range, error: error.toString()));
        }
      }
    });
  }

  @override
  Future<void> close() {
    _debounce?.cancel();
    _cancel?.cancel();
    return super.close();
  }
}

class MentionSuggestions extends StatelessWidget {
  const MentionSuggestions({
    super.key,
    required this.cubit,
    required this.onPick,
  });
  final MentionCubit cubit;
  final ValueChanged<Entity> onPick;
  @override
  Widget build(BuildContext c) => BlocBuilder<MentionCubit, MentionState>(
    bloc: cubit,
    builder: (c, s) {
      if (s.range == null) return const SizedBox.shrink();
      final scheme = Theme.of(c).colorScheme;
      return Container(
        key: const ValueKey('mention-suggestions'),
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Material(
          color: scheme.surfaceContainer,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: scheme.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: s.range!.query.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: Text('Type a name or handle'),
                )
              : s.loading
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: LinearProgressIndicator(),
                )
              : s.error != null
              ? ListTile(
                  title: const Text('Couldn’t find members'),
                  trailing: IconButton(
                    tooltip: 'Retry member search',
                    onPressed: () => cubit.update(s.range, retry: true),
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                )
              : s.items.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: Text('No members found'),
                )
              : ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    shrinkWrap: true,
                    itemCount: s.items.length,
                    itemBuilder: (c, i) {
                      final member = s.items[i];
                      return ListTile(
                        key: ValueKey('mention-${member.id}'),
                        leading: MemberAvatar(member.data, radius: 18),
                        title: Text(
                          member.text('fullName'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '@${member.text('handle')}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => onPick(member),
                      );
                    },
                  ),
                ),
        ),
      );
    },
  );
}

class ComposerPhotoStrip extends StatelessWidget {
  const ComposerPhotoStrip({
    super.key,
    required this.urls,
    this.onRemove,
    this.busy = false,
  });
  final List<String> urls;
  final ValueChanged<int>? onRemove;
  final bool busy;
  @override
  Widget build(BuildContext c) => SizedBox(
    key: const ValueKey('composer-photo-strip'),
    height: 132,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      itemCount: urls.length,
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (c, index) => SizedBox(
        width: 160,
        child: Stack(
          children: [
            Semantics(
              label: 'Photo ${index + 1} of ${urls.length}',
              image: true,
              child: BrandImage(urls[index], width: 160, height: 120),
            ),
            if (onRemove != null)
              Positioned(
                right: 4,
                top: 4,
                child: IconButton.filled(
                  key: ValueKey('remove-composer-photo-$index'),
                  tooltip: 'Remove photo ${index + 1}',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black54,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: busy ? null : () => onRemove!(index),
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class SocialPostText extends StatefulWidget {
  const SocialPostText({
    super.key,
    required this.text,
    this.mentions = const [],
    this.style,
  });
  final String text;
  final List<Json> mentions;
  final TextStyle? style;
  @override
  State<SocialPostText> createState() => _SocialPostTextState();
}

class _SocialPostTextState extends State<SocialPostText> {
  final links = <TapGestureRecognizer>[];
  void clearLinks() {
    for (final link in links) {
      link.dispose();
    }
    links.clear();
  }

  @override
  void dispose() {
    clearLinks();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    clearLinks();
    final members = {
      for (final m in widget.mentions) '${m['handle']}'.toLowerCase(): m,
    };
    final spans = <InlineSpan>[];
    var offset = 0;
    for (final token in socialTokens.allMatches(widget.text)) {
      spans.add(TextSpan(text: widget.text.substring(offset, token.start)));
      final text = token.group(0)!;
      final member = text.startsWith('@')
          ? members[text.substring(1).toLowerCase()]
          : null;
      TapGestureRecognizer? link;
      if (member != null) {
        link = TapGestureRecognizer()
          ..onTap = () =>
              c.push('/members/${Uri.encodeComponent('${member['handle']}')}');
        links.add(link);
      }
      spans.add(
        TextSpan(
          text: member == null ? text : '${member['fullName'] ?? text}',
          style: TextStyle(
            color: text.startsWith('#') || member != null
                ? Theme.of(c).colorScheme.primary
                : null,
            fontWeight: member != null || text.startsWith('#')
                ? FontWeight.w600
                : null,
          ),
          recognizer: link,
        ),
      );
      offset = token.end;
    }
    spans.add(TextSpan(text: widget.text.substring(offset)));
    return Text.rich(TextSpan(children: spans), style: widget.style);
  }
}

/// Decorative contour lines: quiet around the avatar, denser at the card's edge.
class ProfileCometPattern extends CustomPainter {
  const ProfileCometPattern({required this.color, required this.accent});
  final Color color, accent;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(24)),
    );
    // Keep the constellation away from the avatar and name.
    final stars = <Offset>[
      Offset(size.width * .61, size.height * .13),
      Offset(size.width * .78, size.height * .22),
      Offset(size.width * .94, size.height * .12),
      Offset(size.width * .90, size.height * .52),
      Offset(size.width * .57, size.height * .82),
      Offset(size.width * .73, size.height * .91),
    ];
    for (var i = 0; i < stars.length; i++) {
      final head = stars[i];
      final radius = i.isEven ? 2.8 : 1.8;
      final star = Path()
        ..moveTo(head.dx, head.dy - radius)
        ..quadraticBezierTo(
          head.dx + .5,
          head.dy - .5,
          head.dx + radius,
          head.dy,
        )
        ..quadraticBezierTo(
          head.dx + .5,
          head.dy + .5,
          head.dx,
          head.dy + radius,
        )
        ..quadraticBezierTo(
          head.dx - .5,
          head.dy + .5,
          head.dx - radius,
          head.dy,
        )
        ..quadraticBezierTo(
          head.dx - .5,
          head.dy - .5,
          head.dx,
          head.dy - radius,
        );
      canvas.drawPath(star..close(), Paint()..color = accent);
      if (i == 1 || i == 3 || i == 4) {
        final tail = head + Offset(size.width * .15, -size.height * .24);
        final trail = Path()
          ..moveTo(head.dx - 1, head.dy - 1)
          ..lineTo(tail.dx, tail.dy)
          ..lineTo(head.dx + 1, head.dy + 1)
          ..close();
        canvas.drawPath(
          trail,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.bottomLeft,
              end: Alignment.topRight,
              colors: [accent, accent.withValues(alpha: 0)],
            ).createShader(Rect.fromPoints(head, tail)),
        );
      }
    }
    for (final point in <Offset>[
      Offset(size.width * .68, size.height * .43),
      Offset(size.width * .86, size.height * .77),
      Offset(size.width * .97, size.height * .88),
      Offset(size.width * .83, size.height * .07),
    ]) {
      canvas.drawCircle(point, .7, Paint()..color = color);
    }
    canvas.restore();
  }

  @override
  bool hitTest(Offset position) => false;
  @override
  bool shouldRepaint(covariant ProfileCometPattern oldDelegate) =>
      color != oldDelegate.color || accent != oldDelegate.accent;
}
