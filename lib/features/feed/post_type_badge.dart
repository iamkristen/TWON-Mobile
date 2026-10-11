import 'package:flutter/material.dart';

String postTypeDisplayLabel(String type) => switch (type) {
  'general' => 'General Howl',
  'housing' => 'Housing',
  'visa' => 'Visa',
  'fraud' => 'Fraud Alert',
  'scam' => 'Scam Alert',
  'help' => 'Help / SOS',
  _ => type,
};

// Same category tokens and opacity as WebApp postTypeBadgeClass, converted to sRGB.
class PostTypeBadge extends StatelessWidget {
  const PostTypeBadge(this.type, {super.key});
  final String type;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final (background, foreground, border) = switch (type) {
      'general' => dark ? (Color(0xFF45556C).withValues(alpha: .4), Color(0xFFF1F5F9), Colors.white.withValues(alpha: .15)) : (Color(0xFFE2E8F0).withValues(alpha: .95), Color(0xFF1D293D), Color(0xFFCAD5E2).withValues(alpha: .8)),
      'housing' => dark ? (Color(0xFF00BC7D).withValues(alpha: .2), Color(0xFFD0FAE5), Color(0xFF00D492).withValues(alpha: .25)) : (Color(0xFFD0FAE5), Color(0xFF002C22), Color(0xFFA4F4CF).withValues(alpha: .9)),
      'visa' => dark ? (Color(0xFF615FFF).withValues(alpha: .2), Color(0xFFE0E7FF), Color(0xFFA3B3FF).withValues(alpha: .3)) : (Color(0xFFE0E7FF), Color(0xFF1E1A4D), Color(0xFFC6D2FF).withValues(alpha: .9)),
      'fraud' => dark ? (Color(0xFFFE9A00).withValues(alpha: .2), Color(0xFFFEF3C6), Color(0xFFFFD230).withValues(alpha: .25)) : (Color(0xFFFEF3C6), Color(0xFF461901), Color(0xFFFEE685).withValues(alpha: .9)),
      'scam' => dark ? (Color(0xFFFF2056).withValues(alpha: .25), Color(0xFFFFE4E6), Color(0xFFFFA1AD).withValues(alpha: .3)) : (Color(0xFFFFE4E6), Color(0xFF4D0218), Color(0xFFFFCCD3).withValues(alpha: .9)),
      'help' => dark ? (Color(0xFF8E51FF).withValues(alpha: .2), Color(0xFFEDE9FE), Color(0xFFC4B4FF).withValues(alpha: .25)) : (Color(0xFFEDE9FE), Color(0xFF2F0D68), Color(0xFFDDD6FF).withValues(alpha: .9)),
      _ => (Theme.of(context).colorScheme.primary.withValues(alpha: .1), Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.primary.withValues(alpha: .2)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(6), border: Border.all(color: border)),
      child: Text(postTypeDisplayLabel(type), style: TextStyle(color: foreground, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: .25)),
    );
  }
}
