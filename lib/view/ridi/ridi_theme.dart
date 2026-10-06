import 'package:flutter/material.dart';

/// 리디 스타일 색·글자·테마. 화면 파일은 모두 이 파일만 보고 색을 쓴다.
class RidiColors {
  RidiColors._();

  static const blue = Color(0xFF1F8CE6);
  static const ink = Color(0xFF000000);
  static const text = Color(0xFF222222);
  static const gray = Color(0xFF9E9E9E);
  static const grayLight = Color(0xFFE6E6E6);
  static const bg = Color(0xFFFFFFFF);
  static const panel = Color(0xFFF5F5F5);
  static const red = Color(0xFFE9484E);
  static const highlight = Color(0xFFF2C6CB);
  static const pillBlack = Color(0xFF111111);

  /// 형광펜 5색 (독서노트 색 필터와 같은 순서)
  static const penColors = [
    Color(0xFFE2CB5C),
    Color(0xFFA9CB5C),
    Color(0xFFBB8CD4),
    Color(0xFF7FBBE6),
    Color(0xFFE08A93),
  ];

  /// 밑줄 5색 — 형광펜 5색의 진한 버전 (글자 아래 선이라 옅으면 안 보인다). 순서는 penColors 와 같다
  static const penLines = [
    Color(0xFFC9A800),
    Color(0xFF6E9E1F),
    Color(0xFF8E4FB5),
    Color(0xFF2F86D1),
    Color(0xFFD2505E),
  ];

  /// 읽기 테마 — 종이색 / 어두운 테마 글자색
  static const paperLight = Color(0xFFFFFFFF);
  static const paperSepia = Color(0xFFF7F1E3);
  static const paperDark = Color(0xFF1C1C1E);
  static const textOnDark = Color(0xFFD9D9D9);
}

/// 앱 이름·로고·팀 엠블렘 (임시 — 이름과 로고는 확정 전)
class RidiBrand {
  RidiBrand._();

  static const appName = '책담';
  static const tagline = '함께 읽고, 같은 방에서 메모를 나눠요';
  static const teamName = '이팀';

  static const logo = 'assets/images/app_logo.png';
  static const teamEmblem = 'assets/images/team_emblem.png';
  static const teamMain = 'assets/images/team_main.webp';

  /// 스플래시 배경 = 팀 대표 이미지 바탕색
  static const cream = Color(0xFFFEF9F1);
  static const navy = Color(0xFF253B5C);

  static const emblemHero = 'team-emblem';
  static const splashEmblem = 168.0;
}

/// 글자 스타일 — UI 는 Pretendard(f). 본문 장 제목만 세리프(NotoSerifKR, 뷰어에서 직접 지정)
class RidiText {
  RidiText._();

  static const f = 'Pretendard';
  static const koreanFallback = <String>['Noto Sans KR', 'sans-serif'];

  static const title = TextStyle(
    fontFamily: f,
    fontSize: 18,
    fontWeight: FontWeight.w700,
    color: RidiColors.ink,
  );
  static const heading = TextStyle(
    fontFamily: f,
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: RidiColors.ink,
  );
  static const body = TextStyle(
    fontFamily: f,
    fontSize: 15,
    fontWeight: FontWeight.w400,
    color: RidiColors.text,
    height: 1.4,
  );
  static const bodyBold = TextStyle(
    fontFamily: f,
    fontSize: 15,
    fontWeight: FontWeight.w700,
    color: RidiColors.ink,
    height: 1.4,
  );
  static const sub = TextStyle(
    fontFamily: f,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: RidiColors.gray,
    height: 1.4,
  );
  static const tab = TextStyle(
    fontFamily: f,
    fontSize: 15,
    fontWeight: FontWeight.w500,
    color: RidiColors.gray,
  );
  static const tabOn = TextStyle(
    fontFamily: f,
    fontSize: 15,
    fontWeight: FontWeight.w700,
    color: RidiColors.ink,
  );
  static const nav = TextStyle(
    fontFamily: f,
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: RidiColors.gray,
  );
  static const navOn = TextStyle(
    fontFamily: f,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    color: RidiColors.ink,
  );
}

/// 앱 전체 테마 (흰 바탕 · 리디 파랑 · Pretendard). ridi_app.dart 의 MaterialApp 에서 쓴다
ThemeData ridiTheme() => ThemeData(
  useMaterial3: true,
  fontFamily: RidiText.f,
  scaffoldBackgroundColor: RidiColors.bg,
  colorScheme: ColorScheme.fromSeed(
    seedColor: RidiColors.blue,
    primary: RidiColors.blue,
    surface: RidiColors.bg,
    onSurface: RidiColors.ink,
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: RidiColors.bg,
    foregroundColor: RidiColors.ink,
    elevation: 0,
    scrolledUnderElevation: 0,
    centerTitle: true,
    toolbarHeight: 56,
    titleTextStyle: RidiText.title,
  ),
  dividerTheme: const DividerThemeData(
    color: RidiColors.grayLight,
    thickness: 1,
    space: 1,
  ),
  snackBarTheme: SnackBarThemeData(
    backgroundColor: const Color(0xFF2B2B2B),
    behavior: SnackBarBehavior.floating,
    width: 420,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    contentTextStyle: const TextStyle(
      fontFamily: RidiText.f,
      fontSize: 14,
      color: Colors.white,
    ),
  ),
);
