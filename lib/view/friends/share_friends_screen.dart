import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../theme/app_theme.dart';
import '../../viewmodel/friends_viewmodel.dart';
import '../../viewmodel/reading_viewmodel.dart';
import '../../widgets/app_card.dart';
import '../../widgets/buttons.dart';
import '../../widgets/sub_page.dart';
import 'friends_screen.dart';

/// 이 책의 내 메모를 어떤 친구에게 공개할지 (단방향). 상대가 나에게 공개했는지와 진행도도 보여줌
class ShareFriendsScreen extends StatefulWidget {
  const ShareFriendsScreen({super.key});

  @override
  State<ShareFriendsScreen> createState() => _ShareFriendsScreenState();
}

class _ShareFriendsScreenState extends State<ShareFriendsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final bookId = context.read<ReadingViewModel>().bookId;
      context.read<FriendsViewModel>().loadShares(bookId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final reading = context.watch<ReadingViewModel>();
    final vm = context.watch<FriendsViewModel>();
    final shares = vm.shares;

    return SubPage(
      tag: 'S61',
      title: '공유 친구',
      subtitle: '${reading.bookTitle} · 내 메모를 공개할 친구를 고르세요',
      maxWidth: 560,
      children: [
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionTitle('내 메모 공개', hint: '켜면 그 친구가 이 책에서 내 메모를 봐요. 친구가 나에게 공개해야 나도 친구 메모를 봐요.'),
            if (shares.isEmpty)
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('아직 친구가 없어요.', style: AppText.labelMuted),
                const SizedBox(height: AppSpace.sm),
                AppButton.primary('친구 추가하러 가기', icon: Icons.person_add_alt_1_outlined,
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FriendsScreen()))),
              ]),
            for (final s in shares)
              Container(
                margin: const EdgeInsets.only(bottom: AppSpace.sm),
                padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.xs, AppSpace.xs),
                decoration: BoxDecoration(
                  color: AppColors.friendBg,
                  border: Border.all(color: AppColors.line),
                  borderRadius: BorderRadius.circular(AppTheme.radiusControl),
                ),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(s.friend.name, style: AppText.label),
                      Text(
                        '${s.progressLabel} · ${s.sharedToMe ? "나에게 공개함" : "나에게 비공개"}',
                        style: AppText.caption.copyWith(color: s.sharedToMe ? AppColors.success : AppColors.muted),
                      ),
                    ]),
                  ),
                  Switch(
                    value: s.sharedByMe,
                    onChanged: (on) async {
                      final err = await vm.toggleShare(reading.bookId, s.friend.memberId, on);
                      if (!context.mounted) return;
                      if (err != null) {
                        showToast(context, err);
                      } else {
                        showToast(context, on ? '${s.friend.name}님에게 공개' : '${s.friend.name}님에게 비공개');
                        reading.refreshShared(reading.chapterNo);
                      }
                    },
                  ),
                ]),
              ),
          ]),
        ),
        const SizedBox(height: AppSpace.lg),
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionTitle('스포일러 방지', hint: '친구 메모 중 내 읽는 지점보다 뒤 문장의 것은 잠겨 있다가, 그 문장을 읽으면 열려요.'),
            Row(children: [
              const Icon(Icons.lock_outline, size: 16, color: AppColors.muted),
              const SizedBox(width: AppSpace.sm),
              Text('내 읽는 지점: ${reading.progress.chapter}장 ${reading.progress.lineNo}줄', style: AppText.label),
            ]),
          ]),
        ),
      ],
    );
  }
}
