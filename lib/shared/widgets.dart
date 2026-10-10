import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import '../core/api.dart';
import '../core/models.dart';
import '../core/collection_cubit.dart';

AppRepository repository(BuildContext context) => context.read<AppRepository>();
String dateLabel(String value) {
  final d = DateTime.tryParse(value);
  return d == null ? value : DateFormat.yMMMd().format(d.toLocal());
}

String money(int amount, String currency) => NumberFormat.simpleCurrency(
  name: currency.toUpperCase(),
).format(amount / 100);
Future<void> openUrl(String value) async {
  final uri = Uri.tryParse(value);
  if (uri == null || !['http', 'https'].contains(uri.scheme)) {
    throw const AppFailure('This link is unavailable.');
  }
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    throw const AppFailure('Could not open this link.');
  }
}

void notice(BuildContext context, String message) => ScaffoldMessenger.of(
  context,
).showSnackBar(SnackBar(content: Text(message)));
Future<bool> confirm(BuildContext context, String title, String message) =>
    showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    ).then((value) => value ?? false);

class BrandImage extends StatelessWidget {
  const BrandImage(
    this.url, {
    super.key,
    this.height = 190,
    this.width,
    this.fit = BoxFit.cover,
  });
  final String url;
  final double height;
  final double? width;
  final BoxFit fit;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(16),
    child: url.isEmpty
        ? Container(
            height: height,
            width: width,
            color: Theme.of(context).colorScheme.surfaceContainer,
            child: const Icon(Icons.landscape_outlined, size: 40),
          )
        : CachedNetworkImage(
            imageUrl: url,
            height: height,
            width: width,
            fit: fit,
            placeholder: (_, _) => SizedBox(
              height: height,
              child: const Center(child: CircularProgressIndicator()),
            ),
            errorWidget: (_, _, _) => SizedBox(
              height: height,
              child: const Center(child: Icon(Icons.broken_image_outlined)),
            ),
          ),
  );
}

class MemberAvatar extends StatelessWidget {
  const MemberAvatar(this.person, {super.key, this.radius = 22});
  final Json person;
  final double radius;
  @override
  Widget build(BuildContext context) {
    final url = person['avatar']?.toString() ?? '';
    final name =
        person['fullName']?.toString() ??
        person['handle']?.toString() ??
        'Pack';
    return CircleAvatar(
      radius: radius,
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      child: url.isEmpty
          ? Text(name.isEmpty ? 'P' : name.substring(0, 1).toUpperCase())
          : ClipOval(
              child: BrandImage(url, height: radius * 2, width: radius * 2),
            ),
    );
  }
}

class ErrorPanel extends StatelessWidget {
  const ErrorPanel(this.message, {super.key, this.retry});
  final String message;
  final VoidCallback? retry;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.cloud_off_outlined, size: 40),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center),
        if (retry != null)
          TextButton(onPressed: retry, child: const Text('Try again')),
      ],
    ),
  );
}

class CollectionView extends StatelessWidget {
  const CollectionView({
    super.key,
    required this.path,
    required this.builder,
    this.query = const {},
    this.header,
    this.empty = 'Nothing here yet.',
    this.reverse = false,
    this.emptyAsset,
  });
  final String path, empty;
  final Json query;
  final Widget Function(BuildContext, Entity, VoidCallback) builder;
  final Widget? header;
  final bool reverse;
  final String? emptyAsset;
  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (c) => CollectionCubit(repository(c), path, query: query)..load(),
    child: BlocBuilder<CollectionCubit, CollectionState>(
      builder: (c, state) {
        final cubit = c.read<CollectionCubit>();
        return RefreshIndicator(
          onRefresh: () => cubit.load(),
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.all(16),
            physics: const AlwaysScrollableScrollPhysics(),
            reverse: reverse,
            children: [
              ?header,
              if (state.loading)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (state.error != null)
                ErrorPanel(state.error!, retry: () => cubit.load()),
              if (!state.loading && state.loaded && state.items.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: emptyAsset == null
                      ? Text(empty, textAlign: TextAlign.center)
                      : BrandEmptyState(
                          asset: emptyAsset!,
                          title: empty,
                          message: '',
                        ),
                ),
              ...state.items.map(
                (e) => SubtleEntry(
                  key: ValueKey(e.id),
                  child: builder(c, e, () => cubit.load()),
                ),
              ),
              if (state.cursor != null)
                OutlinedButton(
                  onPressed: state.loadingMore
                      ? null
                      : () => cubit.load(more: true),
                  child: Text(state.loadingMore ? 'Loading…' : 'Load more'),
                ),
            ],
          ),
        );
      },
    ),
  );
}

