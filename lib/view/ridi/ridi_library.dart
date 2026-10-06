import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'ridi_data.dart';
import 'ridi_reader.dart';
import 'ridi_rooms.dart';
import 'reading_rooms_screen.dart';
import 'ridi_store.dart';
import 'ridi_theme.dart';
import 'ridi_widgets.dart';
import '../../widgets/screen_tag.dart';

/// 내 서재 탭 — RIDI_LIB_01 내 책장 · RIDI_ROOMS_01 교환독서(방 목록). 위 검은 알약으로 전환.
///
/// 내 책장: 책 행 → 이어보기로 뷰어(마지막 페이지). 편집 = 여러 권 골라 책장에서 빼기, 필터 = 전체/읽는 중/완결.
/// 교환독서: 방 카드 → 그 방에서 마지막 책 이어 읽기(방 메모가 보이는 뷰어), ⋯ → 방 메뉴(RIDI_ROOMS_02),
/// 코드로 입장(RIDI_ROOM_JOIN_01) · 방 만들기(RIDI_ROOM_CREATE_01). 편집 = 여러 방 나가기.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

/// 책장 필터 — 전체 / 읽는 중(완결 아님) / 완결
enum _Filter { all, reading, done }

class _LibraryScreenState extends State<LibraryScreen> {
  int _tab = 0; // 0 내 책장, 1 교환독서
  bool _edit = false;
  final _picked = <String>{};
  _Filter _filter = _Filter.all;

  /// 편집 모드 켜고 끄기 (고른 것은 비운다)
  void _toggleEdit() {
    setState(() {
      _edit = !_edit;
      _picked.clear();
    });
  }

