import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

/// segmentation mask와 cropRect를 적용해 투명 PNG를 비동기 네이티브 처리로 생성한다.
///
/// 이진(binary) 마스크 파이프라인:
///   [1] List`<`double`>` 마스크를 이진 RGBA Uint8List 텍스처로 변환 (threshold 이상 → 불투명, 미만 → 완전 투명)
///   [2] 네이티브 함수인 `decodeImageFromPixels`를 통해 알파 마스크 GPU 텍스처로 로드
///   [3] `ui.Canvas`의 `BlendMode.dstIn` 블렌딩으로 배경을 타이트하게 제거 (블러 없음)
Future<Uint8List> buildHeadPngAsync({
  required ui.Image srcImage,
  required List<double> mask,
  required int maskWidth,
  required int maskHeight,
  required ui.Rect cropRect,
  double threshold = 0.5, // 이 값 이상이면 완전 불투명(255), 미만이면 완전 투명(0)
}) async {
  // [1] 배열 기반 마스크를 이진 RGBA Uint8List 텍스처로 변환 (threshold 기준 hard cutoff)
  final bytes = Uint8List(maskWidth * maskHeight * 4);
  for (int i = 0; i < mask.length; i++) {
    final alpha = mask[i] >= threshold ? 255 : 0;
    final off = i * 4;
    bytes[off] = 255;
    bytes[off + 1] = 255;
    bytes[off + 2] = 255;
    bytes[off + 3] = alpha;
  }

  // [2] 네이티브 GPU Image. 알파 채널이 적용됨.
  final comp = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    bytes,
    maskWidth,
    maskHeight,
    ui.PixelFormat.rgba8888,
    comp.complete,
  );
  final maskImage = await comp.future;

  // [3] Canvas 기반 하드웨어 가속 블렌딩 (크롭)
  final cropW = cropRect.width.round();
  final cropH = cropRect.height.round();
  if (cropW <= 0 || cropH <= 0) return Uint8List(0);

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(
    recorder,
    ui.Rect.fromLTWH(0, 0, cropW.toDouble(), cropH.toDouble()),
  );

  // 크롭 위치인 왼쪽 상단을 원점으로 조정
  canvas.translate(-cropRect.left, -cropRect.top);

  // 원본 이미지 그리기
  canvas.drawImage(srcImage, ui.Offset.zero, ui.Paint());

  // 기존 픽셀들에 대해 dstIn 블렌드 모드로 마스크 강제 교차
  final dstRect = ui.Rect.fromLTWH(
    0,
    0,
    srcImage.width.toDouble(),
    srcImage.height.toDouble(),
  );
  final maskRect = ui.Rect.fromLTWH(
    0,
    0,
    maskWidth.toDouble(),
    maskHeight.toDouble(),
  );

  canvas.saveLayer(dstRect, ui.Paint()..blendMode = ui.BlendMode.dstIn);

  // 블러 없이 이진 마스크를 그대로 적용해 배경을 타이트하게 제거
  final maskPaint = ui.Paint()
    ..isAntiAlias = false
    ..filterQuality = ui.FilterQuality.none;

  canvas.drawImageRect(maskImage, maskRect, dstRect, maskPaint);
  canvas.restore();

  // [4] 추출 후 메모리 수거
  final picture = recorder.endRecording();
  final resultCanvasImage = await picture.toImage(cropW, cropH);
  final byteData = await resultCanvasImage.toByteData(
    format: ui.ImageByteFormat.png,
  );

  maskImage.dispose();
  resultCanvasImage.dispose();

  return byteData!.buffer.asUint8List();
}

/// mask에서 이미지 좌표 기준 cutoffY 이하 픽셀을 0으로 설정한다.
List<double> applyHeadCutoff(
  List<double> mask, {
  required int maskWidth,
  required int maskHeight,
  required double cutoffY,
  required double imageHeight,
}) {
  final cutoffMaskY = (cutoffY / imageHeight * maskHeight).round().clamp(
    0,
    maskHeight,
  );
  if (cutoffMaskY >= maskHeight) return mask;

  final result = List<double>.from(mask);
  for (int my = cutoffMaskY; my < maskHeight; my++) {
    final rowStart = my * maskWidth;
    for (int mx = 0; mx < maskWidth; mx++) {
      result[rowStart + mx] = 0.0;
    }
  }
  return result;
}
