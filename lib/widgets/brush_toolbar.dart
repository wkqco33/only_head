import 'package:flutter/material.dart';

import '../models/brush_state.dart';

class BrushToolbar extends StatelessWidget {
  final BrushState state;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final bool canUndoApply;
  final bool canRedoApply;
  final ValueChanged<BrushMode> onModeChanged;
  final ValueChanged<double> onSizeChanged;
  final VoidCallback onApplyMask;
  final VoidCallback onSave;
  final VoidCallback onShare;
  final double brightness;
  final double warmth;
  final ValueChanged<double> onBrightnessChanged;
  final ValueChanged<double> onWarmthChanged;

  const BrushToolbar({
    super.key,
    required this.state,
    required this.onUndo,
    required this.onRedo,
    this.canUndoApply = false,
    this.canRedoApply = false,
    required this.onModeChanged,
    required this.onSizeChanged,
    required this.onApplyMask,
    required this.onSave,
    required this.onShare,
    this.brightness = 0.0,
    this.warmth = 0.0,
    required this.onBrightnessChanged,
    required this.onWarmthChanged,
  });

  @override
  Widget build(BuildContext context) {
    final canUndo = state.strokes.isNotEmpty || canUndoApply;
    final canRedo = state.redoStack.isNotEmpty || canRedoApply;
    final hasMask = state.hasMaskStrokes;

    return Container(
      color: Colors.grey.shade900,
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 행 1: 모드 토글 + 마스킹 적용 버튼
          Row(
            children: [
              _ModeButton(
                label: '마스킹',
                icon: Icons.brush,
                color: Colors.redAccent,
                selected: state.mode == BrushMode.mask,
                onTap: () => onModeChanged(BrushMode.mask),
              ),
              const SizedBox(width: 6),
              _ModeButton(
                label: '복원',
                icon: Icons.auto_fix_high,
                color: Colors.lightBlueAccent,
                selected: state.mode == BrushMode.restore,
                onTap: () => onModeChanged(BrushMode.restore),
              ),
              const Spacer(),
              _ApplyButton(active: hasMask, onTap: onApplyMask),
            ],
          ),
          // 행 2: 브러시 크기 슬라이더
          Row(
            children: [
              Icon(
                Icons.circle,
                size: 8,
                color: state.mode == BrushMode.mask
                    ? Colors.redAccent.withValues(alpha: 0.7)
                    : Colors.lightBlueAccent.withValues(alpha: 0.7),
              ),
              Expanded(
                child: Slider(
                  value: state.size,
                  min: 8,
                  max: 80,
                  divisions: 18,
                  activeColor: state.mode == BrushMode.mask
                      ? Colors.redAccent
                      : Colors.lightBlueAccent,
                  inactiveColor: Colors.white24,
                  onChanged: onSizeChanged,
                ),
              ),
              Icon(
                Icons.circle,
                size: 20,
                color: state.mode == BrushMode.mask
                    ? Colors.redAccent.withValues(alpha: 0.7)
                    : Colors.lightBlueAccent.withValues(alpha: 0.7),
              ),
            ],
          ),
          // 행 3: undo/redo + 저장/공유
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.undo),
                tooltip: '실행취소',
                color: canUndo ? Colors.white : Colors.white24,
                onPressed: canUndo ? onUndo : null,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              ),
              IconButton(
                icon: const Icon(Icons.redo),
                tooltip: '다시실행',
                color: canRedo ? Colors.white : Colors.white24,
                onPressed: canRedo ? onRedo : null,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.save_alt),
                tooltip: '저장',
                color: Colors.white,
                onPressed: onSave,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.share),
                tooltip: '공유',
                color: Colors.white,
                onPressed: onShare,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              ),
            ],
          ),
          const Divider(color: Colors.white12, height: 10, thickness: 0.5),
          // 행 4: 밝기 슬라이더
          _FilterSliderRow(
            icon: Icons.brightness_6,
            label: '밝기',
            value: brightness,
            activeColor: Colors.amberAccent,
            onChanged: onBrightnessChanged,
          ),
          // 행 5: 따뜻함 슬라이더
          _FilterSliderRow(
            icon: Icons.wb_sunny_outlined,
            label: '온도',
            value: warmth,
            activeColor: Colors.deepOrangeAccent,
            onChanged: onWarmthChanged,
          ),
        ],
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _ModeButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: selected
              ? Border.all(color: color.withValues(alpha: 0.6), width: 1)
              : Border.all(color: Colors.white12, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: selected ? color : Colors.white38),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: selected ? color : Colors.white38,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ApplyButton extends StatelessWidget {
  final bool active;
  final VoidCallback onTap;

  const _ApplyButton({required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: active ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active ? Colors.redAccent : Colors.white10,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.delete_outline,
              size: 15,
              color: active ? Colors.white : Colors.white24,
            ),
            const SizedBox(width: 5),
            Text(
              '지우기',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: active ? Colors.white : Colors.white24,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterSliderRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final double value;
  final Color activeColor;
  final ValueChanged<double> onChanged;

  const _FilterSliderRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.activeColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.white54),
        const SizedBox(width: 4),
        SizedBox(
          width: 28,
          child: Text(
            label,
            style: const TextStyle(fontSize: 11, color: Colors.white54),
          ),
        ),
        Expanded(
          child: Slider(
            value: value,
            min: -1.0,
            max: 1.0,
            divisions: 40,
            activeColor: activeColor,
            inactiveColor: Colors.white24,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 32,
          child: Text(
            value == 0.0 ? '0' : '${value > 0 ? '+' : ''}${(value * 100).round()}',
            style: TextStyle(
              fontSize: 11,
              color: value == 0.0 ? Colors.white38 : activeColor,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}
