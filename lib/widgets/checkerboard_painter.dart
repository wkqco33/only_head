import 'package:flutter/material.dart';

/// 투명 배경을 시각화하기 위한 체커보드 패턴 CustomPainter
class CheckerboardPainter extends CustomPainter {
  final double cellSize;

  const CheckerboardPainter({this.cellSize = 16});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    final cols = (size.width / cellSize).ceil();
    final rows = (size.height / cellSize).ceil();

    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        paint.color = (r + c) % 2 == 0 ? Colors.grey.shade300 : Colors.white;
        canvas.drawRect(
          Rect.fromLTWH(c * cellSize, r * cellSize, cellSize, cellSize),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(CheckerboardPainter old) => old.cellSize != cellSize;
}
