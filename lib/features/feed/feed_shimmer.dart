import 'package:flutter/material.dart';

/// Animates only the placeholder shapes, leaving the card surface unchanged.
class FeedShimmer extends StatefulWidget {
  const FeedShimmer({super.key, required this.child});
  final Widget child;
  @override
  State<FeedShimmer> createState() => _FeedShimmerState();
}

class _FeedShimmerState extends State<FeedShimmer> with SingleTickerProviderStateMixin {
  late final controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) || !TickerMode.of(context)) {
      controller.stop();
    } else if (!controller.isAnimating) {
      controller.repeat();
    }
  }
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    final scheme = Theme.of(context).colorScheme;
    final base = scheme.surfaceContainerHighest;
    final highlight = Color.lerp(base, scheme.onSurface, .12)!;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: controller,
        child: widget.child,
        builder: (context, child) => ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment(-3 + controller.value * 6, -.3),
            end: Alignment(-1 + controller.value * 6, .3),
            colors: [base, highlight, base],
            stops: const [0, .5, 1],
          ).createShader(bounds),
          child: child,
        ),
      ),
    );
  }
}
