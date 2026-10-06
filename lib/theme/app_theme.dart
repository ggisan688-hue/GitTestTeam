import 'package:flutter/material.dart';

/// prototype.html 의 :root 색상 변수를 옮긴 팔레트 + P0 보강
/// (대비 수치는 bg #F5F3EF 기준 WCAG 명도 대비)
class AppColors {
  AppColors._();

  static const bg = Color(0xFFF5F3EF);
  static const panel = Color(0xFFFFFFFF);
  static const ink = Color(0xFF1C1B1A);

  /// 보조 텍스트. 원본 #7A756F(≈4.0:1) → 5.1:1
  static const muted = Color(0xFF6B665F);
  static const line = Color(0xFFE4DFD6);

  /// 채움용 강조색 (흰 글자 대비 5.0:1). 원본 #B4652A 보다 한 단계 짙음
  static const accent = Color(0xFFA85C25);

  /// 작은 강조 텍스트·아이콘용 (bg 대비 5.1:1)
  static const accentText = Color(0xFF9C5522);
  static const accentPressed = Color(0xFF8E4A1C);
  static const accentDisabled = Color(0xFFD9B99F);
  static const accentSoft = Color(0xFFF3E7D6);

  static const codeBg = Color(0xFFF1EDE5);
  static const memoBg = Color(0xFFEEF7EE);
  static const memoLine = Color(0xFFD6E6D6);
  static const spoiler = Color(0xFFE7E2D8);
  static const spoilerLine = Color(0xFFD8D0C0);
  static const sceneBg = Color(0xFFFBF9F4);
  static const sceneHover = Color(0xFFF0E9DC);
  static const friendBg = Color(0xFFF7F3EA);
  static const dark = Color(0xFF3B3A37);
  static const toast = Color(0xFF2B2B29);

  /// 상태색: 성공(공개함·완료), AI(보라), 새 메모 배지, 읽는 지점 마커
  static const success = Color(0xFF3B8A4E);
  static const ai = Color(0xFF7A5FB0);
  static const newBadge = Color(0xFFD9534F);
  static const marker = accent;
}

/// 간격 토큰. 화면 배치는 이 6단계만 쓴다
class AppSpace {
  AppSpace._();

  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;

  /// 최소 터치 타깃 (손가락·펜 공통)
  static const touch = 44.0;
}

/// 타이포 스케일. UI 는 Pretendard, 본문은 Noto Serif KR
class AppText {
  AppText._();

  static const ui = 'Pretendard';
  static const serif = 'NotoSerifKR';

  static const _fallback = ['Pretendard', 'Noto Sans KR', 'sans-serif'];

  static const display = TextStyle(
    fontFamily: ui,
    fontSize: 28,
    fontWeight: FontWeight.w700,
    height: 1.25,
    letterSpacing: -0.4,
    color: AppColors.ink,
  );
  static const title = TextStyle(
    fontFamily: ui,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.3,
    letterSpacing: -0.2,
    color: AppColors.ink,
  );
  static const heading = TextStyle(
    fontFamily: ui,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.4,
    color: AppColors.ink,
  );
  static const body = TextStyle(
    fontFamily: ui,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.55,
    color: AppColors.ink,
  );
  static const label = TextStyle(
    fontFamily: ui,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.4,
    color: AppColors.ink,
  );
  static const caption = TextStyle(
    fontFamily: ui,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.4,
    color: AppColors.muted,
  );
  static const micro = TextStyle(
    fontFamily: ui,
    fontSize: 11,
    fontWeight: FontWeight.w400,
    height: 1.3,
    color: AppColors.muted,
  );

  /// 자주 쓰는 변형
  static const bodyMuted = TextStyle(
    fontFamily: ui,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.55,
    color: AppColors.muted,
  );
  static const labelMuted = TextStyle(
    fontFamily: ui,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.4,
    color: AppColors.muted,
  );
  static const labelAccent = TextStyle(
    fontFamily: ui,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.4,
    color: AppColors.accentText,
  );
  static const captionAccent = TextStyle(
    fontFamily: ui,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 1.4,
    color: AppColors.accentText,
  );
  static const error = TextStyle(
    fontFamily: ui,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.4,
    color: AppColors.accentText,
  );

  /// 본문 읽기용 세리프. 기본 18px / 행간 1.8 / 굵기 500 (RESEARCH_eye_comfort.md 4절)
  static TextStyle reading({
    double size = 18,
    double height = 1.8,
    Color color = AppColors.ink,
  }) => TextStyle(
    fontFamily: serif,
    fontFamilyFallback: _fallback,
    fontSize: size,
    height: height,
    fontWeight: FontWeight.w500,
    color: color,
  );

  /// 인용된 본문(선택한 문장 등): 세리프, 조금 작게
  static TextStyle quote({double size = 16}) =>
      reading(size: size, height: 1.65);
}

class AppTheme {
  AppTheme._();

  static const radiusCard = 14.0;
  static const radiusControl = 10.0;
  static const radiusChip = 999.0;

  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      fontFamily: AppText.ui,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.accent,
        primary: AppColors.accent,
        surface: AppColors.panel,
        onSurface: AppColors.ink,
      ),
      scaffoldBackgroundColor: AppColors.bg,
      materialTapTargetSize: MaterialTapTargetSize.padded,
    );

    final text = base.textTheme.copyWith(
      displaySmall: AppText.display,
      titleLarge: AppText.title,
      titleMedium: AppText.heading,
      bodyLarge: AppText.body,
      bodyMedium: AppText.body,
      bodySmall: AppText.caption,
      labelLarge: AppText.label,
      labelMedium: AppText.caption,
      labelSmall: AppText.micro,
    );

    return base.copyWith(
      textTheme: text.apply(
        bodyColor: AppColors.ink,
        displayColor: AppColors.ink,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.bg,
        foregroundColor: AppColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: 60,
        titleTextStyle: AppText.title,
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(AppSpace.touch, AppSpace.touch),
          foregroundColor: AppColors.ink,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.line,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.sceneBg,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpace.lg,
          vertical: AppSpace.md,
        ),
        hintStyle: AppText.labelMuted,
        labelStyle: AppText.labelMuted,
        helperStyle: AppText.caption,
        errorStyle: AppText.caption.copyWith(color: AppColors.accentText),
        border: _border(AppColors.line),
        enabledBorder: _border(AppColors.line),
        focusedBorder: _border(AppColors.accent, width: 1.5),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.accentDisabled,
          textStyle: AppText.label.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
          minimumSize: const Size(AppSpace.touch, AppSpace.touch + 4),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.xl,
            vertical: AppSpace.md,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusControl),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.accentText,
          textStyle: AppText.label.copyWith(fontWeight: FontWeight.w600),
          minimumSize: const Size(AppSpace.touch, AppSpace.touch),
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) =>
              s.contains(WidgetState.selected) ? Colors.white : AppColors.muted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? AppColors.accent
              : AppColors.line,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      tooltipTheme: TooltipThemeData(
        textStyle: AppText.caption.copyWith(color: Colors.white),
        decoration: BoxDecoration(
          color: AppColors.toast,
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.toast,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        contentTextStyle: AppText.label.copyWith(color: Colors.white),
      ),
    );
  }

  static OutlineInputBorder _border(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusControl),
        borderSide: BorderSide(color: color, width: width),
      );
}
