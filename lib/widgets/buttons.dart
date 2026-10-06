import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

enum AppButtonKind { primary, secondary, ghost }

/// 공통 버튼. 높이 44(터치 타깃), 글자 14 w600.
/// - primary: 강조 채움 (화면당 하나)
/// - secondary: 흰 바탕 + 라인
/// - ghost: 배경 없음 (보조 동작)
class AppButton extends StatelessWidget {
  const AppButton(
    this.label, {
    super.key,
    this.onPressed,
    this.kind = AppButtonKind.secondary,
    this.icon,
    this.compact = false,
    this.busy = false,
  });

  const AppButton.primary(
    this.label, {
    super.key,
    this.onPressed,
    this.icon,
    this.compact = false,
    this.busy = false,
  }) : kind = AppButtonKind.primary;
  const AppButton.ghost(
    this.label, {
    super.key,
    this.onPressed,
    this.icon,
    this.compact = false,
    this.busy = false,
  }) : kind = AppButtonKind.ghost;

  final String label;
  final VoidCallback? onPressed;
  final AppButtonKind kind;
  final IconData? icon;

  /// 줄 안에 끼울 때 좌우 여백만 줄인다 (높이는 그대로 44)
  final bool compact;

  /// 진행 중 표시 (스피너 + 비활성)
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    final Color bg;
    final Color fg;
    final Color border;
    switch (kind) {
      case AppButtonKind.primary:
        bg = enabled ? AppColors.accent : AppColors.accentDisabled;
        fg = Colors.white;
        border = bg;
      case AppButtonKind.secondary:
        bg = AppColors.panel;
        fg = enabled ? AppColors.ink : AppColors.muted;
        border = AppColors.line;
      case AppButtonKind.ghost:
        bg = Colors.transparent;
        fg = enabled ? AppColors.accentText : AppColors.muted;
        border = Colors.transparent;
    }

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(AppTheme.radiusControl),
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        splashColor: kind == AppButtonKind.primary
            ? AppColors.accentPressed
            : AppColors.sceneHover,
        child: Container(
          constraints: const BoxConstraints(minHeight: AppSpace.touch),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? AppSpace.md : AppSpace.lg + 2,
          ),
          decoration: BoxDecoration(
            border: Border.all(color: border),
            borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (busy) ...[
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                ),
                const SizedBox(width: AppSpace.sm),
              ] else if (icon != null) ...[
                Icon(icon, size: 18, color: fg),
                const SizedBox(width: AppSpace.xs + 2),
              ],
              Text(
                label,
                style: AppText.label.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 여러 개 중 하나를 고르는 필터/모드 칩 (알약). 높이 36, 터치 영역은 44
class AppFilterChip extends StatelessWidget {
  const AppFilterChip(
    this.label, {
    super.key,
    this.active = false,
    this.onTap,
    this.icon,
  });

  final String label;
  final bool active;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final fg = active ? Colors.white : AppColors.ink;
    return Material(
      color: active ? AppColors.accent : AppColors.panel,
      borderRadius: BorderRadius.circular(AppTheme.radiusChip),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusChip),
        child: Container(
          constraints: const BoxConstraints(minHeight: 36),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.lg - 2,
            vertical: AppSpace.xs,
          ),
          decoration: BoxDecoration(
            border: Border.all(
              color: active ? AppColors.accent : AppColors.line,
            ),
            borderRadius: BorderRadius.circular(AppTheme.radiusChip),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: fg),
                const SizedBox(width: AppSpace.xs + 2),
              ],
              Text(
                label,
                style: AppText.label.copyWith(
                  color: fg,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void showToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(milliseconds: 1600),
      ),
    );
}
