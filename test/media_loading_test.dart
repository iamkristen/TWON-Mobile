import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twon_mobile/core/responsive_media.dart';
import 'package:twon_mobile/shared/widgets.dart';

/// Task 14: non-image media is never downloaded inline; images decode near
/// their displayed size; decoded-image memory is bounded.
const video =
    'https://d111.cloudfront.net/videos/65f0000000000000000000cd/123e4567-e89b-42d3-a456-426614174000.mp4';
const image =
    'https://d111.cloudfront.net/images/65f0000000000000000000cd/123e4567-e89b-42d3-a456-426614174000.webp';

Future<void> show(
  WidgetTester tester,
  Widget child, {
  double screen = 400,
  double dpr = 2,
}) => tester.pumpWidget(
  MediaQuery(
    data: MediaQueryData(size: Size(screen, 800), devicePixelRatio: dpr),
    child: MaterialApp(home: Scaffold(body: child)),
  ),
);

void main() {
  test('recognises non-image media by path', () {
    expect(isNonImageMedia(video), isTrue);
    expect(isNonImageMedia('https://x.test/files/a/report.PDF'), isTrue);
    expect(isNonImageMedia('$video?token=1'), isTrue);
    expect(isNonImageMedia(image), isFalse);
  });

  test('decode width follows the display size, bounded by the stored size', () {
    expect(decodeWidth(400, 2, cover: false), 800);
    expect(decodeWidth(400, 2), 1200);
    expect(decodeWidth(1200, 3), 2048);
    expect(decodeWidth(double.infinity, 2), isNull);
    expect(
      imageCacheMaxBytes,
      lessThan(100 << 20),
    ); // below Flutter's 100 MB default
  });

  testWidgets('a video in a post is a tile, not an image download', (
    tester,
  ) async {
    await show(tester, const BrandImage(video));
    expect(find.byType(CachedNetworkImage), findsNothing);
    expect(find.text('Play video'), findsOneWidget);
    expect(find.bySemanticsLabel('Play video'), findsOneWidget);
  });

  testWidgets('images decode near their displayed size', (tester) async {
    await show(tester, const BrandImage(image, width: 44, height: 44), dpr: 3);
    final widget = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    );
    expect(widget.memCacheWidth, 198); // 44 × 3 × 1.5, not 2048
  });
}
