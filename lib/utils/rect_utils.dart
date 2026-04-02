import 'dart:ui';

/// segmentation mask에서 confidence > threshold 인 픽셀의 bounding rect 계산
Rect? maskBoundingRect(
  List<double> mask, {
  required int maskWidth,
  required int maskHeight,
  double threshold = 0.5,
  required double imageWidth,
  required double imageHeight,
}) {
  int minX = maskWidth, minY = maskHeight, maxX = 0, maxY = 0;
  bool found = false;

  for (int y = 0; y < maskHeight; y++) {
    final rowStart = y * maskWidth;
    for (int x = 0; x < maskWidth; x++) {
      if (mask[rowStart + x] > threshold) {
        if (x < minX) minX = x;
        if (y < minY) minY = y;
        if (x > maxX) maxX = x;
        if (y > maxY) maxY = y;
        found = true;
      }
    }
  }

  if (!found) return null;

  final scaleX = imageWidth / maskWidth;
  final scaleY = imageHeight / maskHeight;

  return Rect.fromLTRB(
    minX * scaleX,
    minY * scaleY,
    maxX * scaleX,
    maxY * scaleY,
  );
}
