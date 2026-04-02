import 'dart:io';

import 'package:google_mlkit_selfie_segmentation/google_mlkit_selfie_segmentation.dart';

final _segmenter = SelfieSegmenter(
  mode: SegmenterMode.stream,
  enableRawSizeMask: true,
);

/// 이미지 파일에서 selfie segmentation 마스크를 추출한다.
/// 반환값: `List<double>` (0.0~1.0), 크기는 [width x height]
Future<({List<double> mask, int width, int height})> runSegmentation(
  File imageFile,
) async {
  final inputImage = InputImage.fromFile(imageFile);
  final result = await _segmenter.processImage(inputImage);

  if (result == null) {
    throw Exception('Segmentation 결과 없음');
  }

  return (
    mask: result.confidences,
    width: result.width,
    height: result.height,
  );
}

void disposeSegmenter() {
  _segmenter.close();
}
