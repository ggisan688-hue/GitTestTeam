import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 흰 배경 + 얇은 라인 + 14px 라운드 (prototype 의 .viewer / .panel)
/// `AppCard.flat` 은 테두리 없는 연한 바탕 — 카드 안에 또 카드를 넣을 때 쓴다
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpace.lg + 2),
  }) : flat = false;

  const AppCard.flat({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpace.lg),
  }) : flat = true;

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool flat;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: flat ? AppColors.sceneBg : AppColors.panel,
        border: flat ? null : Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(
          flat ? AppTheme.radiusControl : AppTheme.radiusCard,
        ),
      ),
      child: child,
    );
  }
}

/// 섹션 제목 + 힌트 (.panel h2 + .hint)
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.hint, this.trailing});

  final String title;
  final String? hint;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.heading),
                if (hint != null && hint!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(hint!, style: AppText.caption),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

enum StatusTone { accent, neutral, success, ai, locked }

/// 상태 라벨 (누를 수 없음). 진행도·잠금·역할 표시용 — 버튼처럼 보이지 않게 작고 납작하다
class StatusBadge extends StatelessWidget {
  const StatusBadge(
    this.text, {
    super.key,
    this.tone = StatusTone.accent,
    this.icon,
  });

  final String text;
  final StatusTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tone) {
      StatusTone.accent => (AppColors.accentSoft, AppColors.accentText),
      StatusTone.neutral => (AppColors.codeBg, AppColors.muted),
      StatusTone.success => (const Color(0xFFE4F1E6), AppColors.success),
      StatusTone.ai => (const Color(0xFFEDE8F6), AppColors.ai),
      StatusTone.locked => (AppColors.spoiler, AppColors.muted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.sm + 2,
        vertical: AppSpace.xs,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppTheme.radiusChip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: AppSpace.xs),
          ],
          Text(
            text,
            style: AppText.caption.copyWith(
              color: fg,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
