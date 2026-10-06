import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/app_card.dart';
import '../../widgets/screen_tag.dart';

/// 로그인/회원가입 공통 레이아웃: 가운데 카드 + 상단 브랜드
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({super.key, required this.title, required this.subtitle, required this.child, this.tag});

  final String title;
  final String subtitle;
  final Widget child;
  final String? tag;

  @override
  Widget build(BuildContext context) {
    final page = Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _Brand(),
                  const SizedBox(height: AppSpace.xl),
                  AppCard(
                    padding: const EdgeInsets.all(AppSpace.xl),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(title, style: AppText.title),
                        const SizedBox(height: AppSpace.xs),
                        Text(subtitle, style: AppText.labelMuted),
                        const SizedBox(height: AppSpace.xl),
                        child,
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return tag == null ? page : ScreenTag(tag!, child: page);
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: AppColors.accentSoft,
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            border: Border.all(color: AppColors.line),
          ),
          child: const Icon(Icons.menu_book_rounded, color: AppColors.accent, size: 28),
        ),
        const SizedBox(height: AppSpace.md),
        const Text('교환독서', style: AppText.display),
        const SizedBox(height: AppSpace.xs),
        const Text('함께 읽고, AI 독서 친구와 이야기해요', style: AppText.labelMuted),
      ],
    );
  }
}
