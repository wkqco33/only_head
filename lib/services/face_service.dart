import 'dart:io';
import 'dart:ui';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

final _detector = FaceDetector(
  options: FaceDetectorOptions(performanceMode: FaceDetectorMode.fast),
);

/// 이미지에서 가장 큰 얼굴의 boundingBox를 반환한다.
/// 얼굴이 감지되지 않으면 null 반환.
Future<Rect?> detectFace(File imageFile) async {
  final inputImage = InputImage.fromFile(imageFile);
  final faces = await _detector.processImage(inputImage);

  if (faces.isEmpty) return null;

  // 가장 큰 얼굴 선택
  final face = faces.reduce(
    (a, b) =>
        a.boundingBox.width * a.boundingBox.height >
            b.boundingBox.width * b.boundingBox.height
        ? a
        : b,
  );

  return face.boundingBox;
}

void disposeDetector() {
  _detector.close();
}
