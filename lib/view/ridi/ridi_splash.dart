import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'ridi_app.dart';
import 'ridi_theme.dart';
import '../../widgets/screen_tag.dart';

/// RIDI_SPLASH_01 — 앱을 켤 때 한 번만.
/// 팀 대표 이미지가 나타났다가 → 작아지며 팀 엠블렘으로 바뀌고 →
/// 로그인 화면으로 스르르 넘어가면서 엠블렘은 로그인 화면 아래 자리로 날아가 앉는다(Hero).
/// 화면을 탭하면 건너뛴다.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);
  bool _started = false;

  /// 디자인 확인용 느리게 보기: flutter run --dart-define=SPLASH_SLOW=5
  static const _slow = int.fromEnvironment('SPLASH_SLOW', defaultValue: 1);
  bool _left = false;

  // 0.00–0.18 대표 이미지 나타남 · 0.18–0.42 머묾 · 0.42–0.72 엠블렘으로 작아짐 · 0.72–1.00 엠블렘 머묾
  late final _appear = CurvedAnimation(
    parent: _c,
    curve: const Interval(0.0, 0.18, curve: Curves.easeOutCubic),
  );
  late final _shrink = CurvedAnimation(
    parent: _c,
    curve: const Interval(0.42, 0.72, curve: Curves.easeInOutCubic),
  );
  late final _swap = CurvedAnimation(
    parent: _c,
    curve: const Interval(0.56, 0.72, curve: Curves.easeInOut),
  );

  /// 첫 빌드에서 한 번만: 길이를 정하고(애니메이션 줄이기면 0.4초) 시작
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // 기기에서 '애니메이션 줄이기'를 켰으면 짧게
    final reduce = MediaQuery.disableAnimationsOf(context);
    _c.duration = Duration(milliseconds: reduce ? 400 : 2600 * _slow);
    _start();
  }

  /// 이미지를 다 읽고 첫 화면이 실제로 그려진 뒤에 시작해야 앞부분이 잘리지 않는다
  Future<void> _start() async {
    await Future.wait([
      for (final a in [
        RidiBrand.teamMain,
        RidiBrand.teamEmblem,
        RidiBrand.logo,
      ])
        precacheImage(AssetImage(a), context),
    ]);
    await WidgetsBinding.instance.waitUntilFirstFrameRasterized;
    if (!mounted || _left) return;
    _c.forward().whenComplete(_finish);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// 로그인 화면(RidiGate)으로 교체 — 0.7초 페이드 동안 엠블렘이 아래 크레딧 자리로 날아간다(Hero).
  /// 애니메이션이 끝났을 때와 화면을 탭했을 때 둘 다 불리므로 _left 로 한 번만 이동한다.
  void _finish() {
    if (_left || !mounted) return;
    _left = true;
    _c.stop();
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 700 * _slow),
        pageBuilder: (_, _, _) => const RidiGate(),
        transitionsBuilder: (_, a, _, child) => FadeTransition(
          opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) =>
      ScreenTag('RIDI_SPLASH_01', child: _screen(context));

  Widget _screen(BuildContext context) {
    return Scaffold(
      backgroundColor: RidiBrand.cream,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _finish,
        child: LayoutBuilder(
          builder: (context, box) {
            final big = (box.biggest.shortestSide * 0.8).clamp(240.0, 620.0);
            const small = RidiBrand.splashEmblem;
            return Center(
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) {
                  final size = lerpDouble(big, small, _shrink.value)!;
                  final fade = _appear.value;
                  final swap = _swap.value;
                  return Opacity(
                    opacity: fade,
                    child: Transform.scale(
                      scale: lerpDouble(0.94, 1.0, fade)!,
                      child: SizedBox.square(
                        dimension: size,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            // 대표 이미지: 작아지면서 원이 되고, 동시에 '이팀' 글자 쪽으로 당겨 확대해
                            // 엠블렘의 글자 자리와 겹치게 한다 (바뀔 때 글자가 두 번 보이지 않게)
                            Opacity(
                              opacity: 1 - swap,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(
                                  size / 2 * _shrink.value,
                                ),
                                child: _ZoomToWordmark(
                                  progress: _shrink.value,
                                  size: size,
                                ),
                              ),
                            ),
                            // 엠블렘: 같은 자리에서 서서히 드러난다
                            Opacity(
                              opacity: swap,
                              child: Hero(
                                tag: RidiBrand.emblemHero,
                                child: Image.asset(RidiBrand.teamEmblem),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

/// 대표 이미지를 '이팀' 글자 중심으로 확대하며 가운데로 끌어온다.
/// 글자 위치·크기는 원본(1254px) 기준 (docs/design/make_brand.js 의 잘라낸 영역과 같음).
class _ZoomToWordmark extends StatelessWidget {
  const _ZoomToWordmark({required this.progress, required this.size});

  final double progress;
  final double size;

  static const _cx = 630 / 1254, _cy = 365 / 1254; // 글자 중심
  static const _zoom = (372 / 512) / (610 / 1254); // 엠블렘 속 글자 폭 ÷ 원본 속 글자 폭

  @override
  Widget build(BuildContext context) {
    final z = lerpDouble(1, _zoom, progress)!;
    final ax = lerpDouble(_cx, 0.5, progress)! * size;
    final ay = lerpDouble(_cy, 0.49, progress)! * size;
    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        Positioned(
          left: ax - _cx * size * z,
          top: ay - _cy * size * z,
          width: size * z,
          height: size * z,
          child: Image.asset(RidiBrand.teamMain, fit: BoxFit.cover),
        ),
      ],
    );
  }
}
