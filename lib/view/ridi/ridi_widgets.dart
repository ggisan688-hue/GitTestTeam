import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_config.dart';

import 'ridi_theme.dart';

/// 리디 화면에서 반복해 쓰는 조각들. 와이어프레임(docs/design/wire)과 같은 모양.

/// 화면 아래 짧은 안내 (1.6초, 이전 안내는 바로 지움)
void ridiToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(milliseconds: 1600),
      ),
    );
}

/// 왼쪽 뒤로 · 가운데 제목 · 오른쪽 글자 버튼 (리디 상세 화면 공통)
AppBar ridiAppBar(
  BuildContext context,
  String title, {
  String? right,
  VoidCallback? onRight,
  bool back = true,
  List<Widget>? actions,
}) {
  return AppBar(
    leading: back
        ? IconButton(
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 20,
              color: RidiColors.ink,
            ),
            onPressed: () => Navigator.of(context).maybePop(),
          )
        : null,
    automaticallyImplyLeading: false,
    title: Text(title),
    actions: [
      if (right != null)
        TextButton(
          onPressed: onRight,
          style: TextButton.styleFrom(
            foregroundColor: onRight == null
                ? RidiColors.grayLight
                : RidiColors.ink,
          ),
          child: Text(
            right,
            style: const TextStyle(fontFamily: RidiText.f, fontSize: 16),
          ),
        ),
      ...?actions,
      const SizedBox(width: 8),
    ],
    shape: const Border(bottom: BorderSide(color: RidiColors.grayLight)),
  );
}

/// 내 서재 상단의 검은 알약 탭
class RidiPill extends StatelessWidget {
  const RidiPill(
    this.label, {
    super.key,
    required this.on,
    required this.onTap,
  });

  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: on ? RidiColors.pillBlack : Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: RidiText.f,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: on ? Colors.white : RidiColors.gray,
            ),
          ),
        ),
      ),
    );
  }
}

/// 작은 선택 칩 (말투·글자 크기 등)
class RidiChip extends StatelessWidget {
  const RidiChip(
    this.label, {
    super.key,
    required this.on,
    required this.onTap,
  });

  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: on ? RidiColors.pillBlack : Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            border: Border.all(
              color: on ? RidiColors.pillBlack : RidiColors.grayLight,
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontFamily: RidiText.f,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: on ? Colors.white : RidiColors.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 흰 바탕 + 회색 테두리 입력칸
class RidiInput extends StatelessWidget {
  const RidiInput({
    super.key,
    required this.controller,
    required this.hint,
    this.obscure = false,
    this.autofocus = false,
    this.keyboard,
    this.maxLength,
    this.onSubmitted,
    this.onChanged,
    this.style,
    this.textAlign = TextAlign.start,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String hint;
  final bool obscure;
  final bool autofocus;
  final TextInputType? keyboard;
  final int? maxLength;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final TextStyle? style;
  final TextAlign textAlign;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      autofocus: autofocus,
      keyboardType: keyboard ?? TextInputType.text,
      // These fields are controller-backed and deliberately receive the IME's
      // value as-is. Avoid input formatters or controller rewrites here: they
      // discard Android's composing range and break Korean consonant/vowel
      // composition on Samsung Keyboard and Gboard.
      enableSuggestions: !obscure,
      autocorrect: !obscure,
      maxLength: maxLength,
      maxLines: maxLines,
      textAlign: textAlign,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      style: (style ?? RidiText.body).copyWith(
        fontSize: 16,
        color: RidiColors.ink,
        fontFamilyFallback: RidiText.koreanFallback,
      ),
      decoration: InputDecoration(
        hintText: hint,
        counterText: '',
        hintStyle: RidiText.body.copyWith(
          fontSize: 16,
          color: RidiColors.gray,
          fontFamilyFallback: RidiText.koreanFallback,
        ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: RidiColors.grayLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: RidiColors.pillBlack, width: 1.4),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: RidiColors.grayLight),
        ),
      ),
    );
  }
}

