import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../theme/app_theme.dart';
import '../../viewmodel/reading_viewmodel.dart';
import '../../widgets/app_card.dart';
import '../../widgets/memo_tile.dart';
import '../../widgets/sub_page.dart';

/// 패널 "내 메모 → 전체 보기" → 이 페이지
class MyMemosScreen extends StatelessWidget {
  const MyMemosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ReadingViewModel>();

    return SubPage(
      tag: 'S41',
      title: '내 메모',
      subtitle: '${vm.bookTitle} · ${vm.memos.length}개',
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionTitle('제${vm.chapterNo}장'),
              if (vm.memos.isEmpty) const EmptyMemo('아직 메모가 없어요. 본문에서 문장을 눌러 남겨보세요.'),
              for (final m in vm.memos) ...[
                MemoTile(left: '문장 ${m.lineNo}', right: m.timeLabel, body: m.text, spoiler: vm.isSpoiler(m.lineNo)),
                const SizedBox(height: AppSpace.sm),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
