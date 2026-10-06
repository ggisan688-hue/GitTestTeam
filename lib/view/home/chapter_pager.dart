import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../model/book.dart';
import '../../model/memo.dart';
import '../../theme/app_theme.dart';
import '../../viewmodel/reading_viewmodel.dart';
import '../../widgets/app_card.dart';
import '../../widgets/buttons.dart';
import '../../widgets/memo_tile.dart';
import '../../widgets/screen_tag.dart';
import '../memo/line_memo_screen.dart';
import 'ink_layer.dart';
import 'ink_toolbar.dart';

/// 본문 뷰어. 한 장 = 한 페이지(PageView)라 장을 넘기면 옆으로 슬라이드되고,
/// 각 페이지가 자기 장만 구독하므로 다른 장이 로딩돼도 다시 그리지 않는다.
class ChapterPager extends StatefulWidget {
  const ChapterPager({super.key, this.bottomPadding = 0});

  /// 폰에서 하단 시트에 가려지지 않도록 페이지 아래에 줄 여백
  final double bottomPadding;

  @override
  State<ChapterPager> createState() => _ChapterPagerState();
}

class _ChapterPagerState extends State<ChapterPager> {
  late final PageController _controller;
  late ReadingViewModel _vm;
  int _shown = 1;

  @override
  void initState() {
    super.initState();
    _vm = context.read<ReadingViewModel>();
    _shown = _vm.chapterNo;
    _controller = PageController(initialPage: _shown - 1);
    _vm.addListener(_syncPage);
  }

  @override
  void dispose() {
    _vm.removeListener(_syncPage);
    _controller.dispose();
    super.dispose();
  }

