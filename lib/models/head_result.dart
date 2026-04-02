import 'dart:typed_data';
import 'dart:ui';

class HeadResult {
  final String originalPath;
  final Uint8List resultImage;        // 투명 PNG (머리 영역만)
  final Uint8List originalCroppedBytes; // 불투명 원본 크롭 PNG (restore 브러시용)
  final List<double> maskPixels;      // segmentation 마스크 (0.0~1.0)
  final Rect cropRect;                // 이미지 내 머리 영역

  const HeadResult({
    required this.originalPath,
    required this.resultImage,
    required this.originalCroppedBytes,
    required this.maskPixels,
    required this.cropRect,
  });
}
