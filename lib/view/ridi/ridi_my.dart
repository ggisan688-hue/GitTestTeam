import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'ridi_notifications.dart';
import 'ridi_reader_settings.dart';
import 'ridi_rooms.dart';
import 'ridi_store.dart';
import 'ridi_theme.dart';
import 'ridi_widgets.dart';
import '../../widgets/screen_tag.dart';

/// RIDI_MY_01 — 이름 · 내 정보 · 로그아웃 · 설정만 (리디의 캐시·포인트·결제는 뺌)
class MyScreen extends StatelessWidget {
  const MyScreen({super.key});

  @override
  Widget build(BuildContext context) => ScreenTag(
    'RIDI_MY_01',
    alignment: Alignment.topCenter,
    child: _screen(context),
  );

  Widget _screen(BuildContext context) {
    final store = context.watch<RidiStore>();
    return Scaffold(
      appBar: AppBar(title: const Text('마이')),
      body: SafeArea(
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RidiProfileImage(imageUrl: store.profileImageUrl, size: 64),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: store.nickname,
                                style: const TextStyle(
                                  fontFamily: RidiText.f,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: RidiColors.ink,
                                ),
                              ),
                              const TextSpan(
                                text: ' 님',
                                style: TextStyle(
                                  fontFamily: RidiText.f,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w500,
                                  color: RidiColors.ink,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(store.bio, style: RidiText.sub),
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const ProfileScreen(),
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('프로필 수정', style: RidiText.sub),
                              Icon(
                                Icons.chevron_right_rounded,
                                size: 18,
                                color: RidiColors.gray,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  RidiOutlineButton(
                    '로그아웃',
                    onTap: () async {
                      final ok = await ridiConfirm(
                        context,
                        title: '로그아웃할까요?',
                        ok: '로그아웃',
                      );
                      if (ok && context.mounted) store.logout();
                    },
                  ),
                ],
              ),
            ),
            Container(height: 8, color: RidiColors.panel),
            RidiMenuRow(
              '설정',
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
            ),
            const Divider(height: 1),
          ],
        ),
      ),
    );
  }
}

/// MY › 설정 — 읽기·알림 설정 모음
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      ScreenTag('RIDI_MY_01 › 설정', child: _screen(context));

  Widget _screen(BuildContext context) {
    final store = context.watch<RidiStore>();
    return Scaffold(
      appBar: ridiAppBar(context, '설정'),
      body: SafeArea(
        child: ListView(
          children: [
            const _Section('읽기'),
            RidiMenuRow(
              '보기 설정',
              value:
                  '글자 ${(store.fontScale * 100).round()}% · ${['좁게', '보통', '넓게'][store.lineHeightStep]}',
              onTap: () => showViewSettings(context),
            ),
            const Divider(height: 1),
            RidiMenuRow(
              '뷰어 설정',
              value: store.twoColumn ? '2단' : '1단',
              onTap: () => showViewerSettings(context),
            ),
            const Divider(height: 1),
            const _Section('알림'),
            RidiMenuRow(
              '알림 설정',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const NotiSettingsScreen()),
              ),
            ),
            const Divider(height: 1),
            const _Section('앱 정보'),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Text(
                '${RidiBrand.appName} (리디 UI 실험) · ${RidiBrand.teamName} 제작',
                style: RidiText.sub,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 설정 화면의 구역 제목 (읽기 · 알림 · 앱 정보)
class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Text(
        title,
        style: RidiText.sub.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}
