/// Task 04: responsive TWON images. A main image whose responsive set exists is
/// stored as `images/<owner>/<uuid>_r.webp`, with WebP variants
/// `<uuid>_r_w640.webp` and `<uuid>_r_w1280.webp` (the main image is at most
/// 2048 px). Other URLs (older uploads, GIFs, external images) are unchanged.
const responsiveWidths = [640, 1280];

final _responsiveMain = RegExp(
  r'^(https?://[^?#]+/images/[0-9a-f]{24}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})_r\.webp$',
);

/// The smallest rendition at least [targetPixels] wide (the main image above
/// the largest variant); [url] itself when it has no responsive set.
String responsiveImageUrl(String url, double targetPixels) {
  final base = _responsiveMain.firstMatch(url)?.group(1);
  if (base == null || !targetPixels.isFinite || targetPixels <= 0) return url;
  for (final width in responsiveWidths) {
    if (targetPixels <= width) return '${base}_r_w$width.webp';
  }
  return url;
}

/// Task 14: URLs that are not images (video, audio, documents). Showing them
/// through an image widget would download the whole file just to fail decoding.
final _nonImage = RegExp(
  r'\.(mp4|mov|webm|m4a|aac|mp3|pdf|docx?|xlsx?|pptx?|zip|rar|txt|csv)$',
  caseSensitive: false,
);

bool isNonImageMedia(String url) {
  final path = Uri.tryParse(url)?.path ?? url;
  return _nonImage.hasMatch(path);
}

/// Decode width for an image shown [logicalWidth] wide (Task 14): about the
/// displayed size, a margin for `BoxFit.cover` cropping, never above the
/// 2048 px the server stores. Null when the width is unknown.
int? decodeWidth(double logicalWidth, double devicePixelRatio, {bool cover = true}) {
  if (!logicalWidth.isFinite || logicalWidth <= 0) return null;
  final pixels = logicalWidth * devicePixelRatio * (cover ? 1.5 : 1.0);
  return pixels.round().clamp(1, 2048);
}

/// Task 14: bound decoded-image memory app-wide (defaults: 1000 images, 100 MB).
const imageCacheMaxImages = 300;
const imageCacheMaxBytes = 64 << 20;
