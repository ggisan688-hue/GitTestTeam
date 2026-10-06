import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../theme/app_theme.dart';
import '../../viewmodel/reading_viewmodel.dart';
import '../../viewmodel/room_viewmodel.dart';
import '../../widgets/buttons.dart';
import '../../widgets/screen_tag.dart';
import '../report/report_screen.dart';
import '../rooms/room_sheets.dart';
import 'chapter_pager.dart';
import 'panel_state.dart';
import 'side_panel.dart';

/// 읽기 화면. 본문(페이저)이 전체를 차지하고, 패널은 숨겨져 있다가 옆에서 나온다.
/// - 넓은 화면: 오른쪽 아이콘 레일 → 옆으로 슬라이드되는 인라인 패널
/// - 폰: 헤더 아이콘 → 오른쪽 드로어
/// 문장을 선택하면 메모 페이지가 자동으로 열린다.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _wide = 820.0;
  static const _panelWidth = 360.0;

  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _panel = PanelState();
  late ReadingViewModel _reading;
  int? _lastSelected;

  @override
  void initState() {
    super.initState();
    _reading = context.read<ReadingViewModel>();
    _reading.addListener(_onReadingChanged);
  }

  @override
  void dispose() {
    _reading.removeListener(_onReadingChanged);
    _panel.dispose();
    super.dispose();
  }

  /// 문장을 새로 선택하면 "필요할 때" → 메모 페이지 열기
  void _onReadingChanged() {
    final sel = _reading.selectedLine;
    if (sel != null && sel != _lastSelected) {
      _lastSelected = sel;
      final wide = MediaQuery.sizeOf(context).width > _wide;
      _panel.open(PanelTab.memo);
      if (!wide) _scaffoldKey.currentState?.openEndDrawer();
    } else if (sel == null) {
      _lastSelected = null;
    }
  }

  void _openDrawer(PanelTab tab) {
    _panel.open(tab);
    _scaffoldKey.currentState?.openEndDrawer();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _panel,
      child: LayoutBuilder(
        builder: (context, c) {
          final wide = c.maxWidth > _wide;
          return ScreenTag('S30', child: Scaffold(
            key: _scaffoldKey,
            // 폰: 오른쪽 드로어
            endDrawer: wide
                ? null
                : Drawer(
                    width: (c.maxWidth * 0.86).clamp(280.0, 420.0),
                    backgroundColor: AppColors.panel,
                    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.horizontal(left: Radius.circular(AppTheme.radiusCard))),
                    child: SafeArea(child: SidePanel(onClose: () => Navigator.of(context).pop())),
                  ),
            body: SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(wide ? AppSpace.lg : AppSpace.md, wide ? AppSpace.lg : AppSpace.md, wide ? AppSpace.lg : AppSpace.md, wide ? AppSpace.lg : AppSpace.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AreaTag('S30.1', child: _Header(wide: wide, onOpen: _openDrawer)),
                    SizedBox(height: wide ? AppSpace.lg : AppSpace.md),
                    Expanded(
                      child: wide
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Expanded(child: AreaTag('S30.2', child: ChapterPager())),
                                const SizedBox(width: AppSpace.md),
                                // 옆에서 슬라이드 인/아웃 되는 인라인 패널
                                Consumer<PanelState>(
                                  builder: (_, s, _) => AnimatedContainer(
                                    duration: const Duration(milliseconds: 260),
                                    curve: Curves.easeOutCubic,
                                    width: s.isOpen ? _panelWidth : 0,
                                    margin: EdgeInsets.only(right: s.isOpen ? AppSpace.md : 0),
                                    clipBehavior: Clip.antiAlias,
                                    decoration: BoxDecoration(
                                      color: AppColors.panel,
                                      border: Border.all(color: s.isOpen ? AppColors.line : Colors.transparent),
                                      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                                    ),
                                    child: s.isOpen
                                        ? OverflowBox(
                                            alignment: Alignment.centerLeft,
                                            minWidth: _panelWidth,
                                            maxWidth: _panelWidth,
                                            child: SidePanel(onClose: s.close),
                                          )
                                        : null,
                                  ),
                                ),
                                const AreaTag('S30.6', child: PanelRail()),
                              ],
                            )
                          : const AreaTag('S30.2', child: ChapterPager()),
                    ),
                  ],
                ),
              ),
            ),
          ));
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.wide, required this.onOpen});

  final bool wide;
  final void Function(PanelTab) onOpen;

  @override
  Widget build(BuildContext context) {
    final title = context.select<ReadingViewModel, String>((vm) => vm.bookTitle);
    final complete = context.select<ReadingViewModel, bool>((vm) => vm.complete);
    final room = context.select<RoomViewModel, String?>((vm) => vm.current?.name);
    final members = context.select<RoomViewModel, int>((vm) => vm.current?.humanCount ?? 0);
    return Container(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
      child: Row(
        children: [
          IconButton(
            tooltip: '내 책장',
            icon: const Icon(Icons.arrow_back, size: 22),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: AppSpace.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title.isEmpty ? '교환독서' : title, style: AppText.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(room == null ? '혼자 읽는 중' : '$room · $members명이 함께 읽는 중', style: AppText.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          if (!wide) PanelHeaderButtons(onOpen: onOpen),
          const SizedBox(width: AppSpace.sm),
          if (complete) ...[
            AppButton.primary('리포트', icon: Icons.celebration_outlined, onPressed: () {
              final vm = context.read<ReadingViewModel>();
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReportScreen(bookId: vm.bookId, bookTitle: vm.bookTitle)));
            }),
            const SizedBox(width: AppSpace.sm),
          ],
          AppButton('방 멤버', icon: Icons.people_alt_outlined, onPressed: () {
            final r = context.read<RoomViewModel>().current;
            if (r != null) showRoomMembersSheet(context, r);
          }),
        ],
      ),
    );
  }
}
