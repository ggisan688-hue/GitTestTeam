import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'ridi_store.dart';
import 'ridi_theme.dart';
import 'ridi_widgets.dart';
import '../../widgets/screen_tag.dart';

/// RIDI_MEMO_01 메모 쓰기 · RIDI_NOTE_01~03 독서노트 — UC-05-1 형광펜/메모, UC-05-2 북마크
///
/// 메모 쓰기: 형광펜 문구 + 공개 범위(이 책을 읽는 내 방 여러 개 / 나만 보기) + 1500자 입력 → 저장.
/// 독서노트: 이 책에서 "내가" 남긴 형광펜·메모·책갈피. 탭 4개, 형광펜 색 필터, 편집(여러 개 삭제), 항목 …(삭제·메모 수정).
/// 저장하면 RidiStore 에 들어가고 본문 형광펜·방 메모에 바로 보인다.

// ================= 메모 쓰기 =================
/// 메모 창 열기. note 가 있으면 그 형광펜의 메모 수정, 없으면 저장할 때 새 형광펜(분홍)을 만든다.
/// 이 책을 읽는 내 방이 있으면 공개 범위 칩이 나온다 — 방 여러 개를 같이 켤 수 있고, "나만 보기"는 전부 끈다.
/// 방에서 열었으면 처음엔 그 방이 켜져 있다 (D2).
Future<void> showRidiMemoDialog(
  BuildContext context, {
  required String bookId,
  required int chapter,
  required int page,
  required int line,
  required String phrase,
  RidiNote? note,
  String? roomId,
}) => showDialog<void>(
  context: context,
  builder: (_) => _MemoDialog(
    host: context,
    bookId: bookId,
    chapter: chapter,
    page: page,
    line: line,
    phrase: phrase,
    note: note,
    roomId: roomId,
  ),
);

/// 입력칸 컨트롤러를 State 가 들고 있어야 닫히는 애니메이션 중에 dispose 되지 않는다
class _MemoDialog extends StatefulWidget {
  const _MemoDialog({
    required this.host,
    required this.bookId,
    required this.chapter,
    required this.page,
    required this.line,
    required this.phrase,
    this.note,
    this.roomId,
  });

  final BuildContext host; // 저장 후 토스트를 띄울 화면
  final String bookId;
  final int chapter;
  final int page;
  final int line;
  final String phrase;
  final RidiNote? note;
  final String? roomId;

  @override
  State<_MemoDialog> createState() => _MemoDialogState();
}

class _MemoDialogState extends State<_MemoDialog> {
  late final _controller = TextEditingController(text: widget.note?.memo ?? '');

  // 공유할 방들. 방에서 쓰면 기본은 그 방. 이미 있는 메모는 지금 공개 범위를 따른다
  late final Set<String> _rooms = {
    ...?widget.note?.roomIds,
    if (widget.note == null) ?widget.roomId,
  };

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 저장: (새 형광펜이면 만들고) 메모 글 · 공개 범위(방들) 적용 → 닫고 결과 안내(어디에 공유했는지)
  void _save() {
    final store = context.read<RidiStore>();
    final to = _rooms.toList();
    final target =
        widget.note ??
        store.addNote(
          bookId: widget.bookId,
          kind: NoteKind.highlight,
          chapter: widget.chapter,
          page: widget.page,
          line: widget.line,
          phrase: widget.phrase,
          roomIds: to,
          penStyle: store.lastPenStyle,
        );
    store.updateMemo(target.id, _controller.text);
    store.setNoteRooms(target.id, to);
    Navigator.of(context).pop();
    if (widget.host.mounted) {
      final where = store.sharedLabel(target);
      ridiToast(
        widget.host,
        where == null ? '메모를 저장했어요 (나만 보기)' : '$where 에 공유했어요',
      );
    }
  }

  @override
  Widget build(BuildContext context) =>
      ScreenTag('RIDI_MEMO_01', child: _screen(context));

