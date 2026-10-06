import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../repository/ai_repository.dart';
import '../../theme/app_theme.dart';
import '../../viewmodel/reading_viewmodel.dart';
import '../../widgets/app_card.dart';
import '../../widgets/buttons.dart';
import '../../widgets/memo_tile.dart';
import '../../widgets/sub_page.dart';
import '../comments/comment_sheet.dart';
import 'ai_assist_screen.dart';

/// 뷰어에서 문장을 탭하면 → 이 페이지 (선택한 문장 + 메모 입력 + 이 문장의 메모들)
class LineMemoScreen extends StatefulWidget {
  const LineMemoScreen({super.key, required this.lineNo});

  final int lineNo;

  @override
  State<LineMemoScreen> createState() => _LineMemoScreenState();
}

class _LineMemoScreenState extends State<LineMemoScreen> {
  final _controller = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_controller.text.trim().isEmpty) return;
    setState(() => _saving = true);
    final vm = context.read<ReadingViewModel>();
    final ok = await vm.addMemo(widget.lineNo, _controller.text);
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      _controller.clear();
      FocusScope.of(context).unfocus();
      showToast(context, '메모 저장됨');
    } else {
      showToast(context, vm.errorMessage ?? '저장 실패');
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ReadingViewModel>();
    final line = vm.chapter?.lines
        .where((l) => l.lineNo == widget.lineNo)
        .firstOrNull;
    final memos = vm.memosOf(widget.lineNo);
    final shared = vm.sharedOf(widget.lineNo);
    final spoiler = vm.isSpoiler(widget.lineNo);

    return SubPage(
      tag: 'S40',
      title: '문장 ${widget.lineNo}',
      subtitle: '${vm.bookTitle} · 제${vm.chapterNo}장',
      children: [
        AppCard(
          padding: const EdgeInsets.all(AppSpace.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  StatusBadge(
                    spoiler ? '아직 읽지 않은 구간' : '읽은 구간',
                    tone: spoiler ? StatusTone.locked : StatusTone.success,
                    icon: spoiler ? Icons.lock_outline : Icons.check_rounded,
                  ),
                  const Spacer(),
                  AppButton(
                    'AI에게 물어보기',
                    icon: Icons.smart_toy_outlined,
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AiAssistScreen(
                          initialMode: AiMode.explain,
                          lineNo: widget.lineNo,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.lg),
              AppCard.flat(
                child: Text(
                  line?.text ?? '',
                  style: AppText.reading(size: 17, height: 1.7),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.lg),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionTitle('메모 남기기'),
              TextField(
                controller: _controller,
                minLines: 3,
                maxLines: 5,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                enableSuggestions: true,
                autocorrect: true,
                style: AppText.body.copyWith(
                  fontFamilyFallback: const ['Noto Sans KR', 'sans-serif'],
                ),
                enabled: !_saving,
                decoration: const InputDecoration(
                  hintText: '이 문장에 대한 생각을 남겨보세요',
                ),
              ),
              const SizedBox(height: AppSpace.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AppButton.primary('저장', busy: _saving, onPressed: _save),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.lg),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionTitle(
                '이 문장의 메모',
                hint: '내 메모 ${memos.length}개 · 방 메모 ${shared.length}개',
              ),
              if (memos.isEmpty && shared.isEmpty)
                const EmptyMemo('아직 메모가 없어요.'),
              for (final m in memos) ...[
                MemoTile(
                  left: '나',
                  right: m.timeLabel,
                  body: m.text,
                  spoiler: spoiler,
                  commentCount: m.commentCount,
                  onComment: () => showCommentSheet(context, m),
                ),
                const SizedBox(height: AppSpace.sm),
              ],
              for (final m in shared) ...[
                MemoTile(
                  left: m.author,
                  right: m.timeLabel,
                  body: m.text,
                  spoiler: m.spoiler,
                  ai: m.ai,
                  commentCount: m.commentCount,
                  onComment: () => showCommentSheet(context, m),
                ),
                const SizedBox(height: AppSpace.sm),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
