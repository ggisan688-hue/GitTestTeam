import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../theme/app_theme.dart';
import '../../viewmodel/friends_viewmodel.dart';
import '../../widgets/app_card.dart';
import '../../widgets/buttons.dart';
import '../../widgets/sub_page.dart';

/// AI 독서 친구 캐릭터 고르기 (프리셋 3종)
class PersonaScreen extends StatefulWidget {
  const PersonaScreen({super.key});

  @override
  State<PersonaScreen> createState() => _PersonaScreenState();
}

class _PersonaScreenState extends State<PersonaScreen> {
  @override
  void initState() {
    super.initState();
    final vm = context.read<FriendsViewModel>();
    if (vm.personas.isEmpty)
      WidgetsBinding.instance.addPostFrameCallback((_) => vm.load());
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<FriendsViewModel>();

    return SubPage(
      tag: 'S62',
      title: 'AI 독서 친구 고르기',
      subtitle: '고른 캐릭터가 읽는 장마다 먼저 메모와 질문을 남겨요. 댓글로 대화할 수 있어요.',
      maxWidth: 560,
      children: [
        if (vm.personas.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(AppSpace.xl),
              child: CircularProgressIndicator(),
            ),
          ),
        for (final p in vm.personas) ...[
          AppCard(
            padding: const EdgeInsets.all(AppSpace.lg + 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: p.chosen ? AppColors.accentSoft : AppColors.sceneBg,
                    borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                    border: Border.all(
                      color: p.chosen ? AppColors.accent : AppColors.line,
                    ),
                  ),
                  child: Text(p.avatar, style: const TextStyle(fontSize: 26)),
                ),
                const SizedBox(width: AppSpace.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(p.name, style: AppText.heading),
                          const SizedBox(width: AppSpace.sm),
                          if (p.chosen)
                            const StatusBadge(
                              '내 독서 친구',
                              tone: StatusTone.ai,
                              icon: Icons.check_rounded,
                            ),
                        ],
                      ),
                      const SizedBox(height: AppSpace.xs),
                      Text(
                        p.intro,
                        style: AppText.labelMuted.copyWith(height: 1.5),
                      ),
                      const SizedBox(height: AppSpace.md),
                      AppButton(
                        p.chosen ? '선택됨' : '이 친구로 할래요',
                        kind: p.chosen
                            ? AppButtonKind.secondary
                            : AppButtonKind.primary,
                        onPressed: p.chosen
                            ? null
                            : () async {
                                final err = await vm.choosePersona(p.memberId);
                                if (!context.mounted) return;
                                showToast(
                                  context,
                                  err ??
                                      '${p.name}이(가) 함께 읽어요. 다음에 여는 장부터 메모를 남겨요',
                                );
                              },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.md),
        ],
      ],
    );
  }
}