class DetailView extends StatelessWidget {
  const DetailView({super.key, required this.path, required this.builder});
  final String path;
  final Widget Function(BuildContext, Entity, VoidCallback) builder;
  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (c) => DetailCubit(repository(c), path)..load(),
    child: BlocBuilder<DetailCubit, DetailState>(
      builder: (c, state) {
        Future<void> refresh() => c.read<DetailCubit>().load();
        if (state.item == null) {
          return state.loading
              ? const Center(child: CircularProgressIndicator())
              : ErrorPanel(state.error ?? 'Not found.', retry: refresh);
        }
        return RefreshIndicator(
          onRefresh: refresh,
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.all(16),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              if (state.error != null) ErrorPanel(state.error!, retry: refresh),
              builder(c, state.item!, refresh),
            ],
          ),
        );
      },
    ),
  );
}

class ActionButton extends StatelessWidget {
  const ActionButton({
    super.key,
    required this.label,
    required this.action,
    this.onSuccess,
    this.icon,
    this.confirmation,
    this.enabled = true,
    this.tonal = false,
  });
  final String label;
  final Future<dynamic> Function() action;
  final void Function(dynamic)? onSuccess;
  final IconData? icon;
  final String? confirmation;
  final bool enabled, tonal;
  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => MutationCubit(),
    child: BlocConsumer<MutationCubit, MutationState>(
      listener: (c, s) {
        if (s.error != null) notice(c, s.error!);
        if (s.success) onSuccess?.call(s.result);
      },
      builder: (c, s) {
        Future<void> run() async {
          if (confirmation != null && !await confirm(c, label, confirmation!)) {
            return;
          }
          if (!c.mounted) return;
          await c.read<MutationCubit>().run(action);
        }

        final content = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (s.busy)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (icon != null)
              Icon(icon, size: 18),
            if (s.busy || icon != null) const SizedBox(width: 8),
            Flexible(child: Text(label)),
          ],
        );
        return tonal
            ? FilledButton.tonal(
                onPressed: enabled && !s.busy ? run : null,
                child: content,
              )
            : FilledButton(
                onPressed: enabled && !s.busy ? run : null,
                child: content,
              );
      },
    ),
  );
}

class PageHeading extends StatelessWidget {
  const PageHeading(this.title, this.description, {super.key});
  final String title, description;
  @override
  Widget build(BuildContext c) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(c).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -.5,
          ),
        ),
        if (description.isNotEmpty) const SizedBox(height: 6),
        if (description.isNotEmpty)
          Text(
            description,
            style: Theme.of(c).textTheme.bodyMedium?.copyWith(
              color: Theme.of(c).colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    ),
  );
}

class SubtleEntry extends StatelessWidget {
  const SubtleEntry({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext c) => MediaQuery.of(c).disableAnimations
      ? child
      : child
            .animate()
            .fadeIn(duration: 180.ms)
            .moveY(begin: 5, end: 0, duration: 180.ms);
}

class ResourcePanel extends StatelessWidget {
  const ResourcePanel({
    super.key,
    required this.path,
    required this.builder,
    this.compact = false,
  });
  final bool compact;
  final String path;
  final Widget Function(BuildContext, Entity, VoidCallback) builder;
  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (c) => DetailCubit(repository(c), path)..load(),
    child: BlocBuilder<DetailCubit, DetailState>(
      builder: (c, s) {
        if (s.item == null) {
          if (compact) {
            return s.loading
                ? const SizedBox(
                    width: 48,
                    height: 48,
                    child: Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                : IconButton(
                    tooltip: 'Retry gathering permissions',
                    onPressed: () => c.read<DetailCubit>().load(),
                    icon: const Icon(Icons.cloud_off_outlined),
                  );
          }

          return s.loading
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              : ErrorPanel(
                  s.error ?? 'Unavailable.',
                  retry: () => c.read<DetailCubit>().load(),
                );
        }
        return builder(c, s.item!, () => c.read<DetailCubit>().load());
      },
    ),
  );
}

class BrandWordmark extends StatelessWidget {
  const BrandWordmark({super.key, this.width = 112});
  final double width;
  @override
  Widget build(BuildContext c) => SvgPicture.asset(
    'assets/branding/navbar-logo${Theme.of(c).brightness == Brightness.dark ? '-dark' : ''}.svg',
    width: width,
    height: width * .34,
    semanticsLabel: 'The Wolves of Nepal',
    fit: BoxFit.contain,
  );
}

class BrandEmptyState extends StatelessWidget {
  const BrandEmptyState({
    super.key,
    required this.asset,
    required this.title,
    required this.message,
    this.action,
  });
  final String asset, title, message;
  final Widget? action;
  @override
  Widget build(BuildContext c) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.asset(
            'assets/illustrations/$asset.svg',
            height: 160,
            semanticsLabel: title,
          ),
          const SizedBox(height: 20),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(
              c,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (message.isNotEmpty) const SizedBox(height: 8),
          if (message.isNotEmpty)
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(c).colorScheme.onSurfaceVariant),
            ),
          if (action != null) ...[const SizedBox(height: 12), action!],
        ],
      ),
    ),
  );
}