/// 검은 채움 버튼 (주요 동작)
class RidiButton extends StatelessWidget {
  const RidiButton(
    this.label, {
    super.key,
    required this.onTap,
    this.icon,
    this.height = 52,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final double height;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final on = onTap != null;
    final child = Material(
      color: on ? RidiColors.pillBlack : RidiColors.grayLight,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: height,
          alignment: expand ? Alignment.center : null,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 18,
                  color: on ? Colors.white : RidiColors.gray,
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontFamily: RidiText.f,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: on ? Colors.white : RidiColors.gray,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return expand ? SizedBox(width: double.infinity, child: child) : child;
  }
}

/// 흰 바탕 + 테두리 버튼 (보조 동작)
class RidiOutlineButton extends StatelessWidget {
  const RidiOutlineButton(
    this.label, {
    super.key,
    required this.onTap,
    this.icon,
    this.height = 44,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            border: Border.all(color: RidiColors.grayLight),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: RidiColors.ink),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: const TextStyle(
                  fontFamily: RidiText.f,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: RidiColors.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 설정 화면의 한 줄 (제목 + 오른쪽 값 + ›)
class RidiMenuRow extends StatelessWidget {
  const RidiMenuRow(
    this.label, {
    super.key,
    this.value,
    this.onTap,
    this.danger = false,
  });

  final String label;
  final String? value;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 16, 18),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: RidiText.f,
                  fontSize: 17,
                  fontWeight: FontWeight.w500,
                  color: danger ? RidiColors.red : RidiColors.ink,
                ),
              ),
            ),
            if (value != null)
              Text(value!, style: RidiText.sub.copyWith(fontSize: 15)),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right_rounded, color: RidiColors.gray),
          ],
        ),
      ),
    );
  }
}

/// 토글 한 줄 (제목 · 설명 · 스위치)
class RidiToggleRow extends StatelessWidget {
  const RidiToggleRow({
    super.key,
    required this.title,
    this.sub,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String? sub;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: RidiText.bodyBold.copyWith(fontSize: 16)),
                  if (sub != null) ...[
                    const SizedBox(height: 4),
                    Text(sub!, style: RidiText.sub),
                  ],
                ],
              ),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: Colors.white,
              activeTrackColor: RidiColors.pillBlack,
              inactiveThumbColor: Colors.white,
              inactiveTrackColor: RidiColors.grayLight,
              trackOutlineColor: const WidgetStatePropertyAll(
                Colors.transparent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 책 표지 자리 (저작물 대신 회색 박스)
class RidiCover extends StatelessWidget {
  const RidiCover({super.key, this.width = 66, this.height = 95});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFDCE3EA),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Icon(
        Icons.menu_book_rounded,
        color: Colors.white70,
        size: width * 0.42,
      ),
    );
  }
}

/// 멤버 아바타 (사람은 첫 글자, AI 는 로봇)
class RidiAvatar extends StatelessWidget {
  const RidiAvatar({
    super.key,
    required this.label,
    this.ai = false,
    this.size = 36,
  });

  final String label;
  final bool ai;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: ai ? const Color(0xFFEDE8F6) : const Color(0xFFE8EEF4),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: ai
          ? Icon(
              Icons.smart_toy_outlined,
              size: size * 0.55,
              color: const Color(0xFF7A5FB0),
            )
          : Text(
              label.isEmpty ? '?' : label.substring(0, 1),
              style: TextStyle(
                fontFamily: RidiText.f,
                fontSize: size * 0.4,
                fontWeight: FontWeight.w700,
                color: RidiColors.text,
              ),
            ),
    );
  }
}

/// 현재 로그인 사용자의 서버 프로필 사진. URL이 없거나 실패하면 사진 추가 안내를 표시한다.
class RidiProfileImage extends StatelessWidget {
  const RidiProfileImage({super.key, this.imageUrl, this.size = 64});

  final String? imageUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    final resolvedUrl = url == null || url.isEmpty
        ? null
        : url.startsWith('http')
        ? url
        : '${AppConfig.baseUrl}$url';
    Widget placeholder() => Container(
      color: const Color(0xFFE8EEF4),
      alignment: Alignment.center,
      child: Icon(
        Icons.add_a_photo_outlined,
        size: size * .38,
        color: RidiColors.gray,
      ),
    );
    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: resolvedUrl == null
            ? placeholder()
            : Image.network(
                resolvedUrl,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) => progress == null
                    ? child
                    : Center(
                        child: SizedBox(
                          width: size * .3,
                          height: size * .3,
                          child: const CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        ),
                      ),
                errorBuilder: (_, _, _) => placeholder(),
              ),
      ),
    );
  }
}

