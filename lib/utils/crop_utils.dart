import 'dart:typed_data';
import 'dart:ui';

/// RGBA bytes에서 alpha > alphaThreshold 인 픽셀의 bounding rect를 반환한다.
/// compute()로 isolate에서 실행 가능하도록 top-level 함수로 정의.
Rect calcOpaqueBounds(
    ({Uint8List bytes, int width, int height}) params) {
  final bytes = params.bytes;
  final w = params.width;
  final h = params.height;
  const alphaThreshold = 10;

  int minY = -1;
  int maxY = -1;
  int minX = -1;
  int maxX = -1;

  // Top-down search for minY
  for (int y = 0; y < h; y++) {
    final rowOff = y * w * 4;
    for (int x = 0; x < w; x++) {
      if (bytes[rowOff + x * 4 + 3] > alphaThreshold) {
        minY = y;
        break;
      }
    }
    if (minY != -1) break;
  }

  // 완전 투명한 경우
  if (minY == -1) {
    return Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble());
  }

  // Bottom-up search for maxY
  for (int y = h - 1; y >= minY; y--) {
    final rowOff = y * w * 4;
    for (int x = 0; x < w; x++) {
      if (bytes[rowOff + x * 4 + 3] > alphaThreshold) {
        maxY = y;
        break;
      }
    }
    if (maxY != -1) break;
  }

  // Left-right search for minX
  for (int x = 0; x < w; x++) {
    for (int y = minY; y <= maxY; y++) {
      if (bytes[(y * w + x) * 4 + 3] > alphaThreshold) {
        minX = x;
        break;
      }
    }
    if (minX != -1) break;
  }

  // Right-left search for maxX
  for (int x = w - 1; x >= minX; x--) {
    for (int y = minY; y <= maxY; y++) {
      if (bytes[(y * w + x) * 4 + 3] > alphaThreshold) {
        maxX = x;
        break;
      }
    }
    if (maxX != -1) break;
  }

  const pad = 2;
  return Rect.fromLTRB(
    (minX - pad).clamp(0, w).toDouble(),
    (minY - pad).clamp(0, h).toDouble(),
    (maxX + 1 + pad).clamp(0, w).toDouble(),
    (maxY + 1 + pad).clamp(0, h).toDouble(),
  );
}