class SwipeReply extends StatefulWidget {
  const SwipeReply({
    super.key,
    required this.child,
    required this.onReply,
    this.enabled = true,
  });
  final Widget child;
  final VoidCallback onReply;
  final bool enabled;
  @override
  State<SwipeReply> createState() => _SwipeReplyState();
}

class _SwipeReplyState extends State<SwipeReply> {
  double distance = 0;
  bool dragging = false;
  void finish({bool cancelled = false}) {
    if (!cancelled && distance >= 56) {
      HapticFeedback.selectionClick();
      widget.onReply();
    }
    setState(() {
      distance = 0;
      dragging = false;
    });
  }

  @override
  Widget build(BuildContext c) => Semantics(
    customSemanticsActions: widget.enabled
        ? {const CustomSemanticsAction(label: 'Reply'): widget.onReply}
        : null,
    child: GestureDetector(
      onHorizontalDragStart: widget.enabled
          ? (_) => setState(() => dragging = true)
          : null,
      onHorizontalDragUpdate: widget.enabled
          ? (d) =>
                setState(() => distance = (distance + d.delta.dx).clamp(0, 80))
          : null,
      onHorizontalDragEnd: widget.enabled ? (_) => finish() : null,
      onHorizontalDragCancel: widget.enabled
          ? () => finish(cancelled: true)
          : null,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          if (distance > 4)
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Icon(
                Icons.reply_rounded,
                color: distance >= 56
                    ? Theme.of(c).colorScheme.primary
                    : Theme.of(c).colorScheme.onSurfaceVariant,
              ),
            ),
          AnimatedContainer(
            duration: dragging || MediaQuery.disableAnimationsOf(c)
                ? Duration.zero
                : const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            transform: Matrix4.translationValues(distance, 0, 0),
            child: widget.child,
          ),
        ],
      ),
    ),
  );
}

class WolfLandscape extends StatelessWidget {
  const WolfLandscape({super.key});
  @override
  Widget build(BuildContext c) => ClipRRect(
    borderRadius: BorderRadius.circular(24),
    child: DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xff334564), Color(0xff19263f), Color(0xff352c4e)],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _TerritoryPainter())),
          Positioned(
            right: 8,
            bottom: -10,
            child: ExcludeSemantics(
              child: SvgPicture.asset(
                'assets/illustrations/no-clan-found.svg',
                width: 185,
                height: 185,
              ),
            ),
          ),
          const Positioned(
            left: 20,
            top: 20,
            child: Icon(
              Icons.nightlight_round,
              color: Color(0xffffc6d1),
              size: 24,
            ),
          ),
        ],
      ),
    ),
  );
}

class _TerritoryPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xff7c8fac).withValues(alpha: .18);
    final back = Path()
      ..moveTo(0, size.height * .86)
      ..lineTo(size.width * .28, size.height * .34)
      ..lineTo(size.width * .48, size.height * .74)
      ..lineTo(size.width * .68, size.height * .42)
      ..lineTo(size.width, size.height * .86)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(back, paint);
    paint.color = const Color(0xff0c172d).withValues(alpha: .45);
    final front = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width * .16, size.height * .70)
      ..lineTo(size.width * .36, size.height * .91)
      ..lineTo(size.width * .57, size.height * .58)
      ..lineTo(size.width * .88, size.height)
      ..close();
    canvas.drawPath(front, paint);
    paint.color = const Color(0xffe9efff).withValues(alpha: .45);
    for (final point in [
      const Offset(.23, .15),
      const Offset(.4, .26),
      const Offset(.58, .12),
      const Offset(.79, .24),
    ]) {
      canvas.drawCircle(
        Offset(point.dx * size.width, point.dy * size.height),
        1.3,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TerritoryPainter oldDelegate) => false;
}