/// 비었을 때 (아이콘 + 문구 + 선택 버튼)
class RidiEmpty extends StatelessWidget {
  const RidiEmpty({
    super.key,
    required this.icon,
    required this.text,
    this.action,
  });

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: RidiColors.grayLight),
          const SizedBox(height: 12),
          Text(text, style: RidiText.sub, textAlign: TextAlign.center),
          if (action != null) ...[
            const SizedBox(height: 16),
            Center(child: action!),
          ],
        ],
      ),
    );
  }
}

// ---------------- 가운데 팝업 (리디 뷰어 시트) ----------------
/// 가운데 팝업 틀 — 흰 둥근 상자, 기본 628×694 (리디 뷰어 팝업 크기)
class RidiDialogFrame extends StatelessWidget {
  const RidiDialogFrame({
    super.key,
    required this.child,
    this.width = 628,
    this.height = 694,
  });

  final Widget child;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height - 120;
    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: SizedBox(
        width: width,
        height: height > maxH ? maxH : height,
        child: child,
      ),
    );
  }
}

/// 팝업 머리: 왼쪽 글자 · 가운데 제목 · 오른쪽 글자
class RidiDialogHeader extends StatelessWidget {
  const RidiDialogHeader({
    super.key,
    required this.left,
    required this.title,
    this.right,
    this.onLeft,
    this.onRight,
    this.rightMuted = false,
  });

  final String left;
  final Widget title;
  final String? right;
  final VoidCallback? onLeft;
  final VoidCallback? onRight;
  final bool rightMuted;

