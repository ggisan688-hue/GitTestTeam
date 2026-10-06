import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../theme/app_theme.dart';
import '../../viewmodel/report_viewmodel.dart';
import '../../widgets/app_card.dart';
import '../../widgets/buttons.dart';
import '../../widgets/sub_page.dart';

/// 교환독서 리포트: 참여자별 메모, 장별 분포, 핫 문장, 활발한 대화, AI 총평, 인물
class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key, required this.bookId, required this.bookTitle, this.force = false});

  final int bookId;
  final String bookTitle;
  final bool force; // 완독 전 미리보기

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<ReportViewModel>().load(widget.bookId, force: widget.force));
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ReportViewModel>();
    final r = vm.report;

    return SubPage(
      tag: 'S50',
      title: '교환독서 리포트',
      subtitle: widget.bookTitle,
      maxWidth: 640,
      children: [
        if (vm.isLoading)
          const Padding(
            padding: EdgeInsets.all(AppSpace.xxl + AppSpace.sm),
            child: Column(children: [CircularProgressIndicator(), SizedBox(height: AppSpace.md), Text('함께 읽은 기록을 정리하는 중…', style: AppText.labelMuted)]),
          )
        else if (vm.errorMessage != null)
          AppCard(child: Column(children: [Text(vm.errorMessage!, style: AppText.error), const SizedBox(height: AppSpace.md), AppButton('다시 시도', onPressed: () => vm.load(widget.bookId, force: widget.force))]))
        else if (r != null) ...[
          // ----- 총평 -----
          AppCard(
            padding: const EdgeInsets.all(AppSpace.xl),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const StatusBadge('AI 총평', tone: StatusTone.ai, icon: Icons.auto_awesome_outlined),
                const Spacer(),
                Text('메모 ${r['totalMemos']} · 댓글 ${r['totalComments']}', style: AppText.caption),
              ]),
              const SizedBox(height: AppSpace.md),
              Text((r['summary'] as String?) ?? '', style: AppText.body.copyWith(height: 1.7)),
              if (r['highlights'] is List) ...[
                const SizedBox(height: AppSpace.md),
                for (final h in r['highlights'] as List) Padding(padding: const EdgeInsets.only(top: AppSpace.xs), child: Text('• $h', style: AppText.labelMuted.copyWith(height: 1.5))),
              ],
            ]),
          ),
          const SizedBox(height: AppSpace.lg),

          // ----- 참여자별 -----
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SectionTitle('누가 얼마나 남겼나'),
              for (final p in (r['participants'] as List).cast<Map<String, dynamic>>()) _ParticipantBar(p: p, max: _maxMemos(r)),
            ]),
          ),
          const SizedBox(height: AppSpace.lg),

          // ----- 장별 분포 -----
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SectionTitle('어느 장에서 오래 머물렀나', hint: '참여자별 장 단위 메모 수'),
              _ChapterHeat(r: r),
            ]),
          ),
          const SizedBox(height: AppSpace.lg),

          // ----- 핫 문장 -----
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SectionTitle('가장 많이 메모된 문장'),
              if ((r['topSentences'] as List).isEmpty) const Text('아직 없어요', style: AppText.labelMuted),
              for (final s in (r['topSentences'] as List).cast<Map<String, dynamic>>())
                Container(
                  margin: const EdgeInsets.only(bottom: AppSpace.sm),
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.md),
                  decoration: BoxDecoration(color: AppColors.sceneBg, border: Border.all(color: AppColors.line), borderRadius: BorderRadius.circular(AppTheme.radiusControl)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${s['chapter']}장 ${s['lineNo']}번 · 메모 ${s['memos']} · 댓글 ${s['comments']}', style: AppText.caption),
                    const SizedBox(height: AppSpace.xs),
                    Text((s['text'] as String?) ?? '', style: AppText.quote(size: 15)),
                  ]),
                ),
            ]),
          ),
          const SizedBox(height: AppSpace.lg),

          // ----- 활발한 대화 / 인물 -----
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SectionTitle('대화가 활발했던 메모'),
              if ((r['hotMemos'] as List).isEmpty) const Text('댓글이 달린 메모가 아직 없어요', style: AppText.labelMuted),
              for (final m in (r['hotMemos'] as List).cast<Map<String, dynamic>>())
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.sm),
                  child: Text('💬 ${m['comments']} · ${m['author']} (${m['chapter']}장 ${m['lineNo']}번): ${m['text']}', style: AppText.label.copyWith(fontWeight: FontWeight.w400, height: 1.5)),
                ),
              if (r['characters'] is List && (r['characters'] as List).isNotEmpty) ...[
                const Divider(height: AppSpace.xl),
                const SectionTitle('많이 언급된 인물'),
                Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: [
                  for (final c in (r['characters'] as List).cast<Map<String, dynamic>>()) StatusBadge('${c['name']} · ${c['mentions']}', tone: StatusTone.neutral),
                ]),
              ],
            ]),
          ),
          const SizedBox(height: AppSpace.lg),
          Align(alignment: Alignment.centerRight, child: AppButton('다시 만들기', icon: Icons.refresh_rounded, onPressed: () => vm.load(widget.bookId, force: true))),
        ],
      ],
    );
  }

  static int _maxMemos(Map<String, dynamic> r) {
    var max = 1;
    for (final p in (r['participants'] as List).cast<Map<String, dynamic>>()) {
      final n = (p['textMemos'] as int) + (p['inkMemos'] as int);
      if (n > max) max = n;
    }
    return max;
  }
}