  /// 화살표 등으로 ViewModel 의 chapterNo 가 바뀌면 페이지를 따라 넘김
  void _syncPage() {
    final target = _vm.chapterNo;
    if (target == _shown || !_controller.hasClients) return;
    _shown = target;
    _controller.animateToPage(
      target - 1,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = context.select<ReadingViewModel, int>(
      (vm) => vm.chapterCount,
    );
    final penMode = context.select<ReadingViewModel, bool>((vm) => vm.penMode);

    return AppCard(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.xl,
        AppSpace.md,
        AppSpace.xl,
        0,
      ),
      child: Column(
        children: [
          const AreaTag('S30.3', child: _ChapterBar()),
          const AreaTag('S30.4', child: InkToolbar()),
          const SizedBox(height: AppSpace.sm),
          Expanded(
            child: ScrollConfiguration(
              // 스타일러스로는 페이지를 넘기지 않음(그리기 전용). 펜 모드면 손가락도 넘기지 않음
              behavior: ScrollConfiguration.of(context).copyWith(
                dragDevices: penMode
                    ? const {}
                    : const {
                        PointerDeviceKind.touch,
                        PointerDeviceKind.mouse,
                        PointerDeviceKind.trackpad,
                      },
              ),
              child: PageView.builder(
                controller: _controller,
                physics: penMode
                    ? const NeverScrollableScrollPhysics()
                    : const PageScrollPhysics(),
                itemCount: count,
                onPageChanged: (i) {
                  // 스와이프로 넘긴 경우 → ViewModel 에 알림 (화살표로 넘긴 경우는 이미 같음)
                  _shown = i + 1;
                  if (_vm.chapterNo != _shown) _vm.goTo(_shown);
                },
                itemBuilder: (_, i) => _ChapterPage(
                  chapterNo: i + 1,
                  bottomPadding: widget.bottomPadding,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 장 이동 화살표 + 읽는 지점 (현재 장 정보만 구독)
class _ChapterBar extends StatelessWidget {
  const _ChapterBar();

  @override
  Widget build(BuildContext context) {
    final vm = context.read<ReadingViewModel>();
    final chapterNo = context.select<ReadingViewModel, int>((v) => v.chapterNo);
    final count = context.select<ReadingViewModel, int>((v) => v.chapterCount);
    final readLine = context.select<ReadingViewModel, int>((v) => v.readLine);

    return Row(
      children: [
        _Arrow(
          Icons.chevron_left,
          enabled: chapterNo > 1,
          onTap: vm.prevChapter,
        ),
        Text('제$chapterNo장 / $count장', style: AppText.label),
        _Arrow(
          Icons.chevron_right,
          enabled: chapterNo < count,
          onTap: vm.nextChapter,
        ),
        const Spacer(),
        StatusBadge(
          readLine == 0 ? '읽는 지점: 시작 전' : '읽는 지점: 줄 $readLine',
          icon: Icons.bookmark_outline_rounded,
        ),
      ],
    );
  }
}

class _Arrow extends StatelessWidget {
  const _Arrow(this.icon, {required this.enabled, required this.onTap});

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      constraints: const BoxConstraints(
        minWidth: AppSpace.touch,
        minHeight: AppSpace.touch,
      ),
      icon: Icon(
        icon,
        size: 24,
        color: enabled ? AppColors.ink : AppColors.line,
      ),
      onPressed: enabled ? onTap : null,
    );
  }
}

/// 한 장의 본문. 자기 장의 캐시·로딩·선택 상태만 구독. 본문 위에 손글씨 레이어를 얹는다.
class _ChapterPage extends StatefulWidget {
  const _ChapterPage({required this.chapterNo, required this.bottomPadding});

  final int chapterNo;
  final double bottomPadding;

  @override
  State<_ChapterPage> createState() => _ChapterPageState();
}

class _ChapterPageState extends State<_ChapterPage> {
  final _rects = LineRects();
  final _stackKey = GlobalKey();

  @override
  void dispose() {
    _rects.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chapterNo = widget.chapterNo;
    final vm = context.read<ReadingViewModel>();
    final chapter = context.select<ReadingViewModel, Chapter?>(
      (v) => v.chapterAt(chapterNo),
    );
    final loading = context.select<ReadingViewModel, bool>(
      (v) => v.isChapterLoading(chapterNo),
    );
    final error = context.select<ReadingViewModel, String?>(
      (v) => v.errorAt(chapterNo),
    );
    final selected = context.select<ReadingViewModel, int?>(
      (v) => v.chapterNo == chapterNo ? v.selectedLine : null,
    );
    final memoKey = context.select<ReadingViewModel, String>(
      (v) => v.memoLinesKey(chapterNo),
    );
    final memoLines = memoKey.isEmpty
        ? const <int>{}
        : memoKey.split(',').map(int.parse).toSet();
    final sharedKey = context.select<ReadingViewModel, String>(
      (v) => v.sharedLinesKey(chapterNo),
    );
    final sharedCounts = <int, int>{};
    if (sharedKey.isNotEmpty) {
      for (final l in sharedKey.split(',').map(int.parse)) {
        sharedCounts[l] = (sharedCounts[l] ?? 0) + 1;
      }
    }
    // 손글씨: 목록이 바뀔 때만 다시 그림
    context.select<ReadingViewModel, String>((v) => v.inkKey(chapterNo));
    final List<Memo> ink = vm.inkOf(chapterNo);
    final session = vm.sessionOf(chapterNo);
    final penMode = context.select<ReadingViewModel, bool>((v) => v.penMode);
    final eraser = context.select<ReadingViewModel, bool>((v) => v.eraser);
    final penColor = context.select<ReadingViewModel, int>((v) => v.penColor);
    final penWidth = context.select<ReadingViewModel, double>(
      (v) => v.penWidth,
    );
    final lines = chapter?.lines ?? const <Line>[];

    Widget body;
    if (lines.isEmpty && loading) {
      body = const Padding(
        padding: EdgeInsets.all(AppSpace.xxl + AppSpace.sm),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (lines.isEmpty && error != null) {
      body = Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(
          children: [
            Text(error, style: AppText.error),
            const SizedBox(height: AppSpace.md),
            AppButton('다시 시도', onPressed: () => vm.ensureChapter(chapterNo)),
          ],
        ),
      );
    } else {
      body = Stack(
        key: _stackKey,
        children: [
          Column(
            children: [
              for (final line in lines)
                LineRectReporter(
                  lineNo: line.lineNo,
                  rects: _rects,
                  ancestorKey: _stackKey,
                  child: SceneLine(
                    index: line.lineNo - 1,
                    text: line.text,
                    selected: selected == line.lineNo,
                    hasMemo: memoLines.contains(line.lineNo),
                    sharedCount: sharedCounts[line.lineNo] ?? 0,
                    onTap: penMode ? null : () => vm.selectLine(line.lineNo),
                    onLongPress: penMode
                        ? null
                        : () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  LineMemoScreen(lineNo: line.lineNo),
                            ),
                          ),
                  ),
                ),
            ],
          ),
          // 손글씨 레이어 (본문과 같이 스크롤됨)
          Positioned.fill(
            child: InkCanvas(
              rects: _rects,
              strokes: ink,
              session: session,
              penMode: penMode,
              eraser: eraser,
              color: penColor,
              width: penWidth,
              onStroke: (stroke) => vm.addStroke(stroke, chapter: chapterNo),
              onErase: vm.removeInk,
            ),
          ),
        ],
      );
    }

    // 펜 모드: 드래그 스크롤 끔(그리기 우선). 평소: 스타일러스는 스크롤에서 제외해 항상 그리기
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        dragDevices: penMode
            ? const {}
            : const {
                PointerDeviceKind.touch,
                PointerDeviceKind.mouse,
                PointerDeviceKind.trackpad,
              },
      ),
      child: SingleChildScrollView(
        key: PageStorageKey('chapter-$chapterNo'),
        padding: EdgeInsets.only(bottom: AppSpace.lg + widget.bottomPadding),
        child: AreaTag(
          'S30.5',
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.md,
              vertical: AppSpace.lg,
            ),
            decoration: BoxDecoration(
              color: AppColors.sceneBg,
              border: Border.all(color: AppColors.line),
              borderRadius: BorderRadius.circular(AppTheme.radiusControl),
            ),
            child: body,
          ),
        ),
      ),
    );
  }
}
