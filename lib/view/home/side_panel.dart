import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../theme/app_theme.dart';
import '../../widgets/screen_tag.dart';
import 'panel_sections.dart';
import 'panel_state.dart';

/// 탭 정의 (아이콘·라벨)
const _tabs = [
  (PanelTab.memo, Icons.edit_note_rounded, '내 메모'),
  (PanelTab.ai, Icons.smart_toy_outlined, 'AI 보조'),
  (PanelTab.share, Icons.people_alt_outlined, '방 메모'),
];

/// 사이드 패널 본체: 상단 탭 + 좌우로 넘기는 세 페이지
class SidePanel extends StatefulWidget {
  const SidePanel({super.key, this.onClose});

  final VoidCallback? onClose;

  @override
  State<SidePanel> createState() => _SidePanelState();
}

class _SidePanelState extends State<SidePanel> {
  late final PageController _pages;
  late PanelState _state;

  @override
  void initState() {
    super.initState();
    _state = context.read<PanelState>();
    _pages = PageController(initialPage: _state.tab.index);
    _state.addListener(_sync);
  }

  @override
  void dispose() {
    _state.removeListener(_sync);
    _pages.dispose();
    super.dispose();
  }

  /// 레일/헤더 버튼으로 탭이 바뀌면 페이지도 따라감
  void _sync() {
    if (!_pages.hasClients) return;
    final target = _state.tab.index;
    if ((_pages.page ?? _pages.initialPage).round() != target) {
      _pages.animateToPage(target, duration: const Duration(milliseconds: 240), curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tab = context.select<PanelState, PanelTab>((s) => s.tab);

    return ScreenTag('S31', alignment: Alignment.topRight, child: Column(
      children: [
        // ----- 탭 헤더 -----
        Container(
          padding: const EdgeInsets.fromLTRB(AppSpace.sm, AppSpace.sm, AppSpace.sm, 0),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
          child: Row(
            children: [
              for (final (t, icon, label) in _tabs)
                _TabButton(icon: icon, label: label, active: t == tab, onTap: () => _state.select(t)),
              const Spacer(),
              if (widget.onClose != null)
                IconButton(
                  tooltip: '닫기',
                  icon: const Icon(Icons.close, size: 20, color: AppColors.muted),
                  onPressed: widget.onClose,
                ),
            ],
          ),
        ),
        // ----- 페이지 (스와이프로 넘김) -----
        Expanded(
          child: PageView(
            controller: _pages,
            onPageChanged: (i) => _state.select(PanelTab.values[i]),
            children: const [MemoSection(), AiSection(), ShareSection()],
          ),
        ),
      ],
    ));
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({required this.icon, required this.label, required this.active, required this.onTap});

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusControl),
      child: Container(
        constraints: const BoxConstraints(minHeight: AppSpace.touch),
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: active ? AppColors.accent : Colors.transparent, width: 2)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: active ? AppColors.accentText : AppColors.muted),
            const SizedBox(width: AppSpace.xs + 2),
            Text(label, style: AppText.label.copyWith(fontWeight: active ? FontWeight.w600 : FontWeight.w500, color: active ? AppColors.ink : AppColors.muted)),
          ],
        ),
      ),
    );
  }
}

/// 넓은 화면 오른쪽 가장자리의 세로 아이콘 레일. 누르면 패널이 열리고 같은 걸 다시 누르면 닫힘
class PanelRail extends StatelessWidget {
  const PanelRail({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PanelState>();

    return Container(
      width: 60,
      decoration: BoxDecoration(
        color: AppColors.panel,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      ),
      child: Column(
        children: [
          const SizedBox(height: AppSpace.sm),
          for (final (t, icon, label) in _tabs) ...[
            _RailButton(icon: icon, label: label, active: state.isOpen && state.tab == t, onTap: () => state.toggle(t)),
            const SizedBox(height: AppSpace.xs),
          ],
          const Spacer(),
          if (state.isOpen)
            IconButton(
              tooltip: '패널 닫기',
              icon: const Icon(Icons.keyboard_double_arrow_right, size: 20, color: AppColors.muted),
              onPressed: state.close,
            ),
          const SizedBox(height: AppSpace.xs),
        ],
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({required this.icon, required this.label, required this.active, required this.onTap});

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Material(
        color: active ? AppColors.accentSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          child: SizedBox(
            width: 48,
            height: 60,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 22, color: active ? AppColors.accentText : AppColors.muted),
                const SizedBox(height: AppSpace.xs),
                Text(label.replaceAll(' ', '\n'),
                    textAlign: TextAlign.center,
                    style: AppText.micro.copyWith(height: 1.15, color: active ? AppColors.accentText : AppColors.muted, fontWeight: active ? FontWeight.w600 : FontWeight.w400)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 폰 헤더용 아이콘 3개 (드로어 열기)
class PanelHeaderButtons extends StatelessWidget {
  const PanelHeaderButtons({super.key, required this.onOpen});

  final void Function(PanelTab tab) onOpen;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (t, icon, label) in _tabs)
          IconButton(
            tooltip: label,
            icon: Icon(icon, size: 22, color: AppColors.ink),
            onPressed: () => onOpen(t),
          ),
      ],
    );
  }
}