class _ParticipantBar extends StatelessWidget {
  const _ParticipantBar({required this.p, required this.max});

  final Map<String, dynamic> p;
  final int max;

  @override
  Widget build(BuildContext context) {
    final total = (p['textMemos'] as int) + (p['inkMemos'] as int);
    final label = '${p['ai'] == true ? "🤖 " : ""}${p['name']}${p['me'] == true ? " (나)" : ""}';
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(label, style: AppText.label)),
          Text('글 ${p['textMemos']} · 손글씨 ${p['inkMemos']}', style: AppText.caption),
        ]),
        const SizedBox(height: AppSpace.xs),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: max == 0 ? 0 : total / max,
            minHeight: 8,
            backgroundColor: AppColors.codeBg,
            color: p['me'] == true ? AppColors.accent : p['ai'] == true ? AppColors.ai : AppColors.success,
          ),
        ),
      ]),
    );
  }
}

/// 참여자 × 장 히트맵 (칸 색 농도 = 메모 수)
class _ChapterHeat extends StatelessWidget {
  const _ChapterHeat({required this.r});

  final Map<String, dynamic> r;

  @override
  Widget build(BuildContext context) {
    final chapters = r['chapterCount'] as int;
    final parts = (r['participants'] as List).cast<Map<String, dynamic>>();
    var max = 1;
    for (final p in parts) {
      for (final v in (p['byChapter'] as Map).values) {
        if ((v as int) > max) max = v;
      }
    }
    return Column(children: [
      for (final p in parts)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.sm),
          child: Row(children: [
            SizedBox(width: 72, child: Text(p['name'] as String, style: AppText.caption.copyWith(color: AppColors.ink), maxLines: 1, overflow: TextOverflow.ellipsis)),
            for (var c = 1; c <= chapters; c++)
              Expanded(
                child: Tooltip(
                  message: '$c장: ${(p['byChapter'] as Map)['$c'] ?? 0}개',
                  child: Container(
                    height: 18,
                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                    decoration: BoxDecoration(
                      // 제곱근 스케일: 한 명이 압도적으로 많아도 나머지 칸이 보이게
                      color: AppColors.accent.withValues(alpha: math.sqrt((((p['byChapter'] as Map)['$c'] ?? 0) as int) / max) * 0.85 + 0.06),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
          ]),
        ),
      Row(children: [
        const SizedBox(width: 72),
        for (var c = 1; c <= chapters; c++) Expanded(child: Text('$c', textAlign: TextAlign.center, style: AppText.micro)),
      ]),
    ]);
  }
}
