import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../repository/ai_repository.dart';
import '../../theme/app_theme.dart';
import '../../viewmodel/reading_viewmodel.dart';
import '../../widgets/app_card.dart';
import '../../widgets/buttons.dart';
import '../../widgets/memo_tile.dart';
import '../../widgets/screen_tag.dart';
import '../memo/ai_assist_screen.dart';
import '../memo/line_memo_screen.dart';
import '../memo/my_memos_screen.dart';
import '../report/report_screen.dart';
import '../comments/comment_sheet.dart';
import '../../viewmodel/room_viewmodel.dart';
import '../rooms/room_sheets.dart';

void _push(BuildContext context, Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

const _pad = EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.lg, AppSpace.lg, AppSpace.xl);

/// ---------- 페이지 1: 내 메모 ----------
class MemoSection extends StatefulWidget {
  const MemoSection({super.key});

  @override
  State<MemoSection> createState() => _MemoSectionState();
}

class _MemoSectionState extends State<MemoSection> {
  final _memo = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _memo.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final vm = context.read<ReadingViewModel>();
    final line = vm.selectedLine;
    if (line == null || _memo.text.trim().isEmpty) return;
    setState(() => _saving = true);
    final ok = await vm.addMemo(line, _memo.text);
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      _memo.clear();
      FocusScope.of(context).unfocus();
      showToast(context, '메모 저장됨');
    } else {
      showToast(context, vm.errorMessage ?? '저장 실패');
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ReadingViewModel>();
    final selected = vm.selectedLine;

    return ScreenTag('S31.1', alignment: Alignment.bottomRight, child: ListView(
      padding: _pad,
      children: [
        SectionTitle('내 메모', hint: selected == null ? '본문에서 문장을 누르면 남길 수 있어요.' : '문장 $selected 에 메모를 남겨요'),
        if (selected != null) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.md),
            decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(AppTheme.radiusControl)),
            child: Text(vm.selected?.text ?? '', maxLines: 3, overflow: TextOverflow.ellipsis, style: AppText.quote(size: 15)),
          ),
          const SizedBox(height: AppSpace.md),
        ],
        TextField(
          controller: _memo,
          enabled: selected != null && !_saving,
          minLines: 2,
          maxLines: 4,
          onSubmitted: (_) => _save(),
          decoration: InputDecoration(hintText: selected == null ? '문장을 먼저 선택하세요' : '문장에 대한 메모를 남겨보세요'),
        ),
        const SizedBox(height: AppSpace.sm),
        Row(
          children: [
            if (selected != null)
              Flexible(
                child: TextButton(
                  onPressed: () => _push(context, LineMemoScreen(lineNo: selected)),
                  child: const Text('메모 모두 보기 →', overflow: TextOverflow.ellipsis),
                ),
              ),
            const Spacer(),
            AppButton.primary('저장', busy: _saving, onPressed: selected == null ? null : _save),
          ],
        ),
        const Divider(height: AppSpace.xl),
        SectionTitle('이 장의 메모', hint: '${vm.memos.length}개'),
        if (vm.memos.isEmpty) const EmptyMemo('아직 메모가 없어요.'),
        for (final m in vm.memos.reversed) ...[
          MemoTile(left: '문장 ${m.lineNo}', right: m.timeLabel, body: m.text, spoiler: vm.isSpoiler(m.lineNo),
              commentCount: m.commentCount, onComment: () => showCommentSheet(context, m)),
          const SizedBox(height: AppSpace.sm),
        ],
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => _push(context, const MyMemosScreen()),
            child: const Text('책 전체 메모 →'),
          ),
        ),
      ],
    ));
  }
}

