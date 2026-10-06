import 'package:flutter/material.dart';

/// 과거 화면 식별자 호환용 wrapper. 사용자 화면에는 어떤 태그도 렌더링하지 않는다.
class ScreenTag extends StatelessWidget {
  const ScreenTag(
    this.id, {
    super.key,
    required this.child,
    this.alignment = Alignment.bottomLeft,
  });

  final String id;
  final Widget child;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) => child;
}

/// 과거 구역 식별자 호환용 wrapper. 사용자 화면에는 어떤 태그도 렌더링하지 않는다.
class AreaTag extends StatelessWidget {
  const AreaTag(this.id, {super.key, required this.child});

  final String id;
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
