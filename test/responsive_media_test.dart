import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twon_mobile/core/responsive_media.dart';
import 'package:twon_mobile/shared/widgets.dart';

/// Task 04: responsive renditions for TWON images; other URLs unchanged.
const owner = '65f0000000000000000000cd';
const uuid = '123e4567-e89b-42d3-a456-426614174000';
const base = 'https://d111.cloudfront.net/images/$owner/$uuid';
const responsive = '${base}_r.webp';
const legacy = '$base.webp';

void main() {
  test('picks the smallest rendition that covers the target width', () {
    expect(responsiveImageUrl(responsive, 132), '${base}_r_w640.webp');
    expect(responsiveImageUrl(responsive, 640), '${base}_r_w640.webp');
    expect(responsiveImageUrl(responsive, 1100), '${base}_r_w1280.webp');
    expect(responsiveImageUrl(responsive, 2400), responsive);
    expect(responsiveImageUrl(responsive, double.infinity), responsive);
    expect(responsiveImageUrl(responsive, 0), responsive);
  });

  test('leaves non-responsive URLs unchanged', () {
    for (final url in [
      legacy,
      '${base}_thumb.webp',
      '${base}_r_w640.webp',
      '$base.gif',
      '$responsive?x=1',
      'https://media.giphy.com/media/abc/giphy.gif',
      'https://d111.cloudfront.net/videos/$owner/${uuid}_r.webp',
    ]) {
      expect(responsiveImageUrl(url, 300), url, reason: url);
    }
  });

  Future<String> requested(
    WidgetTester tester,
    Widget image, {
    double screen = 400,
    double dpr = 2,
  }) async {
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: Size(screen, 800), devicePixelRatio: dpr),
        child: MaterialApp(home: Scaffold(body: image)),
      ),
    );
    return tester
        .widget<CachedNetworkImage>(find.byType(CachedNetworkImage))
        .imageUrl;
  }

  testWidgets('BrandImage requests a variant sized for its display width', (
    tester,
  ) async {
    // Full-width feed image: 400 logical px × 2 = 800 px → the 1280 rendition.
    expect(
      await requested(tester, const BrandImage(responsive)),
      '${base}_r_w1280.webp',
    );
    // A 44 px avatar at 3x = 132 px → the 640 rendition.
    expect(
      await requested(
        tester,
        const BrandImage(responsive, width: 44, height: 44),
        dpr: 3,
      ),
      '${base}_r_w640.webp',
    );
    // A wide tablet at 3x needs more than 1280 px → the main image.
    expect(
      await requested(
        tester,
        const BrandImage(responsive),
        screen: 900,
        dpr: 3,
      ),
      responsive,
    );
  });

  testWidgets('BrandImage keeps older and external URLs exactly as before', (
    tester,
  ) async {
    expect(await requested(tester, const BrandImage(legacy)), legacy);
    expect(
      await requested(tester, const BrandImage('https://example.com/a.jpg')),
      'https://example.com/a.jpg',
    );
  });
}
