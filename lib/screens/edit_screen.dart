import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/brush_state.dart';
import '../models/head_result.dart';
import '../services/image_service.dart';
import '../utils/crop_utils.dart';
import '../widgets/brush_painter.dart';
import '../widgets/brush_toolbar.dart';

final _brushProvider =
    StateNotifierProvider.autoDispose<_BrushNotifier, BrushState>(
      (ref) => _BrushNotifier(),
    );

class _BrushNotifier extends StateNotifier<BrushState> {
  _BrushNotifier() : super(const BrushState());

  void startStroke(Offset point) {
    state = state.copyWith(
      currentStroke: BrushStroke(
        mode: state.mode,
        points: [point],
        size: state.size,
      ),
      redoStack: [],
    );
  }

  void addPoint(Offset point) {
    final cur = state.currentStroke;
    if (cur == null) return;

    // 점 간의 거리가 2px 미만이면 렌더링 부하를 줄이기 위해 무시함 (스로틀링)
    if (cur.points.isNotEmpty) {
      final dist = (cur.points.last - point).distance;
      if (dist < 2.0) return;
    }

    state = state.copyWith(
      currentStroke: BrushStroke(
        mode: cur.mode,
        points: [...cur.points, point],
        size: cur.size,
      ),
    );
  }

  void commitStroke() {
    final cur = state.currentStroke;
    if (cur == null || cur.points.isEmpty) return;
    state = state.copyWith(
      strokes: [...state.strokes, cur],
      clearCurrentStroke: true,
    );
  }

  void undo() {
    if (state.strokes.isEmpty) return;
    final strokes = [...state.strokes];
    final last = strokes.removeLast();
    state = state.copyWith(
      strokes: strokes,
      redoStack: [...state.redoStack, last],
    );
  }

  void redo() {
    if (state.redoStack.isEmpty) return;
    final redo = [...state.redoStack];
    final last = redo.removeLast();
    state = state.copyWith(strokes: [...state.strokes, last], redoStack: redo);
  }

  void setMode(BrushMode mode) => state = state.copyWith(mode: mode);
  void setSize(double size) => state = state.copyWith(size: size);
  void clearAll() => state = const BrushState();
}

class EditScreen extends ConsumerStatefulWidget {
  final HeadResult result;

  const EditScreen({super.key, required this.result});

  @override
  ConsumerState<EditScreen> createState() => _EditScreenState();
}

class _EditScreenState extends ConsumerState<EditScreen> {
  ui.Image? _baseImage;
  ui.Image? _originalImage;
  final _canvasKey = GlobalKey();
  bool _busy = false;
  String? _toastMessage;
  bool _toastIsError = false;
  Timer? _toastTimer;

  // 지우기 적용 이력 (undo/redo)
  final List<({ui.Image base, ui.Image? original})> _imageHistory = [];
  final List<({ui.Image base, ui.Image? original})> _imageRedoStack = [];

  // 이미지 필터
  double _brightness = 0.0;
  double _warmth = 0.0;

  @override
  void initState() {
    super.initState();
    _loadImages();
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    _disposeSafeHistory();
    _baseImage?.dispose();
    _originalImage?.dispose();
    super.dispose();
  }

  void _disposeSafeHistory() {
    for (final item in _imageHistory) {
      item.base.dispose();
      item.original?.dispose();
    }
    _imageHistory.clear();
    for (final item in _imageRedoStack) {
      item.base.dispose();
      item.original?.dispose();
    }
    _imageRedoStack.clear();
  }

  Future<void> _loadImages() async {
    final base = await _decodeImage(widget.result.resultImage);
    final original = await _decodeImage(widget.result.originalCroppedBytes);
    if (!mounted) return;
    setState(() {
      _baseImage = base;
      _originalImage = original;
    });
  }