/// ---------- 페이지 2: AI 보조 ----------
class AiSection extends StatelessWidget {
  const AiSection({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ReadingViewModel>();
    final selected = vm.selectedLine;

    return ScreenTag('S31.2', alignment: Alignment.bottomRight, child: ListView(
      padding: _pad,
      children: [
        SectionTitle('AI 독서 친구', hint: selected == null ? '탭을 누르면 AI 독서 친구가 답해요.' : '문장 $selected 기준으로 답해요.'),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            for (final mode in AiMode.values)
              AppFilterChip(
                mode.label,
                active: mode == (selected == null ? AiMode.summary : AiMode.explain),
                onTap: () {
                  if (mode == AiMode.explain && selected == null) {
                    showToast(context, '문장을 먼저 선택하세요');
                    return;
                  }
                  _push(context, AiAssistScreen(initialMode: mode, lineNo: selected));
                },
              ),
          ],
        ),
        const SizedBox(height: AppSpace.md),
        GestureDetector(
          onTap: () => _push(context, AiAssistScreen(initialMode: selected == null ? AiMode.summary : AiMode.explain, lineNo: selected)),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.md),
            constraints: const BoxConstraints(minHeight: 60),
            decoration: BoxDecoration(
              color: AppColors.codeBg,
              border: Border.all(color: AppColors.line),
              borderRadius: BorderRadius.circular(AppTheme.radiusControl),
            ),
            child: Text(
              selected == null
                  ? '문장을 먼저 선택하면 문장 설명을 볼 수 있어요. 요약·인물관계도·취향 분석은 바로 가능해요.'
                  : '“${vm.selected?.text ?? ''}”',
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: AppText.labelMuted.copyWith(fontStyle: FontStyle.italic),
            ),
          ),
        ),
        const Divider(height: AppSpace.xl),
        SectionTitle('교환독서 리포트', hint: vm.complete ? '완독했어요! 함께 읽은 기록을 정리해 드려요.' : '완독하면 만들어져요. 지금까지 기록으로 미리 볼 수도 있어요.'),
        Row(children: [
          AppButton(vm.complete ? '리포트 보기' : '미리보기', icon: vm.complete ? Icons.celebration_outlined : Icons.visibility_outlined,
              kind: vm.complete ? AppButtonKind.primary : AppButtonKind.secondary,
              onPressed: () => _push(context, ReportScreen(bookId: vm.bookId, bookTitle: vm.bookTitle, force: !vm.complete))),
        ]),
      ],
    ));
  }
}

/// ---------- 페이지 3: 방 메모 ----------
class ShareSection extends StatelessWidget {
  const ShareSection({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ReadingViewModel>();
    final friends = vm.sharedMemos.where((m) => !m.mine).toList();
    final aiCount = friends.where((m) => m.ai).length;

    return ScreenTag('S31.3', alignment: Alignment.bottomRight, child: ListView(
      padding: _pad,
      children: [
        SectionTitle('방 메모', hint: friends.isEmpty ? '같은 방 멤버와 AI 독서 친구가 남긴 메모가 여기 보여요.' : '이 장 ${friends.length}개${aiCount > 0 ? " · AI $aiCount" : ""}'),
        if (vm.maskedSharedCount > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(padding: EdgeInsets.only(top: 2), child: Icon(Icons.lock_outline, size: 14, color: AppColors.muted)),
              const SizedBox(width: AppSpace.xs + 2),
              Expanded(child: Text('${vm.maskedSharedCount}개는 읽는 지점보다 뒤라 잠겨 있어요. 본문에서 그 문장을 누르면 열려요.', style: AppText.caption)),
            ]),
          ),
        if (friends.isEmpty) const EmptyMemo('이 장에는 아직 방 메모가 없어요.'),
        for (final m in friends) ...[
          MemoTile(
            left: '${m.author} · 문장 ${m.lineNo}',
            right: m.timeLabel,
            body: m.text,
            spoiler: m.spoiler,
            ai: m.ai,
            commentCount: m.commentCount,
            onComment: () => showCommentSheet(context, m),
          ),
          const SizedBox(height: AppSpace.sm),
        ],
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () {
                final r = context.read<RoomViewModel>().current;
                if (r != null) showRoomMembersSheet(context, r);
              },
              child: const Text('방 멤버 →'),
            ),
          ],
        ),
      ],
    ));
  }
}
