import 'package:flutter/material.dart';
import '../core/theme.dart';

/// Branded loading: the TWON mark inside a soft moonlight pulse. For screen
/// and route loading only; static when the platform asks for reduced motion.
class MoonPulseLoader extends StatefulWidget {
  const MoonPulseLoader({
    super.key,
    this.label = 'Loading',
    this.size = 64,
    this.onDark,
  });
  final String label;
  final double size;

  /// Forces the dark (navy) treatment, e.g. on the always-dark splash.
  final bool? onDark;
  @override
  State<MoonPulseLoader> createState() => _MoonPulseLoaderState();
}

class _MoonPulseLoaderState extends State<MoonPulseLoader>
    with SingleTickerProviderStateMixin {
  late final controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.disableAnimationsOf(context);
    if (still) {
      controller
        ..stop()
        ..value = .5;
    } else if (!controller.isAnimating) {
      controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final dark = widget.onDark ?? Theme.of(c).brightness == Brightness.dark;
    final size = widget.size;
    return Semantics(
      label: '${widget.label}…',
      liveRegion: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                AnimatedBuilder(
                  animation: controller,
                  builder: (_, _) {
                    final t = Curves.easeInOut.transform(controller.value);
                    return Transform.scale(
                      scale: .92 + t * .16,
                      child: Opacity(
                        opacity: .45 + t * .45,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                TwonPalette.moonBlue.withValues(alpha: .35),
                                TwonPalette.moonBlue.withValues(alpha: 0),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                Container(
                  width: size * .72,
                  height: size * .72,
                  padding: EdgeInsets.all(size * .14),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    // Always navy: the mark's white lettering needs a dark disc.
                    color: TwonPalette.navy.withValues(alpha: dark ? .9 : 1),
                    border: Border.all(
                      color: TwonPalette.moonBlue.withValues(alpha: .3),
                    ),
                  ),
                  child: Image.asset(
                    'assets/branding/logo.png',
                    excludeFromSemantics: true,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          ExcludeSemantics(
            child: Text(
              '${widget.label}…',
              style: Theme.of(c).textTheme.labelLarge?.copyWith(
                color: dark && widget.onDark == true
                    ? TwonPalette.moonlight.withValues(alpha: .8)
                    : Theme.of(c).colorScheme.onSurfaceVariant,
                letterSpacing: .4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Splash / logo reveal while the session is restored: the mark rises out of
/// the dark with a moonlight pulse behind it, then the wordmark fades in.
class TwonSplash extends StatelessWidget {
  const TwonSplash({super.key});
  @override
  Widget build(BuildContext c) {
    final still = MediaQuery.disableAnimationsOf(c);
    return Scaffold(
      backgroundColor: TwonPalette.midnight,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -.2),
            radius: 1.1,
            colors: [Color(0xff123158), TwonPalette.midnight],
          ),
        ),
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: still ? 1 : 0, end: 1),
            duration: still ? Duration.zero : const Duration(milliseconds: 700),
            curve: TwonMotion.curve,
            builder: (_, t, child) => Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset(0, 12 * (1 - t)),
                child: Transform.scale(scale: .94 + .06 * t, child: child),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const MoonPulseLoader(
                  label: 'Finding your pack',
                  size: 120,
                  onDark: true,
                ),
                const SizedBox(height: 10),
                Text(
                  'THE WOLVES OF NEPAL',
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    letterSpacing: 3.2,
                    color: TwonPalette.moonlight,
                  ),
                  semanticsLabel: 'The Wolves of Nepal',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One-time "stealth" entrance (fade and rise) for panels and lists.
class StealthEntrance extends StatelessWidget {
  const StealthEntrance({
    super.key,
    required this.child,
    this.delay = Duration.zero,
  });
  final Widget child;
  final Duration delay;
  @override
  Widget build(BuildContext c) {
    if (MediaQuery.disableAnimationsOf(c)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: TwonMotion.slow + delay,
      curve: Interval(
        delay.inMilliseconds / (TwonMotion.slow + delay).inMilliseconds,
        1,
        curve: TwonMotion.curve,
      ),
      builder: (_, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 8 * (1 - t)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}
