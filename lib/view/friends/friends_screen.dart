import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../theme/app_theme.dart';
import '../../viewmodel/friends_viewmodel.dart';
import '../../widgets/app_card.dart';
import '../../widgets/buttons.dart';
import '../../widgets/sub_page.dart';
import '../persona/persona_screen.dart';

/// 친구: 내 코드, 코드로 추가, 받은 요청 수락, 친구 목록, AI 독서 친구
class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final _code = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<FriendsViewModel>().load(),
    );
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<String?> Function() action, String ok) async {
    final err = await action();
    if (!mounted) return;
    showToast(context, err ?? ok);
    if (err == null) _code.clear();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<FriendsViewModel>();
    final ov = vm.overview;
    final persona = vm.chosenPersona;

    return SubPage(
      tag: 'S60',
      title: '친구',
      subtitle: '이전 방식 · 독서방이 서버에 붙기 전까지 메모 공유는 여기서 켜요',
      maxWidth: 560,
      children: [
        // ----- 내 코드 -----
        AppCard(
          padding: const EdgeInsets.all(AppSpace.xl),
          child: Column(
            children: [
              const Text('내 친구 코드', style: AppText.labelMuted),
              const SizedBox(height: AppSpace.md),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.xl,
                  vertical: AppSpace.md,
                ),
                decoration: BoxDecoration(
                  color: AppColors.accentSoft,
                  borderRadius: BorderRadius.circular(AppTheme.radiusControl),
                ),
                child: Text(
                  ov?.myCode ?? '…',
                  style: AppText.display.copyWith(
                    fontSize: 30,
                    letterSpacing: 2,
                    color: AppColors.accentText,
                  ),
                ),
              ),
              const SizedBox(height: AppSpace.md),
              AppButton(
                '코드 복사',
                icon: Icons.copy_rounded,
                onPressed: ov == null
                    ? null
                    : () async {
                        await Clipboard.setData(ClipboardData(text: ov.myCode));
                        if (context.mounted)
                          showToast(context, '복사됨: ${ov.myCode}');
                      },
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.lg),

        // ----- 코드로 추가 -----
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionTitle('친구 추가', hint: '친구가 알려준 코드를 입력하면 요청이 가요'),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _code,
                      // Keep the IME's composing value intact. The request layer
                      // normalizes a submitted friend code when it is sent.
                      decoration: const InputDecoration(hintText: '예: RD-7K2M'),
                      onSubmitted: (_) =>
                          _run(() => vm.request(_code.text), '친구 요청을 보냈어요'),
                    ),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  AppButton.primary(
                    '요청',
                    onPressed: () =>
                        _run(() => vm.request(_code.text), '친구 요청을 보냈어요'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.lg),

        // ----- 받은 요청 -----
        if (ov != null && ov.incoming.isNotEmpty) ...[
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionTitle('받은 요청', hint: '${ov.incoming.length}개'),
                for (final r in ov.incoming)
                  _Row(
                    name: r.other.name,
                    sub: '@${r.other.username}',
                    trailing: AppButton.primary(
                      '수락',
                      compact: true,
                      onPressed: () => _run(
                        () => vm.accept(r.id),
                        '${r.other.name}님과 친구가 되었어요',
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.lg),
        ],

        // ----- 친구 목록 -----
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionTitle(
                '친구',
                hint: ov == null ? '' : '${ov.friends.length}명',
              ),
              if (vm.isLoading && ov == null)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(AppSpace.lg),
                    child: CircularProgressIndicator(),
                  ),
                ),
              if (ov != null && ov.friends.isEmpty)
                const Text('아직 친구가 없어요. 코드를 나눠보세요.', style: AppText.labelMuted),
              for (final f in ov?.friends ?? const [])
                _Row(
                  name: f.name,
                  sub: '@${f.username}',
                  trailing: AppButton.ghost(
                    '삭제',
                    compact: true,
                    onPressed: () => _run(() => vm.remove(f.memberId), '삭제됨'),
                  ),
                ),
              for (final r in ov?.outgoing ?? const [])
                _Row(
                  name: r.other.name,
                  sub: '요청 보냄 · 수락 대기 중',
                  trailing: const SizedBox.shrink(),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.lg),

        // ----- AI 독서 친구 -----
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionTitle(
                'AI 독서 친구',
                hint: '함께 읽을 사람이 없어도 캐릭터가 먼저 메모와 질문을 남겨요',
              ),
              _Row(
                name: persona == null
                    ? '아직 고르지 않았어요'
                    : '${persona.avatar} ${persona.name}',
                sub: persona?.intro ?? '캐릭터를 고르면 읽는 장마다 메모를 남겨요',
                trailing: AppButton(
                  persona == null ? '고르기' : '바꾸기',
                  compact: true,
                  kind: persona == null
                      ? AppButtonKind.primary
                      : AppButtonKind.secondary,
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const PersonaScreen()),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.name, required this.sub, required this.trailing});

  final String name;
  final String sub;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.sm),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.md,
        vertical: AppSpace.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.friendBg,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: AppText.label),
                Text(
                  sub,
                  style: AppText.caption,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}
