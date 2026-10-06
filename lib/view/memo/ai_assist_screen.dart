import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../repository/ai_repository.dart';
import '../../theme/app_theme.dart';
import '../../viewmodel/ai_assist_viewmodel.dart';
import '../../viewmodel/reading_viewmodel.dart';
import '../../widgets/app_card.dart';
import '../../widgets/buttons.dart';
import '../../widgets/sub_page.dart';

/// AI 독서 친구: 4개 탭(문장 설명/구간 요약/인물관계도/취향 분석) + 자유 질문
class AiAssistScreen extends StatefulWidget {
  const AiAssistScreen({super.key, this.initialMode = AiMode.explain, this.lineNo});

  final AiMode initialMode;
  final int? lineNo;

  @override
  State<AiAssistScreen> createState() => _AiAssistScreenState();
}

class _AiAssistScreenState extends State<AiAssistScreen> {
  final _chat = TextEditingController();

  @override
  void initState() {
    super.initState();
    // 화면이 뜬 직후 위치를 넘기고 첫 탭을 요청
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final reading = context.read<ReadingViewModel>();
      context.read<AiAssistViewModel>().open(
            bookId: reading.bookId,
            chapter: reading.chapterNo,
            lineNo: widget.lineNo,
            initial: widget.initialMode,
          );
    });
  }

  @override
  void dispose() {
    _chat.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final q = _chat.text;
    _chat.clear();
    await context.read<AiAssistViewModel>().chat(q);
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<AiAssistViewModel>();
    final reading = context.watch<ReadingViewModel>();
    final line = widget.lineNo == null ? null : reading.chapter?.lines.where((l) => l.lineNo == widget.lineNo).firstOrNull;

    return SubPage(
      tag: 'S42',
      title: 'AI 독서 친구',
      subtitle: '${reading.bookTitle} · 제${reading.chapterNo}장',
      children: [
        if (line != null) ...[
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionTitle('선택한 문장'),
                AppCard.flat(
                  child: Text('${line.lineNo}. ${line.text}', style: AppText.quote()),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.lg),
        ],
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.sm,
                children: [
                  for (final m in AiMode.values)
                    AppFilterChip(m.label, active: m == vm.mode, onTap: () => vm.selectMode(m)),
                ],
              ),
              const SizedBox(height: AppSpace.md),
              _AnswerBox(vm: vm),
              const SizedBox(height: AppSpace.lg),
              const SectionTitle('더 물어보기'),
              for (final t in vm.turns) _ChatTurnTile(t),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _chat,
                      enabled: !vm.isChatting,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(hintText: '이 문장에서 별은 무슨 의미야?'),
                    ),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  AppButton.primary('보내기', busy: vm.isChatting, onPressed: _send),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AnswerBox extends StatelessWidget {
  const _AnswerBox({required this.vm});

  final AiAssistViewModel vm;

  @override
  Widget build(BuildContext context) {
    final answer = vm.answer;
    Widget body;
    if (vm.isLoading) {
      body = const Row(children: [
        SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        SizedBox(width: AppSpace.md),
        Text('AI 독서 친구가 읽는 중…', style: AppText.labelMuted),
      ]);
    } else if (vm.errorMessage != null && answer == null) {
      body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(vm.errorMessage!, style: AppText.error),
        const SizedBox(height: AppSpace.sm),
        AppButton('다시 시도', onPressed: vm.refresh),
      ]);
    } else if (answer == null) {
      body = Text('탭을 누르면 응답이 보여요.', style: AppText.labelMuted.copyWith(fontStyle: FontStyle.italic));
    } else {
      body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(answer.answer, style: AppText.body.copyWith(height: 1.7)),
        if (answer.sources.isNotEmpty) ...[
          const SizedBox(height: AppSpace.md),
          const Text('참고한 문장', style: AppText.caption),
          for (final s in answer.sources.take(3))
            Text('• ${s.content}', style: AppText.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
        Align(alignment: Alignment.centerRight, child: TextButton(onPressed: vm.refresh, child: const Text('다시 생성'))),
      ]);
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.md),
      constraints: const BoxConstraints(minHeight: 60),
      decoration: BoxDecoration(
        color: AppColors.codeBg,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
      ),
      child: body,
    );
  }
}

class _ChatTurnTile extends StatelessWidget {
  const _ChatTurnTile(this.turn);

  final ChatTurn turn;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Q. ${turn.question}', style: AppText.label.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: AppSpace.xs),
        if (turn.error != null)
          Text(turn.error!, style: AppText.error)
        else if (turn.answer == null)
          const Text('답변 생성 중…', style: AppText.labelMuted)
        else
          Text(turn.answer!.answer, style: AppText.body.copyWith(height: 1.65)),
      ]),
    );
  }
}
