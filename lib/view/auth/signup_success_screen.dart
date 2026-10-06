import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../theme/app_theme.dart';
import '../../viewmodel/auth_viewmodel.dart';
import '../rooms/rooms_screen.dart';
import 'auth_scaffold.dart';

class SignupSuccessScreen extends StatelessWidget {
  const SignupSuccessScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final name = context.watch<AuthViewModel>().member?.name ?? '';
    return AuthScaffold(
      tag: 'S03',
      title: '가입 완료',
      subtitle: '이제 독서방을 만들어볼까요?',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpace.lg + 2),
            decoration: BoxDecoration(
              color: AppColors.memoBg,
              border: Border.all(color: AppColors.memoLine),
              borderRadius: BorderRadius.circular(AppTheme.radiusControl),
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  size: 44,
                  color: AppColors.success,
                ),
                const SizedBox(height: AppSpace.sm),
                Text('$name님, 환영합니다!', style: AppText.heading),
                const SizedBox(height: AppSpace.xs),
                const Text(
                  '방을 만들어 책을 고르고, 코드로 친구를 불러 함께 읽어보세요',
                  style: AppText.labelMuted,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.xl),
          FilledButton(
            onPressed: () => Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const RoomsScreen()),
              (_) => false,
            ),
            child: const Text('독서방으로 가기'),
          ),
        ],
      ),
    );
  }
}
