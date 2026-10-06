import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../model/room.dart';
import '../../theme/app_theme.dart';
import '../../widgets/buttons.dart';

/// 멤버 아바타 겹치기 (사람은 첫 글자, AI 는 로봇 아이콘)
class MemberAvatars extends StatelessWidget {
  const MemberAvatars(this.members, {super.key, this.size = 30, this.max = 4});

  final List<RoomMember> members;
  final double size;
  final int max;

  @override
  Widget build(BuildContext context) {
    final shown = members.take(max).toList();
    final rest = members.length - shown.length;
    final step = size * 0.72;
    return SizedBox(
      height: size,
      width: step * (shown.length + (rest > 0 ? 1 : 0)) + (size - step),
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++) Positioned(left: i * step, child: MemberAvatar(shown[i], size: size)),
          if (rest > 0)
            Positioned(
              left: shown.length * step,
              child: _Circle(size: size, bg: AppColors.codeBg, child: Text('+$rest', style: AppText.micro.copyWith(fontWeight: FontWeight.w600))),
            ),
        ],
      ),
    );
  }
}

class MemberAvatar extends StatelessWidget {
  const MemberAvatar(this.member, {super.key, this.size = 30});

  final RoomMember member;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (member.ai) {
      return _Circle(size: size, bg: const Color(0xFFEDE8F6), child: Icon(Icons.smart_toy_outlined, size: size * 0.55, color: AppColors.ai));
    }
    return _Circle(
      size: size,
      bg: AppColors.accentSoft,
      child: Text(member.initial, style: AppText.label.copyWith(fontSize: size * 0.42, fontWeight: FontWeight.w700, color: AppColors.accentText)),
    );
  }
}

class _Circle extends StatelessWidget {
  const _Circle({required this.size, required this.bg, required this.child});

  final double size;
  final Color bg;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle, border: Border.all(color: AppColors.panel, width: 2)),
      child: child,
    );
  }
}

/// 방 코드 + 복사. 눌러도 복사된다
class RoomCodeChip extends StatelessWidget {
  const RoomCodeChip(this.code, {super.key, this.large = false});

  final String code;
  final bool large;

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (context.mounted) showToast(context, '방 코드 복사됨: $code');
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.accentSoft,
      borderRadius: BorderRadius.circular(AppTheme.radiusControl),
      child: InkWell(
        onTap: () => _copy(context),
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: large ? AppSpace.lg : AppSpace.md, vertical: large ? AppSpace.md : AppSpace.sm),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(code,
                style: (large ? AppText.display : AppText.label).copyWith(color: AppColors.accentText, letterSpacing: large ? 3 : 1, fontWeight: FontWeight.w700)),
            SizedBox(width: large ? AppSpace.md : AppSpace.sm),
            Icon(Icons.copy_rounded, size: large ? 22 : 16, color: AppColors.accentText),
          ]),
        ),
      ),
    );
  }
}
