import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/brush_state.dart';

class BrushPainter extends CustomPainter {
  final ui.Image baseImage;
  final ui.Image? originalImage;
  final List<BrushStroke> strokes;
  final BrushStroke? currentStroke;
  final double brightness;
  final double warmth;

  const BrushPainter({
    required this.baseImage,
    this.originalImage,
    required this.strokes,
    this.currentStroke,
    this.brightness = 0.0,
    this.warmth = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final dst = Rect.fromLTWH(0, 0, size.width, size.height);
    final src = Rect.fromLTWH(
      0, 0,
      baseImage.width.toDouble(),
      baseImage.height.toDouble(),
    );
    final fitRect = fitContain(src, dst);

    canvas.saveLayer(dst, Paint());

    // base 이미지 (필터 적용)
    canvas.drawImageRect(baseImage, src, fitRect,
        Paint()..colorFilter = ColorFilter.matrix(_buildColorMatrix(brightness, warmth)));

    // restore 스트로크 먼저 (이미지 복원)
    for (final stroke in strokes.where((s) => s.mode == BrushMode.restore)) {
      _paintRestoreStroke(canvas, stroke, fitRect, src);
    }

    // mask 스트로크: 빨간 반투명 오버레이 (미리보기)
    for (final stroke in strokes.where((s) => s.mode == BrushMode.mask)) {
      _paintMaskStroke(canvas, stroke);
    }

    // 현재 진행 중인 stroke
    if (currentStroke != null) {
      if (currentStroke!.mode == BrushMode.mask) {
        _paintMaskStroke(canvas, currentStroke!);
      } else {
        _paintRestoreStroke(canvas, currentStroke!, fitRect, src);
      }
    }

    canvas.restore();
  }

  void _paintMaskStroke(Canvas canvas, BrushStroke stroke) {
    if (stroke.points.isEmpty) return;
    final paint = Paint()
      ..color = const Color(0xCCFF2222)
      ..strokeWidth = stroke.size
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    _drawPoints(canvas, stroke.points, paint);
  }

  void _paintRestoreStroke(Canvas canvas, BrushStroke stroke, Rect fitRect, Rect src) {
    if (stroke.points.isEmpty || originalImage == null) return;
    canvas.saveLayer(null, Paint());

    final maskPaint = Paint()
      ..strokeWidth = stroke.size
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    _drawPoints(canvas, stroke.points, maskPaint);

    canvas.drawImageRect(
      originalImage!,
      src,
      fitRect,
      Paint()
        ..blendMode = BlendMode.srcIn
        ..colorFilter = ColorFilter.matrix(_buildColorMatrix(brightness, warmth)),
    );
    canvas.restore();
  }

  void _drawPoints(Canvas canvas, List<Offset> points, Paint paint) {
    if (points.length == 1) {
      final r = paint.strokeWidth / 2;
      canvas.drawCircle(points.first, r, paint..style = PaintingStyle.fill);
      return;
    }
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (int i = 0; i < points.length - 1; i++) {
        final p0 = points[i];
        final p1 = points[i + 1];
        path.quadraticBezierTo(p0.dx, p0.dy, (p0.dx + p1.dx) / 2, (p0.dy + p1.dy) / 2);
    }
    path.lineTo(points.last.dx, points.last.dy);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(BrushPainter old) =>
      old.baseImage != baseImage ||
      old.originalImage != originalImage ||
      old.strokes != strokes ||
      old.currentStroke != currentStroke ||
      old.brightness != brightness ||
      old.warmth != warmth;

  // brightness: -1.0(어둡게) ~ 1.0(밝게), warmth: -1.0(쿨) ~ 1.0(웜)
  static List<double> _buildColorMatrix(double brightness, double warmth) {
    if (brightness == 0.0 && warmth == 0.0) {
      return const [1,0,0,0,0, 0,1,0,0,0, 0,0,1,0,0, 0,0,0,1,0];
    }
    final b = (1.0 + brightness * 0.6).clamp(0.1, 2.0);
    final rMul = (b * (1.0 + warmth * 0.15)).clamp(0.1, 2.5);
    final gMul = (b * (1.0 + warmth * 0.03)).clamp(0.1, 2.5);
    final bMul = (b * (1.0 - warmth * 0.20)).clamp(0.1, 2.5);
    return [
      rMul, 0, 0, 0, warmth * 12.0,
      0, gMul, 0, 0, warmth * 3.0,
      0, 0, bMul, 0, -warmth * 15.0,
      0, 0, 0, 1, 0,
    ];
  }
}

/// BoxFit.contain과 동일한 rect 계산 (EditScreen에서도 재사용)
Rect fitContain(Rect src, Rect dst) {
  final scale = min(dst.width / src.width, dst.height / src.height);
  final w = src.width * scale;
  final h = src.height * scale;
  final dx = dst.left + (dst.width - w) / 2;
  final dy = dst.top + (dst.height - h) / 2;
  return Rect.fromLTWH(dx, dy, w, h);
}
