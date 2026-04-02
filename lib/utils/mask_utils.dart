import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

/// segmentation mask와 cropRect를 적용해 투명 PNG를 비동기 네이티브 처리로 생성한다.
///
/// 안티앨리어싱 파이프라인:
///   [1] List`<`double`>` 마스크를 RGBA 스케일 바이트배열로 즉시 변환
///   [2] 네이티브 함수인 `decodeImageFromPixels`를 통해 알파 마스크 GPU 텍스처로 로드
///   [3] `ui.Canvas`의 `BlendMode.dstIn` 블렌딩과 `ImageFilter.blur` 필터로 초고속 합성
Future<Uint8List> buildHeadPngAsync({
  required ui.Image srcImage,
  required List<double> mask,
  required int maskWidth,
  required int maskHeight,
  required ui.Rect cropRect,
  double threshold = 0.5,
  double blurSigma = 4.0, // 부드러운 경계를 위한 캔버스 블러 시그마
}) async {
  // [1] 배열 기반 마스크를 RGBA Uint8List 텍스처로 변환 (알파에 마스크 강도 기록)
  final bytes = Uint8List(maskWidth * maskHeight * 4);
  for (int i = 0; i < mask.length; i++) {
    final val = mask[i];
    final alpha = (val * 255).clamp(0, 255).toInt();
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

  final maskPaint = ui.Paint()
    ..isAntiAlias = true
    ..filterQuality = ui.FilterQuality.high;

  // 원본의 smoothstep 대신 캔버스 수준 가우시안 블러 사용으로 속도 타협점 확보
  if (blurSigma > 0) {
    maskPaint.imageFilter = ui.ImageFilter.blur(
      sigmaX: blurSigma,
      sigmaY: blurSigma,
    );
  }

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
