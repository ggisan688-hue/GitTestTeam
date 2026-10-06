import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'screen_tag.dart';

/// 메인에서 들어가는 하위 페이지 공통 틀: 앱바 + 가운데 정렬 스크롤
class SubPage extends StatelessWidget {
  const SubPage({super.key, required this.title, this.subtitle, required this.children, this.maxWidth = 720, this.tag});

  final String title;
  final String? subtitle;
  final List<Widget> children;
  final double maxWidth;

  /// 화면 번호 (docs/SCREENS.md)
  final String? tag;

  @override
  Widget build(BuildContext context) {
    final page = Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
            if (subtitle != null) Text(subtitle!, style: AppText.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.sm, AppSpace.lg, AppSpace.xxl),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
        ),
      ),
    );
    return tag == null ? page : ScreenTag(tag!, child: page);
  }
}