  /// 필터 시트 (RIDI_LIB_01 › 필터)
  Future<void> _showFilter() async {
    final r = await showModalBottomSheet<_Filter>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (ctx) => ScreenTag(
        'RIDI_LIB_01 › 필터',
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: RidiColors.grayLight,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              for (final f in _Filter.values)
                ListTile(
                  title: Text(
                    const {
                      _Filter.all: '전체',
                      _Filter.reading: '읽는 중',
                      _Filter.done: '완결',
                    }[f]!,
                    style: f == _filter ? RidiText.bodyBold : RidiText.body,
                  ),
                  trailing: f == _filter
                      ? const Icon(Icons.check_rounded, color: RidiColors.ink)
                      : null,
                  onTap: () => Navigator.pop(ctx, f),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (r != null) setState(() => _filter = r);
  }

  /// 편집에서 고른 것 삭제 (확인 후) — 내 책장이면 책장에서 빼기(메모는 남음), 교환독서면 방 나가기
  Future<void> _deletePicked(RidiStore store) async {
    if (_picked.isEmpty) return;
    final ok = await ridiConfirm(
      context,
      title: _tab == 0
          ? '책 ${_picked.length}권을 책장에서 뺄까요?'
          : '방 ${_picked.length}개에서 나갈까요?',
      body: _tab == 0
          ? '메모와 형광펜은 남아 있어요.'
          : '코드가 있으면 다시 들어올 수 있어요. 방장인 방은 가장 먼저 들어온 사람이 방장이 되고, 나 혼자인 방은 사라져요.',
      ok: _tab == 0 ? '빼기' : '나가기',
      danger: true,
    );
    if (!ok) return;
    if (_tab == 0) {
      store.removeFromShelf(_picked);
    } else {
      for (final id in _picked) {
        store.leaveRoom(id);
      }
    }
    setState(() {
      _picked.clear();
      _edit = false;
    });
  }

  @override
  Widget build(BuildContext context) => ScreenTag(
    _tab == 0 ? 'RIDI_LIB_01' : 'RIDI_ROOMS_01',
    alignment: Alignment.topCenter,
    child: _screen(context),
  );

  Widget _screen(BuildContext context) {
    final store = context.watch<RidiStore>();
    final shelf = store.shelf.where((b) {
      if (_filter == _Filter.reading) return !b.done;
      if (_filter == _Filter.done) return b.done;
      return true;
    }).toList();
    final count = _tab == 0 ? shelf.length : store.rooms.length;

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        titleSpacing: 24,
        title: const Text(
          '모든 책장',
          style: TextStyle(
            fontFamily: RidiText.f,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                RidiPill(
                  '내 책장',
                  on: _tab == 0,
                  onTap: () => setState(() {
                    _tab = 0;
                    _edit = false;
                    _picked.clear();
                  }),
                ),
                const SizedBox(width: 12),
                RidiPill(
                  '교환독서',
                  on: false,
                  // The old tab was a prototype backed only by RidiStore.  It
                  // could never create a server room (or use the DB catalog),
                  // so every real entry point now uses the authenticated API.
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ReadingRoomsScreen(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Text('$count개', style: RidiText.sub),
                const SizedBox(width: 8),
                RidiOutlineButton(
                  _edit ? '완료' : '편집',
                  height: 32,
                  onTap: _toggleEdit,
                ),
                if (_edit) ...[
                  const SizedBox(width: 8),
                  RidiOutlineButton(
                    _tab == 0 ? '책장에서 빼기' : '방 나가기',
                    height: 32,
                    onTap: _picked.isEmpty ? null : () => _deletePicked(store),
                  ),
                ],
                const Spacer(),
                if (_tab == 0)
                  TextButton.icon(
                    onPressed: _showFilter,
                    style: TextButton.styleFrom(
                      foregroundColor: RidiColors.ink,
                    ),
                    icon: const Icon(Icons.tune_rounded, size: 20),
                    label: Text(
                      _filter == _Filter.all
                          ? '필터'
                          : const {
                              _Filter.reading: '읽는 중',
                              _Filter.done: '완결',
                            }[_filter]!,
                      style: const TextStyle(
                        fontFamily: RidiText.f,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  )
                else ...[
                  RidiOutlineButton(
                    '코드로 입장',
                    icon: Icons.login_rounded,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ReadingRoomsScreen(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  RidiButton(
                    '방 만들기',
                    icon: Icons.add_rounded,
                    height: 44,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ReadingRoomsScreen(),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _tab == 0 ? _shelfView(store, shelf) : _roomsView(store),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- 내 책장 ----------------
  /// 내 책장 목록 (필터 적용된 책들)
  Widget _shelfView(RidiStore store, List<RidiBook> shelf) {
    if (shelf.isEmpty) {
      return RidiEmpty(
        icon: Icons.menu_book_outlined,
        text: _filter == _Filter.all
            ? '책장이 비어 있어요\n홈 › 검색에서 책을 담아보세요'
            : '해당하는 책이 없어요',
        action: _filter == _Filter.all
            ? null
            : RidiOutlineButton(
                '필터 지우기',
                onTap: () => setState(() => _filter = _Filter.all),
              ),
      );
    }
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth > 900 ? 2 : 1;
        return GridView.count(
          crossAxisCount: cols,
          childAspectRatio: cols == 2 ? 5.2 : 3.4,
          crossAxisSpacing: 40,
          mainAxisSpacing: 16,
          children: [
            for (final b in shelf)
              _BookRow(
                book: b,
                edit: _edit,
                picked: _picked.contains(b.id),
                onPick: () => setState(
                  () => _picked.contains(b.id)
                      ? _picked.remove(b.id)
                      : _picked.add(b.id),
                ),
                onOpen: () {
                  store.openBook(b.id);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => RidiReaderScreen(bookId: b.id),
                    ),
                  );
                },
              ),
          ],
        );
      },
    );
  }

  // ---------------- 교환독서 (방 목록) ----------------
  /// 내가 속한 방 카드 목록
  Widget _roomsView(RidiStore store) {
    if (store.rooms.isEmpty) {
      return RidiEmpty(
        icon: Icons.groups_2_outlined,
        text: '아직 독서방이 없어요\n방을 만들어 코드를 친구에게 알려주세요',
        action: RidiButton(
          '방 만들기',
          icon: Icons.add_rounded,
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const ReadingRoomsScreen())),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth > 900 ? 2 : 1;
        return GridView.count(
          crossAxisCount: cols,
          childAspectRatio: cols == 2 ? 2.9 : 2.2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          children: [
            for (final r in store.rooms)
              _RoomCard(
                room: r,
                edit: _edit,
                picked: _picked.contains(r.id),
                onPick: () => setState(
                  () => _picked.contains(r.id)
                      ? _picked.remove(r.id)
                      : _picked.add(r.id),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ---------------- 책 한 줄 ----------------
/// 표지 · 완결 배지 · 제목 · 마지막 열람 · 안 본 이야기(방 새 메모) 수 · 이어보기 · 진행바.
/// 편집 모드면 누를 때 선택(onPick), 아니면 뷰어로(onOpen).
class _BookRow extends StatelessWidget {
  const _BookRow({
    required this.book,
    required this.edit,
    required this.picked,
    required this.onPick,
    required this.onOpen,
  });

  final RidiBook book;
  final bool edit;
  final bool picked;
  final VoidCallback onPick;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: edit ? onPick : onOpen,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (edit)
            Padding(
              padding: const EdgeInsets.only(top: 34, right: 8),
              child: Icon(
                picked ? Icons.check_circle_rounded : Icons.circle_outlined,
                color: picked ? RidiColors.ink : RidiColors.grayLight,
              ),
            ),
          const RidiCover(),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 14),
                Row(
                  children: [
                    if (book.done)
                      Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF555555),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: const Text(
                          '완결',
                          style: TextStyle(
                            fontFamily: RidiText.f,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    Flexible(
                      child: Text(
                        book.title,
                        style: RidiText.bodyBold,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(book.lastOpened ?? '아직 안 읽음', style: RidiText.sub),
                const SizedBox(height: 4),
                Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(text: '안 본 이야기 ', style: RidiText.body),
                      TextSpan(
                        text: '${book.unread}',
                        style: RidiText.body.copyWith(color: RidiColors.blue),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const SizedBox(height: 18),
              InkWell(
                onTap: edit ? onPick : onOpen,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '이어보기',
                      style: TextStyle(
                        fontFamily: RidiText.f,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: RidiColors.ink,
                      ),
                    ),
                    SizedBox(width: 4),
                    Icon(Icons.chevron_right_rounded, size: 18),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: 64,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: (book.page / ridiTotalPages).clamp(0.0, 1.0),
                    minHeight: 3,
                    backgroundColor: RidiColors.grayLight,
                    color: RidiColors.blue,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text('${book.chapters}장', style: RidiText.sub),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------- 방 카드 ----------------
/// 방 이름 · 코드 · 함께 읽는 책 · 멤버 얼굴 · AI 친구. 카드 = 이어 읽기, ⋯ = 방 메뉴
class _RoomCard extends StatelessWidget {
  const _RoomCard({
    required this.room,
    required this.edit,
    required this.picked,
    required this.onPick,
  });

  final RidiRoom room;
  final bool edit;
  final bool picked;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final store = context.read<RidiStore>();
    final books = store.roomBooks(room);
    final next = store.roomNextBook(room);
    final ai = store.persona(room.personaId);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: edit
            ? onPick
            : next == null
            ? () => showRoomSheet(context, room)
            : () {
                store.openBook(next.id, roomId: room.id);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        RidiReaderScreen(bookId: next.id, roomId: room.id),
                  ),
                );
              },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(
              color: picked ? RidiColors.ink : RidiColors.grayLight,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (edit)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Icon(
                        picked
                            ? Icons.check_circle_rounded
                            : Icons.circle_outlined,
                        size: 20,
                        color: picked ? RidiColors.ink : RidiColors.grayLight,
                      ),
                    ),
                  Expanded(
                    child: Text(
                      room.name,
                      style: RidiText.title.copyWith(fontSize: 20),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: RidiColors.panel,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.vpn_key_rounded,
                          size: 13,
                          color: RidiColors.gray,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          room.code,
                          style: RidiText.sub.copyWith(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '방 정보',
                    icon: const Icon(
                      Icons.more_horiz_rounded,
                      color: RidiColors.gray,
                    ),
                    onPressed: () => showRoomSheet(context, room),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                books.isEmpty
                    ? '아직 책이 없어요'
                    : books.map((b) => b.title).join(' · '),
                style: RidiText.sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const Spacer(),
              Row(
                children: [
                  SizedBox(
                    width: 52,
                    height: 30,
                    child: Stack(
                      children: [
                        for (var i = 0; i < room.members.take(3).length; i++)
                          Positioned(
                            left: i * 16.0,
                            child: RidiAvatar(
                              label: room.members[i].name,
                              ai: room.members[i].ai,
                              size: 30,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${room.humanCount}명${ai != null ? " · ${ai.name}" : ""}',
                    style: RidiText.sub,
                  ),
                  const Spacer(),
                  if (next != null)
                    Flexible(
                      child: Text(
                        '${next.title} 이어보기  ›',
                        style: const TextStyle(
                          fontFamily: RidiText.f,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: RidiColors.ink,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    )
                  else
                    const Text(
                      '책 고르기  ›',
                      style: TextStyle(
                        fontFamily: RidiText.f,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: RidiColors.ink,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
