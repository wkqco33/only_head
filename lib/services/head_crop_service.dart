import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../models/head_result.dart';
import '../utils/mask_utils.dart';
import '../utils/rect_utils.dart';
import 'face_service.dart';
import 'image_service.dart';
import 'segmentation_service.dart';

Future<ui.Image> _decodeUiImage(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  return frame.image;
}

/// 이미지 파일에서 머리 영역을 감지해 HeadResult를 반환하는 메인 파이프라인.
///
/// 알고리즘:
///   [1] Selfie Segmentation → 전신 mask (머리카락 경계 포함)
///   [2] mask로 배경 제거한 임시 이미지 생성 → face detection 정확도 향상
///   [3] Face Detection → 배경 없는 이미지에서 faceBox (얼굴 위치)
///   [4] faceBox.bottom 기준으로 mask cutoff → 목/어깨 제거
///   [5] cutoff된 mask의 실제 bounding rect → cropRect (머리카락 경계 그대로)
///   [6] mask + cropRect로 투명 PNG 생성 (네이티브)
Future<HeadResult> processHead(File imageFile) async {
  final bytes = await imageFile.readAsBytes();
  final srcImage = await _decodeUiImage(bytes);

  final imgW = srcImage.width.toDouble();
  final imgH = srcImage.height.toDouble();

  // [1] Selfie Segmentation
  final (:mask, :width, :height) = await runSegmentation(imageFile);

  // [2] 배경 제거 이미지 생성 → face detection이 인물에만 집중할 수 있도록 개선
  final maskedBytes = await _buildMaskedImageForDetection(
    srcImage,
    mask,
    width,
    height,
  );
  final maskedFile = await saveImageToTemp(
    maskedBytes,
    'masked_for_detection_${DateTime.now().millisecondsSinceEpoch}.png',
  );

  // [3] Face Detection (배경 제거된 이미지 사용)
  final faceBox = await detectFace(maskedFile);

  // 임시 파일 정리
  try {
    await maskedFile.delete();
  } catch (_) {}

  // [4] faceBox 기준 cutoff 적용
  final trimmedMask = faceBox != null
      ? applyHeadCutoff(
          mask,
          maskWidth: width,
          maskHeight: height,
          cutoffY: faceBox.bottom + faceBox.height * 0.15,
          imageHeight: imgH,
        )
      : mask;

  // [5] cutoff된 mask에서 실제 bounding rect 계산 (머리카락 경계 그대로)
  final cropRect =
      maskBoundingRect(
        trimmedMask,
        maskWidth: width,
        maskHeight: height,
        imageWidth: imgW,
        imageHeight: imgH,
      ) ??
      ui.Rect.fromLTWH(0, 0, imgW, imgH);

  // [6] 투명 PNG 생성 (cutoff mask 사용 - 네이티브 비동기)
  final resultPng = await buildHeadPngAsync(
    srcImage: srcImage,
    mask: trimmedMask,
    maskWidth: width,
    maskHeight: height,
    cropRect: cropRect,
  );

  // [7] 원본 크롭 PNG (restore 브러시용, 알파 없음 - 네이티브 비동기)
  final originalCropped = await _cropOriginalAsync(srcImage, cropRect);

  srcImage.dispose(); // 메모리 확보

  return HeadResult(
    originalPath: imageFile.path,
    resultImage: resultPng,
    originalCroppedBytes: originalCropped,
    maskPixels: trimmedMask,
    cropRect: cropRect,
  );
}

/// Selfie segmentation mask를 원본 이미지에 이진(binary) 적용해
/// 배경이 제거된 PNG를 반환한다.
///
/// face detection이 배경 없이 인물에만 집중할 수 있도록 돕는 전처리 단계.
Future<Uint8List> _buildMaskedImageForDetection(
  ui.Image srcImage,
  List<double> mask,
  int maskWidth,
  int maskHeight, {
  double threshold = 0.5,
}) async {
  // 이진 마스크: 인물 영역은 불투명, 배경은 투명
  final maskBytes = Uint8List(maskWidth * maskHeight * 4);
  for (int i = 0; i < mask.length; i++) {
    final off = i * 4;
    final alpha = mask[i] >= threshold ? 255 : 0;
    maskBytes[off] = 255;
    maskBytes[off + 1] = 255;
    maskBytes[off + 2] = 255;
    maskBytes[off + 3] = alpha;
  }

  final comp = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    maskBytes,
    maskWidth,
    maskHeight,
    ui.PixelFormat.rgba8888,
    comp.complete,
  );
  final maskImage = await comp.future;

  final imgW = srcImage.width;
  final imgH = srcImage.height;
  final imageRect = ui.Rect.fromLTWH(0, 0, imgW.toDouble(), imgH.toDouble());
  final maskRect = ui.Rect.fromLTWH(
    0,
    0,
    maskWidth.toDouble(),
    maskHeight.toDouble(),
  );

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder, imageRect);

  // 원본 이미지 그리기
  canvas.drawImage(srcImage, ui.Offset.zero, ui.Paint());

  // 이진 마스크로 배경 제거 (dstIn: 원본 알파를 마스크 알파로 교체)
  canvas.saveLayer(imageRect, ui.Paint()..blendMode = ui.BlendMode.dstIn);
  canvas.drawImageRect(
    maskImage,
    maskRect,
    imageRect,
    ui.Paint()..filterQuality = ui.FilterQuality.high,
  );
  canvas.restore();

  maskImage.dispose();

  final picture = recorder.endRecording();
  final resultImage = await picture.toImage(imgW, imgH);
  final byteData = await resultImage.toByteData(format: ui.ImageByteFormat.png);

  resultImage.dispose();

  return byteData?.buffer.asUint8List() ?? Uint8List(0);
}

Future<Uint8List> _cropOriginalAsync(ui.Image src, ui.Rect rect) async {
  final cropW = rect.width.round().clamp(1, src.width);
  final cropH = rect.height.round().clamp(1, src.height);

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(
    recorder,
    ui.Rect.fromLTWH(0, 0, cropW.toDouble(), cropH.toDouble()),
  );

  canvas.translate(-rect.left, -rect.top);
  canvas.drawImage(src, ui.Offset.zero, ui.Paint());

  final picture = recorder.endRecording();
  final croppedImage = await picture.toImage(cropW, cropH);
  final byteData = await croppedImage.toByteData(
    format: ui.ImageByteFormat.png,
  );

  croppedImage.dispose();
  return byteData!.buffer.asUint8List();
}