  Widget _screen(BuildContext context) {
    final store = context.read<RidiStore>();
    // 고를 수 있는 방 = 이 책을 읽는 내 방 (+ 이미 공유된 방)
    final choices = {
      for (final r in store.roomsReading(widget.bookId)) r.id: r.name,
      for (final id in _rooms) id: store.room(id)?.name ?? '나간 방',
    };
    return RidiDialogFrame(
      height: choices.isEmpty ? 480 : 560,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RidiDialogHeader(
            left: '닫기',
            onLeft: () => Navigator.of(context).pop(),
            // Rebuild only the character counter while typing. Rebuilding the
            // TextField for every IME update clears Android's composing range,
            // which leaves Hangul as separate consonant/vowel jamo.
            title: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _controller,
              builder: (_, value, __) => Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: '메모 ', style: RidiText.heading),
                    TextSpan(
                      text: '(${value.text.characters.length}/1500)',
                      style: RidiText.sub,
                    ),
                  ],
                ),
              ),
            ),
            right: '저장',
            onRight: _save,
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
            child: Row(
              children: [
                RidiPenMark(
                  colorIndex: widget.note?.colorIndex ?? 4,
                  underline:
                      (widget.note?.penStyle ?? store.lastPenStyle) ==
                      PenStyle.underline,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.phrase,
                    style: RidiText.body.copyWith(fontSize: 16),
                  ),
                ),
              ],
            ),
          ),
          if (choices.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 9),
                    child: Text('공개 범위', style: RidiText.sub),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final e in choices.entries)
                          RidiChip(
                            e.value,
                            on: _rooms.contains(e.key),
                            onTap: () => setState(
                              () => _rooms.contains(e.key)
                                  ? _rooms.remove(e.key)
                                  : _rooms.add(e.key),
                            ),
                          ),
                        RidiChip(
                          '나만 보기',
                          on: _rooms.isEmpty,
                          onTap: () => setState(_rooms.clear),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: RidiColors.panel,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: TextField(
                  controller: _controller,
                  maxLines: null,
                  expands: true,
                  autofocus: true,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  enableSuggestions: true,
                  autocorrect: true,
                  maxLength: 1500,
                  decoration: const InputDecoration.collapsed(
                    hintText: '',
                    hintStyle: RidiText.sub,
                  ),
                  style: RidiText.body.copyWith(
                    fontFamilyFallback: RidiText.koreanFallback,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ================= 독서노트 =================
/// 독서노트 열기. onGoto(페이지) — 항목을 누르면 뷰어가 그 페이지로 간다
Future<void> showRidiNoteDialog(
  BuildContext context, {
  required String bookId,
  ValueChanged<int>? onGoto,
}) => showDialog<void>(
  context: context,
  builder: (_) => _NoteDialog(bookId: bookId, onGoto: onGoto),
);

class _NoteDialog extends StatefulWidget {
  const _NoteDialog({required this.bookId, this.onGoto});

  final String bookId;
  final ValueChanged<int>? onGoto;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  int _tab = 0;
  int? _colorFilter;
  bool _edit = false;
  final _picked = <String>{};

  static const _tabs = ['전체', '형광펜', '메모', '책갈피'];

  /// 탭별 목록: 전체 / 형광펜(색 필터) / 메모 있는 것 / 책갈피
  List<RidiNote> _list(RidiStore store) {
    final all = store.notesOf(widget.bookId);
    return switch (_tab) {
      1 =>
        all
            .where(
              (n) =>
                  n.kind == NoteKind.highlight &&
                  (_colorFilter == null || n.colorIndex == _colorFilter),
            )
            .toList(),
      2 => all.where((n) => n.memo.isNotEmpty).toList(),
      3 => all.where((n) => n.kind == NoteKind.bookmark).toList(),
      _ => all,
    };
  }

  @override
  Widget build(BuildContext context) => ScreenTag(switch (_tab) {
    1 => 'RIDI_NOTE_02',
    2 => 'RIDI_NOTE_01 › 메모',
    3 => 'RIDI_NOTE_01 › 책갈피',
    _ => 'RIDI_NOTE_01',
  }, child: _screen(context));

  Widget _screen(BuildContext context) {
    final store = context.watch<RidiStore>();
    final book = store.book(widget.bookId);
    final items = _list(store);

    return RidiDialogFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RidiDialogHeader(
            left: _edit ? '취소' : '닫기',
            onLeft: () => _edit
                ? setState(() {
                    _edit = false;
                    _picked.clear();
                  })
                : Navigator.of(context).pop(),
            title: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('독서노트', style: RidiText.heading),
                SizedBox(width: 4),
                Icon(
                  Icons.arrow_drop_down_rounded,
                  size: 22,
                  color: RidiColors.ink,
                ),
              ],
            ),
            right: _edit
                ? (_picked.isEmpty ? '삭제' : '삭제 ${_picked.length}')
                : '편집',
            rightMuted: items.isEmpty || (_edit && _picked.isEmpty),
            onRight: items.isEmpty
                ? null
                : () async {
                    if (!_edit) {
                      setState(() => _edit = true);
                      return;
                    }
                    if (_picked.isEmpty) return;
                    final ok = await ridiConfirm(
                      context,
                      title: '${_picked.length}개를 지울까요?',
                      ok: '삭제',
                      danger: true,
                    );
                    if (!ok) return;
                    store.deleteNotes(_picked);
                    setState(() {
                      _picked.clear();
                      _edit = false;
                    });
                  },
          ),
          // ----- 탭 -----
          Container(
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: RidiColors.grayLight)),
            ),
            child: Row(
              children: [
                for (var i = 0; i < _tabs.length; i++)
                  Expanded(
                    child: InkWell(
                      onTap: () => setState(() {
                        _tab = i;
                        _colorFilter = null;
                        _picked.clear();
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: i == _tab
                                  ? RidiColors.ink
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                        child: Text(
                          _tabs[i],
                          textAlign: TextAlign.center,
                          style: i == _tab ? RidiText.tabOn : RidiText.tab,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // ----- 형광펜 색 필터 -----
          if (_tab == 1)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  InkWell(
                    onTap: () => setState(() => _colorFilter = null),
                    child: Text(
                      '전체',
                      style: _colorFilter == null
                          ? RidiText.bodyBold.copyWith(fontSize: 13)
                          : RidiText.sub,
                    ),
                  ),
                  const SizedBox(width: 20),
                  for (var c = 0; c < RidiColors.penColors.length; c++)
                    Padding(
                      padding: const EdgeInsets.only(right: 20),
                      child: InkWell(
                        onTap: () => setState(
                          () => _colorFilter = _colorFilter == c ? null : c,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: RidiColors.penColors[c],
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _colorFilter == c
                                  ? RidiColors.blue
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          // ----- 목록 -----
          Expanded(
            child: items.isEmpty
                ? RidiEmpty(
                    icon: _tab == 3
                        ? Icons.bookmark_border_rounded
                        : Icons.edit_outlined,
                    text: switch (_tab) {
                      1 => '아직 남겨진 형광펜이 없습니다.',
                      2 => '아직 남겨진 메모가 없습니다.',
                      3 => '아직 꽂은 책갈피가 없습니다.',
                      _ => '아직 남겨진 기록이 없습니다.',
                    },
                  )
                : ListView(
                    children: [
                      if (_tab == 0 && book != null)
                        Container(
                          color: RidiColors.panel,
                          padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                          child: Column(
                            children: [
                              Text(
                                book.title,
                                style: RidiText.title.copyWith(fontSize: 20),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                book.author,
                                style: RidiText.sub.copyWith(fontSize: 14),
                              ),
                              const SizedBox(height: 14),
                              const RidiCover(width: 96, height: 132),
                            ],
                          ),
                        ),
                      for (final chapter
                          in items.map((n) => n.chapter).toSet().toList()
                            ..sort()) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Text(
                            'Chapter ${chapter + 1}',
                            textAlign: TextAlign.center,
                            style: RidiText.sub.copyWith(fontSize: 15),
                          ),
                        ),
                        for (final n in items.where(
                          (e) => e.chapter == chapter,
                        ))
                          _Entry(
                            note: n,
                            edit: _edit,
                            picked: _picked.contains(n.id),
                            onPick: () => setState(
                              () => _picked.contains(n.id)
                                  ? _picked.remove(n.id)
                                  : _picked.add(n.id),
                            ),
                            onGoto: () {
                              Navigator.of(context).pop();
                              widget.onGoto?.call(n.page);
                            },
                          ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// 독서노트 항목 한 줄 — 색 점(책갈피는 리본) · 문구 · 메모 상자 · 페이지 | 날짜 | 공유한 방 · … 메뉴(RIDI_NOTE_03)
class _Entry extends StatelessWidget {
  const _Entry({
    required this.note,
    required this.edit,
    required this.picked,
    required this.onPick,
    required this.onGoto,
  });

  final RidiNote note;
  final bool edit;
  final bool picked;
  final VoidCallback onPick;
  final VoidCallback onGoto;

  @override
  Widget build(BuildContext context) {
    final store = context.read<RidiStore>();
    final bookmark = note.kind == NoteKind.bookmark;

    return InkWell(
      onTap: edit ? onPick : onGoto,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (edit)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Icon(
                      picked
                          ? Icons.check_circle_rounded
                          : Icons.circle_outlined,
                      size: 20,
                      color: picked ? RidiColors.ink : RidiColors.grayLight,
                    ),
                  ),
                if (bookmark)
                  const Icon(
                    Icons.bookmark_rounded,
                    size: 18,
                    color: RidiColors.red,
                  )
                else
                  RidiPenMark(
                    colorIndex: note.colorIndex,
                    underline: note.penStyle == PenStyle.underline,
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    note.phrase,
                    style: RidiText.body.copyWith(fontSize: 16),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (note.memo.isNotEmpty) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.only(left: 26),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: RidiColors.panel,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.push_pin_rounded,
                        size: 16,
                        color: RidiColors.ink,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          note.memo,
                          style: RidiText.sub.copyWith(color: RidiColors.text),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            Padding(
              padding: const EdgeInsets.only(left: 26),
              child: Row(
                children: [
                  Text(
                    '${note.page} 페이지',
                    style: RidiText.sub.copyWith(fontSize: 12),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      '|',
                      style: RidiText.sub.copyWith(color: RidiColors.grayLight),
                    ),
                  ),
                  Text(
                    note.dateLabel,
                    style: RidiText.sub.copyWith(fontSize: 12),
                  ),
                  if (store.sharedLabel(note) case final where?) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        '|',
                        style: RidiText.sub.copyWith(
                          color: RidiColors.grayLight,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.groups_2_outlined,
                      size: 14,
                      color: RidiColors.blue,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$where 공유',
                      style: RidiText.sub.copyWith(
                        fontSize: 12,
                        color: RidiColors.blue,
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (!edit)
                    PopupMenuButton<String>(
                      icon: const Icon(
                        Icons.more_horiz_rounded,
                        color: RidiColors.grayLight,
                      ),
                      position: PopupMenuPosition.under,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      color: Colors.white,
                      onSelected: (v) async {
                        final nav = Navigator.of(context);
                        if (v == 'delete') {
                          final ok = await ridiConfirm(
                            context,
                            title: '이 기록을 지울까요?',
                            ok: '삭제',
                            danger: true,
                          );
                          if (ok) store.deleteNotes([note.id]);
                        } else {
                          nav.pop();
                          await showRidiMemoDialog(
                            nav.context,
                            bookId: note.bookId,
                            chapter: note.chapter,
                            page: note.page,
                            line: note.line,
                            phrase: note.phrase,
                            note: note,
                          );
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'delete',
                          height: 56,
                          child: Center(
                            child: Text(
                              '삭제',
                              style: TextStyle(
                                fontFamily: RidiText.f,
                                fontSize: 17,
                                color: RidiColors.red,
                              ),
                            ),
                          ),
                        ),
                        PopupMenuDivider(),
                        PopupMenuItem(
                          value: 'edit',
                          height: 56,
                          child: Center(
                            child: Text(
                              '메모 수정',
                              style: TextStyle(
                                fontFamily: RidiText.f,
                                fontSize: 17,
                                color: RidiColors.blue,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            const Divider(),
          ],
        ),
      ),
    );
  }
}
