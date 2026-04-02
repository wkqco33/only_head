import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../models/head_result.dart';
import '../utils/mask_utils.dart';
import '../utils/rect_utils.dart';
import 'face_service.dart';
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
///   [2] Face Detection → faceBox (얼굴 위치)
///   [3] faceBox.bottom 기준으로 mask cutoff → 목/어깨 제거
///   [4] cutoff된 mask의 실제 bounding rect → cropRect (머리카락 경계 그대로)
///   [5] mask + cropRect로 투명 PNG 생성 (네이티브)
Future<HeadResult> processHead(File imageFile) async {
  final bytes = await imageFile.readAsBytes();
  final srcImage = await _decodeUiImage(bytes);

  final imgW = srcImage.width.toDouble();
  final imgH = srcImage.height.toDouble();

  // [1] Selfie Segmentation
  final (:mask, :width, :height) = await runSegmentation(imageFile);

  // [2] Face Detection
  final faceBox = await detectFace(imageFile);

  // [3] faceBox 기준 cutoff 적용
  final trimmedMask = faceBox != null
      ? applyHeadCutoff(
          mask,
          maskWidth: width,
          maskHeight: height,
          cutoffY: faceBox.bottom + faceBox.height * 0.15,
          imageHeight: imgH,
        )
      : mask;

  // [4] cutoff된 mask에서 실제 bounding rect 계산 (머리카락 경계 그대로)
  final cropRect =
      maskBoundingRect(
        trimmedMask,
        maskWidth: width,
        maskHeight: height,
        imageWidth: imgW,
        imageHeight: imgH,
      ) ??
      ui.Rect.fromLTWH(0, 0, imgW, imgH);

  // [5] 투명 PNG 생성 (cutoff mask 사용 - 네이티브 비동기)
  final resultPng = await buildHeadPngAsync(
    srcImage: srcImage,
    mask: trimmedMask,
    maskWidth: width,
    maskHeight: height,
    cropRect: cropRect,
  );

  // [6] 원본 크롭 PNG (restore 브러시용, 알파 없음 - 네이티브 비동기)
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
