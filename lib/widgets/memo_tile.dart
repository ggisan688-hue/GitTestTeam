import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 메모 한 장 (.memo / .memo.spoiler)
class MemoTile extends StatelessWidget {
  const MemoTile({super.key, required this.left, required this.right, required this.body, this.spoiler = false, this.ai = false, this.commentCount, this.onComment});

  final String left;
  final String right;
  final String body;
  final bool spoiler;
  final bool ai; // AI 독서 친구의 메모 (다른 색)
  final int? commentCount; // null 이면 댓글 버튼 없음
  final VoidCallback? onComment;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm + 2, AppSpace.md, AppSpace.sm),
      decoration: BoxDecoration(
        color: spoiler ? AppColors.spoiler : ai ? AppColors.accentSoft : AppColors.memoBg,
        border: Border.all(color: spoiler ? AppColors.spoilerLine : ai ? AppColors.line : AppColors.memoLine),
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text('${ai ? "🤖 " : ""}$left', style: AppText.caption.copyWith(fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)),
              const SizedBox(width: AppSpace.sm),
              Text(right, style: AppText.caption),
            ],
          ),
          const SizedBox(height: AppSpace.xs),
          Text(spoiler && body.isEmpty ? '●●●●●●●●' : body, style: AppText.label.copyWith(fontWeight: FontWeight.w400, height: 1.5)),
          if (spoiler)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('(아직 읽지 않은 구간 메모)', style: AppText.micro.copyWith(fontStyle: FontStyle.italic)),
            ),
          if (commentCount != null && !spoiler)
            Align(
              alignment: Alignment.centerRight,
              child: InkWell(
                onTap: onComment,
                borderRadius: BorderRadius.circular(AppTheme.radiusControl),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 36),
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.mode_comment_outlined, size: 15, color: AppColors.accentText),
                    const SizedBox(width: AppSpace.xs),
                    Text(commentCount == 0 ? '댓글 달기' : '댓글 $commentCount', style: AppText.captionAccent),
                  ]),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 비어 있을 때 (.memo.empty)
class EmptyMemo extends StatelessWidget {
  const EmptyMemo(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.md),
      decoration: BoxDecoration(
        color: AppColors.memoBg,
        border: Border.all(color: AppColors.memoLine),
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
      ),
      child: Text(text, style: AppText.labelMuted),
    );
  }
}

/// 뷰어의 문장 한 줄 (.scene .line). 본문은 세리프 읽기 서체, 줄번호는 왼쪽 거터
class SceneLine extends StatelessWidget {
  const SceneLine({super.key, required this.index, required this.text, this.selected = false, this.hasMemo = false, this.sharedCount = 0, this.onTap, this.onLongPress});

  final int index;
  final String text;
  final bool selected;
  final bool hasMemo;
  final int sharedCount; // 이 문장에 달린 친구 메모 수
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final reading = AppText.reading();
    return Material(
      color: selected ? AppColors.accentSoft : Colors.transparent,
      borderRadius: BorderRadius.circular(AppTheme.radiusControl - 2),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        hoverColor: AppColors.sceneHover,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl - 2),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 30,
                child: Text('${index + 1}', style: AppText.micro.copyWith(height: reading.height! * reading.fontSize! / 11, color: AppColors.muted.withValues(alpha: 0.7))),
              ),
              Expanded(child: Text(text, style: reading)),
              if (sharedCount > 0)
                Padding(
                  padding: const EdgeInsets.only(left: AppSpace.sm, top: AppSpace.sm),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.people_alt_outlined, size: 14, color: AppColors.muted),
                    const SizedBox(width: 2),
                    Text('$sharedCount', style: AppText.caption),
                  ]),
                ),
              if (hasMemo)
                const Padding(
                  padding: EdgeInsets.only(left: AppSpace.sm, top: AppSpace.sm),
                  child: Icon(Icons.edit_note_rounded, size: 18, color: AppColors.accentText),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