  Future<ui.Image> _decodeImage(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  // ── 화면 좌표 → 이미지 좌표 변환 헬퍼 ─────────────────────────────

  Rect _computeFitRect() {
    final canvasSize = _canvasKey.currentContext!.size!;
    final imgW = _baseImage!.width.toDouble();
    final imgH = _baseImage!.height.toDouble();
    return fitContain(
      Rect.fromLTWH(0, 0, imgW, imgH),
      Rect.fromLTWH(0, 0, canvasSize.width, canvasSize.height),
    );
  }

  Offset _toImageCoord(Offset screenPt, Rect fitRect) {
    final imgW = _baseImage!.width.toDouble();
    final imgH = _baseImage!.height.toDouble();
    return Offset(
      ((screenPt.dx - fitRect.left) / fitRect.width * imgW).clamp(0.0, imgW),
      ((screenPt.dy - fitRect.top) / fitRect.height * imgH).clamp(0.0, imgH),
    );
  }

  double _toImageSize(double screenSize, Rect fitRect) =>
      screenSize * _baseImage!.width / fitRect.width;

  // ── 마스킹 적용 + 크롭 ───────────────────────────────────────────

  Future<void> _applyMaskAndCrop() async {
    final brushState = ref.read(_brushProvider);
    if (!brushState.hasMaskStrokes || _busy) return;

    setState(() => _busy = true);
    try {
      // 적용 전 이미지 상태를 히스토리에 저장
      _imageHistory.add((base: _baseImage!, original: _originalImage));

      // Redo 스택이 비워지므로 메모해 둔 기존 이미지들도 완벽히 해제해야 누수가 안 생김
      for (final item in _imageRedoStack) {
        item.base.dispose();
        item.original?.dispose();
      }
      _imageRedoStack.clear();

      final fitRect = _computeFitRect();
      final imgW = _baseImage!.width.toDouble();
      final imgH = _baseImage!.height.toDouble();
      final imgRect = Rect.fromLTWH(0, 0, imgW, imgH);

      // [1] 모든 스트로크를 원본 이미지 좌표계에서 합성
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, imgRect);
      canvas.saveLayer(imgRect, Paint());

      // base 이미지
      canvas.drawImage(_baseImage!, Offset.zero, Paint());

      // restore 스트로크 → originalImage 복원
      if (_originalImage != null) {
        for (final s in brushState.strokes.where(
          (s) => s.mode == BrushMode.restore,
        )) {
          final imgPts = s.points
              .map((p) => _toImageCoord(p, fitRect))
              .toList();
          final imgSz = _toImageSize(s.size, fitRect);
          canvas.saveLayer(null, Paint());
          _drawPointsOn(
            canvas,
            imgPts,
            Paint()
              ..strokeWidth = imgSz
              ..strokeCap = StrokeCap.round
              ..style = PaintingStyle.stroke,
          );
          canvas.drawImage(
            _originalImage!,
            Offset.zero,
            Paint()..blendMode = BlendMode.srcIn,
          );
          canvas.restore();
        }
      }

      // mask 스트로크 → 정확한 영역만 지우기 (blur 없이 hard erase)
      // blur를 쓰면 ① 중심 알파가 ~95%로 낮아져 완전 삭제가 안 되고
      // ② Gaussian 확산으로 stroke 밖 픽셀까지 지워지는 문제가 생김
      for (final s in brushState.strokes.where(
        (s) => s.mode == BrushMode.mask,
      )) {
        final imgPts = s.points.map((p) => _toImageCoord(p, fitRect)).toList();
        final imgSz = _toImageSize(s.size, fitRect);

        canvas.saveLayer(imgRect, Paint()..blendMode = BlendMode.dstOut);
        _drawPointsOn(
          canvas,
          imgPts,
          Paint()
            ..color = const Color(0xFFFFFFFF)
            ..strokeWidth = imgSz
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..style = PaintingStyle.stroke,
        );
        canvas.restore(); // dstOut
      }

      canvas.restore();
      final merged = await recorder.endRecording().toImage(
        imgW.round(),
        imgH.round(),
      );

      // [2] 불투명 픽셀 bounding box 계산 (isolate)
      final byteData = await merged.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      final bytes = byteData!.buffer.asUint8List();
      final bounds = await compute(calcOpaqueBounds, (
        bytes: bytes,
        width: merged.width,
        height: merged.height,
      ));

      // [3] bounds로 크롭
      final newBase = await _cropUiImage(merged, bounds);
      final newOriginal = _originalImage != null
          ? await _cropUiImage(_originalImage!, bounds)
          : null;

      if (!mounted) return;
      setState(() {
        _baseImage = newBase;
        _originalImage = newOriginal;
      });
      ref.read(_brushProvider.notifier).clearAll();
      _showToast('마스킹 영역이 제거됐습니다');
    } catch (e) {
      // 실패 시 저장해 둔 히스토리 항목 제거
      if (_imageHistory.isNotEmpty) _imageHistory.removeLast();
      _showToast('처리 실패: $e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<ui.Image> _cropUiImage(ui.Image src, Rect bounds) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImageRect(
      src,
      bounds,
      Rect.fromLTWH(0, 0, bounds.width, bounds.height),
      Paint(),
    );
    return recorder.endRecording().toImage(
      bounds.width.round(),
      bounds.height.round(),
    );
  }

  void _drawPointsOn(Canvas canvas, List<Offset> points, Paint paint) {
    if (points.isEmpty) return;
    if (points.length == 1) {
      canvas.drawCircle(
        points.first,
        paint.strokeWidth / 2,
        paint..style = PaintingStyle.fill,
      );
      return;
    }
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (int i = 0; i < points.length - 1; i++) {
      final p0 = points[i];
      final p1 = points[i + 1];
      // 선들이 각지지 않고 매우 부드러운 브러시처럼 보이게 이차 베지어 곡선(quadraticBezierTo)을 써서 보간함
      path.quadraticBezierTo(
        p0.dx,
        p0.dy,
        (p0.dx + p1.dx) / 2,
        (p0.dy + p1.dy) / 2,
      );
    }
    path.lineTo(points.last.dx, points.last.dy);
    canvas.drawPath(path, paint);
  }

  // ── Undo / Redo ─────────────────────────────────────────────────

  void _handleUndo() {
    final brushState = ref.read(_brushProvider);
    if (brushState.strokes.isNotEmpty) {
      ref.read(_brushProvider.notifier).undo();
    } else {
      _undoApply();
    }
  }

  void _handleRedo() {
    final brushState = ref.read(_brushProvider);
    if (brushState.redoStack.isNotEmpty) {
      ref.read(_brushProvider.notifier).redo();
    } else {
      _redoApply();
    }
  }

  void _undoApply() {
    if (_imageHistory.isEmpty) return;
    setState(() {
      _imageRedoStack.add((base: _baseImage!, original: _originalImage));
      final prev = _imageHistory.removeLast();
      _baseImage = prev.base;
      _originalImage = prev.original;
    });
    _showToast('지우기가 취소됐습니다');
  }

  void _redoApply() {
    if (_imageRedoStack.isEmpty) return;
    setState(() {
      _imageHistory.add((base: _baseImage!, original: _originalImage));
      final next = _imageRedoStack.removeLast();
      _baseImage = next.base;
      _originalImage = next.original;
    });
    _showToast('지우기가 다시 적용됐습니다');
  }

  // ── 저장 / 공유 ────────────────────────────────────────────────

  Future<Uint8List> _captureResult() async {
    final boundary =
        _canvasKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return widget.result.resultImage;
    final image = await boundary.toImage(pixelRatio: 3.0);
    final bd = await image.toByteData(format: ui.ImageByteFormat.png);
    return bd!.buffer.asUint8List();
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await _captureResult();
      await saveImageToGallery(bytes);
      _showToast('갤러리에 저장됐습니다');
    } catch (e) {
      _showToast('저장 실패: $e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await _captureResult();
      await shareImage(bytes, 'only_head_result.png');
    } catch (e) {
      _showToast('공유 실패: $e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showToast(String message, {bool isError = false}) {
    _toastTimer?.cancel();
    setState(() {
      _toastMessage = message;
      _toastIsError = isError;
    });
    _toastTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _toastMessage = null);
    });
  }