  @override
  Widget build(BuildContext context) {
    final side = RidiText.body.copyWith(color: RidiColors.gray, fontSize: 16);
    return SizedBox(
      height: 60,
      child: Stack(
        children: [
          Center(child: title),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: TextButton(
              onPressed: onLeft,
              child: Text(left, style: side),
            ),
          ),
          if (right != null)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: TextButton(
                onPressed: onRight,
                child: Text(
                  right!,
                  style: side.copyWith(
                    color: rightMuted ? RidiColors.grayLight : RidiColors.gray,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 확인 다이얼로그 (삭제·나가기 등)
Future<bool> ridiConfirm(
  BuildContext context, {
  required String title,
  String? body,
  String ok = '확인',
  bool danger = false,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Colors.white,
      title: Text(title, style: RidiText.heading),
      content: body == null ? null : Text(body, style: RidiText.body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text(
            '취소',
            style: TextStyle(fontFamily: RidiText.f, color: RidiColors.gray),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(
            ok,
            style: TextStyle(
              fontFamily: RidiText.f,
              fontWeight: FontWeight.w700,
              color: danger ? RidiColors.red : RidiColors.blue,
            ),
          ),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// 펜 색 표시 — 형광펜이면 동그라미, 밑줄이면 짧은 색 막대 (메모 창·독서노트·방 메모 목록)
class RidiPenMark extends StatelessWidget {
  const RidiPenMark({
    super.key,
    required this.colorIndex,
    this.underline = false,
    this.size = 14,
  });

  final int colorIndex;
  final bool underline;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (!underline) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: RidiColors.penColors[colorIndex],
          shape: BoxShape.circle,
        ),
      );
    }
    return SizedBox(
      width: size + 4,
      height: size,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          height: 3.5,
          decoration: BoxDecoration(
            color: RidiColors.penLines[colorIndex],
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}

/// [−] 숫자 [+] — 끝값에 닿으면 버튼이 흐려진다. 누르고 있으면 계속 바뀐다 (방 최대 인원 2~50)
class RidiStepper extends StatefulWidget {
  const RidiStepper({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.unit = '명',
  });

  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  final String unit;

  @override
  State<RidiStepper> createState() => _RidiStepperState();
}

class _RidiStepperState extends State<RidiStepper> {
  Timer? _repeat;
  late int _v = widget.value;

  @override
  void didUpdateWidget(RidiStepper old) {
    super.didUpdateWidget(old);
    _v = widget.value;
  }

  @override
  void dispose() {
    _repeat?.cancel();
    super.dispose();
  }

  void _step(int d) {
    final n = (_v + d).clamp(widget.min, widget.max);
    if (n == _v) {
      _repeat?.cancel();
      return;
    }
    _v = n;
    widget.onChanged(n);
  }

  Widget _btn(IconData icon, int d) {
    final enabled = d < 0
        ? widget.value > widget.min
        : widget.value < widget.max;
    return GestureDetector(
      onLongPressStart: enabled
          ? (_) => _repeat = Timer.periodic(
              const Duration(milliseconds: 90),
              (_) => _step(d),
            )
          : null,
      onLongPressEnd: (_) => _repeat?.cancel(),
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(
          side: BorderSide(color: RidiColors.grayLight),
        ),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? () => _step(d) : null,
          child: SizedBox(
            width: 34,
            height: 34,
            child: Icon(
              icon,
              size: 18,
              color: enabled ? RidiColors.ink : RidiColors.grayLight,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _btn(Icons.remove_rounded, -1),
        SizedBox(
          width: 60,
          child: Text(
            '${widget.value}${widget.unit}',
            textAlign: TextAlign.center,
            style: RidiText.bodyBold,
          ),
        ),
        _btn(Icons.add_rounded, 1),
      ],
    );
  }
}

/// 밀어서 나오는 버튼 하나
class RidiSwipeAction {
  const RidiSwipeAction({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
}

/// 왼쪽으로 밀면 오른쪽에 버튼들이 드러나는 줄 (알림 보관·삭제). 패키지 없이 직접 구현.
/// 한 번에 하나만 열리고, 열린 줄을 누르면 닫힌다.
class RidiSwipeActions extends StatefulWidget {
  const RidiSwipeActions({
    super.key,
    required this.child,
    required this.actions,
    this.actionWidth = 88,
  });

  final Widget child;
  final List<RidiSwipeAction> actions;
  final double actionWidth;

  @override
  State<RidiSwipeActions> createState() => _RidiSwipeActionsState();
}

class _RidiSwipeActionsState extends State<RidiSwipeActions>
    with SingleTickerProviderStateMixin {
  static _RidiSwipeActionsState? _opened; // 지금 열려 있는 줄
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );

  double get _w => widget.actionWidth * widget.actions.length;

  void _open() {
    if (_opened != this) _opened?._close();
    _opened = this;
    _c.animateTo(1);
  }

  void _close() {
    if (_opened == this) _opened = null;
    _c.animateTo(0);
  }

  @override
  void dispose() {
    if (_opened == this) _opened = null;
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragUpdate: (d) =>
          _c.value = (_c.value - (d.primaryDelta ?? 0) / _w).clamp(0.0, 1.0),
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v < -300 || (v <= 300 && _c.value > 0.5)) {
          _open();
        } else {
          _close();
        }
      },
      child: Stack(
        children: [
          Positioned.fill(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                for (final a in widget.actions)
                  SizedBox(
                    width: widget.actionWidth,
                    child: Material(
                      color: a.color,
                      child: InkWell(
                        onTap: () {
                          _close();
                          a.onTap();
                        },
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(a.icon, color: Colors.white, size: 24),
                            const SizedBox(height: 6),
                            Text(
                              a.label,
                              style: const TextStyle(
                                fontFamily: RidiText.f,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          AnimatedBuilder(
            animation: _c,
            builder: (_, child) => Transform.translate(
              offset: Offset(-_w * _c.value, 0),
              child: Stack(
                children: [
                  child!,
                  // 열려 있을 때 줄을 누르면 닫기만 한다 (안의 버튼이 눌리지 않게)
                  if (_c.value > 0)
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _close,
                      ),
                    ),
                ],
              ),
            ),
            child: Material(color: Colors.white, child: widget.child),
          ),
        ],
      ),
    );
  }
}
