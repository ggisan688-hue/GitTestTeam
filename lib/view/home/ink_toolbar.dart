import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../theme/app_theme.dart';
import '../../viewmodel/reading_viewmodel.dart';
import '../../widgets/app_card.dart';
import 'ink_layer.dart';

/// 챕터 바 아래 펜 도구. 펜 모드가 꺼져 있으면 토글 버튼 하나만 보인다.
/// (스타일러스는 펜 모드와 상관없이 항상 그려짐 — 펜 모드는 손가락/마우스로 그릴 때용)
class InkToolbar extends StatelessWidget {
  const InkToolbar({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ReadingViewModel>();
    final on = vm.penMode;

    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.xs),
      child: Row(
        children: [
          _Tool(
            icon: Icons.draw_outlined,
            label: on ? '펜 모드 끄기' : '펜 모드',
            active: on,
            onTap: () => vm.setPenMode(!on),
          ),
          if (on) ...[
            const SizedBox(width: AppSpace.sm),
            for (final c in inkColors)
              _ColorDot(
                color: Color(c),
                active: !vm.eraser && vm.penColor == c,
                onTap: () => vm.setPenColor(c),
              ),
            const SizedBox(width: AppSpace.sm),
            _WidthPicker(
              step: inkStepFor(vm.penWidth),
              onChanged: (s) => vm.setPenWidth(inkWidthFor(s)),
            ),
            const SizedBox(width: AppSpace.sm),
            _Tool(
              icon: Icons.auto_fix_off_outlined,
              label: '지우개',
              active: vm.eraser,
              onTap: () => vm.setEraser(!vm.eraser),
            ),
            _Tool(
              icon: Icons.undo,
              label: '실행취소',
              active: false,
              onTap: vm.canUndoInk ? vm.undoInk : null,
            ),
          ],
          const Spacer(),
          if (vm.maskedSharedCount > 0)
            Tooltip(
              message:
                  '읽는 지점보다 뒤 문장에 친구가 남긴 메모예요. 본문에서 그 문장을 눌러 읽는 지점을 옮기면 보여요.',
              child: Padding(
                padding: const EdgeInsets.only(right: AppSpace.sm),
                child: StatusBadge(
                  '친구 메모 ${vm.maskedSharedCount}개 잠김',
                  tone: StatusTone.locked,
                  icon: Icons.lock_outline,
                ),
              ),
            ),
          _Tool(
            icon: vm.showMyInk
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            label: '내 글씨',
            active: vm.showMyInk,
            onTap: vm.toggleMyInk,
            compact: true,
          ),
          _Tool(
            icon: vm.showSharedInk
                ? Icons.people_alt_outlined
                : Icons.people_outline,
            label: '멤버 글씨',
            active: vm.showSharedInk,
            onTap: vm.toggleSharedInk,
            compact: true,
          ),
        ],
      ),
    );
  }
}

class _Tool extends StatelessWidget {
  const _Tool({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.compact = false,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final fg = onTap == null
        ? AppColors.line
        : active
        ? AppColors.accentText
        : AppColors.muted;
    return Tooltip(
      message: label,
      child: Material(
        color: active && !compact ? AppColors.accentSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          child: Container(
            constraints: const BoxConstraints(
              minHeight: AppSpace.touch - 4,
              minWidth: AppSpace.touch - 4,
            ),
            padding: EdgeInsets.symmetric(
              horizontal: compact ? AppSpace.sm : AppSpace.md,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 20, color: fg),
                if (!compact) ...[
                  const SizedBox(width: AppSpace.xs + 2),
                  Text(label, style: AppText.label.copyWith(color: fg)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({
    required this.color,
    required this.active,
    required this.onTap,
  });

  final Color color;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusChip),
      child: Container(
        width: 32,
        height: 32,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: active ? AppColors.ink : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ),
    );
  }
}

class _WidthPicker extends StatelessWidget {
  const _WidthPicker({required this.step, required this.onChanged});

  final int step;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < 3; i++)
          InkWell(
            onTap: () => onChanged(i),
            borderRadius: BorderRadius.circular(AppTheme.radiusControl),
            child: Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: step == i ? AppColors.accentSoft : Colors.transparent,
                borderRadius: BorderRadius.circular(AppTheme.radiusControl),
              ),
              child: Container(
                width: 6.0 + i * 4,
                height: 6.0 + i * 4,
                decoration: const BoxDecoration(
                  color: AppColors.ink,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