  // ── Build ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final brushState = ref.watch(_brushProvider);
    final notifier = ref.read(_brushProvider.notifier);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _buildTopBar(),
                Expanded(child: _buildCanvas()),
                BrushToolbar(
                  state: brushState,
                  onUndo: _handleUndo,
                  onRedo: _handleRedo,
                  canUndoApply: _imageHistory.isNotEmpty,
                  canRedoApply: _imageRedoStack.isNotEmpty,
                  onModeChanged: notifier.setMode,
                  onSizeChanged: notifier.setSize,
                  onApplyMask: _applyMaskAndCrop,
                  onSave: _save,
                  onShare: _share,
                  brightness: _brightness,
                  warmth: _warmth,
                  onBrightnessChanged: (v) => setState(() => _brightness = v),
                  onWarmthChanged: (v) => setState(() => _warmth = v),
                ),
              ],
            ),
            if (_toastMessage != null)
              Positioned(
                bottom: 120,
                left: 24,
                right: 24,
                child: _Toast(message: _toastMessage!, isError: _toastIsError),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const Text(
            '편집',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (_busy) ...[
            const SizedBox(width: 12),
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCanvas() {
    final brushState = ref.watch(_brushProvider);

    if (_baseImage == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    return GestureDetector(
      onPanStart: (d) =>
          ref.read(_brushProvider.notifier).startStroke(d.localPosition),
      onPanUpdate: (d) =>
          ref.read(_brushProvider.notifier).addPoint(d.localPosition),
      onPanEnd: (_) => ref.read(_brushProvider.notifier).commitStroke(),
      child: RepaintBoundary(
        key: _canvasKey,
        child: CustomPaint(
          painter: BrushPainter(
            baseImage: _baseImage!,
            originalImage: _originalImage,
            strokes: brushState.strokes,
            currentStroke: brushState.currentStroke,
            brightness: _brightness,
            warmth: _warmth,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _Toast extends StatelessWidget {
  final String message;
  final bool isError;

  const _Toast({required this.message, required this.isError});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: isError
              ? Colors.red.shade800.withValues(alpha: 0.92)
              : Colors.grey.shade800.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
