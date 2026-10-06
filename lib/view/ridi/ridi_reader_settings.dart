import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'ridi_data.dart';
import 'ridi_store.dart';
import 'ridi_theme.dart';
import 'ridi_widgets.dart';
import '../../widgets/screen_tag.dart';

/// 뷰어 하단 도구의 시트들 — 목차 · 보기 설정 · 뷰어 설정
/// (리디처럼 화면 아래에서 올라오는 시트. 설정은 본문에 바로 반영된다.)

/// 아래에서 올라오는 흰 시트 + 화면 번호 배지(tag, 디버그에서만)
Future<T?> _sheet<T>(BuildContext context, String tag, Widget child) => showModalBottomSheet<T>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(14))),
      builder: (_) => SafeArea(child: ScreenTag(tag, child: child)),
    );

/// 시트 제목 줄
class _Head extends StatelessWidget {
  const _Head(this.title, {this.sub});

  final String title;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: RidiColors.grayLight, borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 16),
        Text(title, style: RidiText.heading),
        if (sub != null) ...[const SizedBox(height: 4), Text(sub!, style: RidiText.sub)],
      ]),
    );
  }
}

/// 목차 — 장을 누르면 그 장 첫 페이지로
Future<int?> showChapterList(BuildContext context, {required int current}) => _sheet<int>(
      context,
      'RIDI_READER_02 › 목차',
      Column(mainAxisSize: MainAxisSize.min, children: [
        const _Head('목차'),
        for (var i = 0; i < ridiChapters.length; i++)
          ListTile(
            title: Text('Chapter ${i + 1}', style: i == current ? RidiText.bodyBold : RidiText.body),
            subtitle: Text('${ridiChapters[i].lines.length}문장', style: RidiText.sub),
            trailing: i == current ? const Icon(Icons.play_arrow_rounded, size: 18, color: RidiColors.ink) : null,
            onTap: () => Navigator.pop(context, i),
          ),
        const SizedBox(height: 12),
      ]),
    );

/// 보기 설정 — 글자 크기 · 행간 · 종이 테마
Future<void> showViewSettings(BuildContext context) => _sheet<void>(
      context,
      'RIDI_READER_02 › 보기 설정',
      Consumer<RidiStore>(
        builder: (ctx, store, _) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const _Head('보기 설정', sub: '본문에 바로 적용돼요'),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
            child: Row(children: [
              const SizedBox(width: 70, child: Text('글자 크기', style: RidiText.body)),
              const Text('가', style: TextStyle(fontFamily: RidiText.f, fontSize: 13, color: RidiColors.gray)),
              Expanded(
                child: Slider(
                  value: store.fontScale,
                  min: 0.85,
                  max: 1.3,
                  divisions: 9,
                  activeColor: RidiColors.pillBlack,
                  inactiveColor: RidiColors.grayLight,
                  label: '${(store.fontScale * 100).round()}%',
                  onChanged: store.setFontScale,
                ),
              ),
              const Text('가', style: TextStyle(fontFamily: RidiText.f, fontSize: 22, color: RidiColors.ink)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
            child: Row(children: [
              const SizedBox(width: 70, child: Text('행간', style: RidiText.body)),
              for (var i = 0; i < 3; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: RidiChip(const ['좁게', '보통', '넓게'][i], on: store.lineHeightStep == i, onTap: () => store.setLineHeight(i)),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Row(children: [
              const SizedBox(width: 70, child: Text('테마', style: RidiText.body)),
              for (final t in PaperTheme.values)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: InkWell(
                    onTap: () => store.setPaper(t),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 72,
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: switch (t) { PaperTheme.light => RidiColors.paperLight, PaperTheme.sepia => RidiColors.paperSepia, PaperTheme.dark => RidiColors.paperDark },
                        border: Border.all(color: store.paper == t ? RidiColors.ink : RidiColors.grayLight, width: store.paper == t ? 2 : 1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        switch (t) { PaperTheme.light => '밝게', PaperTheme.sepia => '세피아', PaperTheme.dark => '어둡게' },
                        style: TextStyle(fontFamily: RidiText.f, fontSize: 13, fontWeight: FontWeight.w700, color: t == PaperTheme.dark ? RidiColors.textOnDark : RidiColors.ink),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
        ]),
      ),
    );

/// 뷰어 설정 — 단 수 · 화면 유지
Future<void> showViewerSettings(BuildContext context) => _sheet<void>(
      context,
      'RIDI_READER_02 › 뷰어 설정',
      Consumer<RidiStore>(
        builder: (ctx, store, _) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const _Head('뷰어 설정'),
          RidiToggleRow(
            title: '2단으로 보기',
            sub: '태블릿 가로에서 본문을 두 쪽으로 나눠 보여줘요',
            value: store.twoColumn,
            onChanged: store.setTwoColumn,
          ),
          const Divider(height: 1),
          RidiToggleRow(
            title: '읽는 동안 화면 켜 두기',
            sub: '뷰어에서만 적용돼요',
            value: store.keepScreenOn,
            onChanged: store.setKeepScreenOn,
          ),
          const SizedBox(height: 12),
        ]),
      ),
    );
