import 'dart:ui';

enum BrushMode { mask, restore }

class BrushStroke {
  final BrushMode mode;
  final List<Offset> points;
  final double size;

  const BrushStroke({
    required this.mode,
    required this.points,
    required this.size,
  });
}

class BrushState {
  final BrushMode mode;
  final double size;
  final List<BrushStroke> strokes;
  final BrushStroke? currentStroke;
  final List<BrushStroke> redoStack;

  const BrushState({
    this.mode = BrushMode.mask,
    this.size = 24.0,
    this.strokes = const [],
    this.currentStroke,
    this.redoStack = const [],
  });

  /// 아직 적용되지 않은 마스킹 스트로크가 있는지 여부
  bool get hasMaskStrokes => strokes.any((s) => s.mode == BrushMode.mask);

  BrushState copyWith({
    BrushMode? mode,
    double? size,
    List<BrushStroke>? strokes,
    BrushStroke? currentStroke,
    bool clearCurrentStroke = false,
    List<BrushStroke>? redoStack,
  }) {
    return BrushState(
      mode: mode ?? this.mode,
      size: size ?? this.size,
      strokes: strokes ?? this.strokes,
      currentStroke: clearCurrentStroke
          ? null
          : (currentStroke ?? this.currentStroke),
      redoStack: redoStack ?? this.redoStack,
    );
  }
}
