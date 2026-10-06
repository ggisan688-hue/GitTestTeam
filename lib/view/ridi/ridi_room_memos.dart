import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'ridi_store.dart';
import 'ridi_theme.dart';
import 'ridi_widgets.dart';
import '../../widgets/screen_tag.dart';

/// RIDI_ROOM_MEMO_01 방 메모 · RIDI_COMMENT_01 댓글 — UC-05 책 읽기 ⊃ 메모 공유
/// 방에서 책을 읽을 때 같은 방 멤버·AI 독서 친구가 남긴 메모를 보고 댓글을 단다.
/// 스포일러 잠금이 켜진 방이면, 내가 아직 안 읽은 장의 메모는 내용을 가린다.

// ================= 방 메모 =================
/// [chapter]·[line] 을 주면 그 문장의 메모만, 안 주면 이 책의 방 메모 전체.
/// [onGoto] 는 '이 문장으로' 를 눌렀을 때 (장, 문장).
Future<void> showRoomMemoDialog(
  BuildContext context, {
  required String roomId,
  required String bookId,
  int? chapter,
  int? line,
  void Function(int chapter, int line)? onGoto,
}) =>
    showDialog<void>(
      context: context,
      builder: (_) => _RoomMemoDialog(roomId: roomId, bookId: bookId, chapter: chapter, line: line, onGoto: onGoto),
    );

class _RoomMemoDialog extends StatefulWidget {
  const _RoomMemoDialog({required this.roomId, required this.bookId, this.chapter, this.line, this.onGoto});

  final String roomId;
  final String bookId;
  final int? chapter;
  final int? line;
  final void Function(int chapter, int line)? onGoto;

  @override
  State<_RoomMemoDialog> createState() => _RoomMemoDialogState();
}

class _RoomMemoDialogState extends State<_RoomMemoDialog> {
  String? _who; // null = 전체, '' = 나, 그 외 = 멤버 이름
  late bool _oneLine = widget.chapter != null && widget.line != null;

  @override
  Widget build(BuildContext context) => ScreenTag('RIDI_ROOM_MEMO_01', child: _screen(context));

  Widget _screen(BuildContext context) {
    final store = context.watch<RidiStore>();
    final room = store.room(widget.roomId);
    if (room == null) return const SizedBox.shrink();

    // 이 책의 방 메모 → (말풍선에서 열었으면) 그 문장만 → (칩을 골랐으면) 그 사람 것만
    var items = store.roomNotes(widget.roomId, widget.bookId);
    if (_oneLine) items = items.where((n) => n.chapter == widget.chapter && n.line == widget.line).toList();
    final authors = <String>{for (final n in items) if (!n.mine) n.author}.toList();
    if (_who != null) items = items.where((n) => _who!.isEmpty ? n.mine : (!n.mine && n.author == _who)).toList();

    return RidiDialogFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RidiDialogHeader(
            left: '닫기',
            onLeft: () => Navigator.of(context).pop(),
            title: Text.rich(TextSpan(children: [
              const TextSpan(text: '방 메모 ', style: RidiText.heading),
              TextSpan(text: '${items.length}', style: RidiText.sub),
            ])),
          ),
          const Divider(height: 1),
          // ----- 방 이름 · 스포일러 안내 -----
          Container(
            color: RidiColors.panel,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: Row(children: [
              const Icon(Icons.groups_2_outlined, size: 18, color: RidiColors.gray),
              const SizedBox(width: 8),
              Text(room.name, style: RidiText.bodyBold.copyWith(fontSize: 14)),
              const Spacer(),
              Icon(room.spoilerLock ? Icons.lock_outline_rounded : Icons.lock_open_rounded, size: 16, color: RidiColors.gray),
              const SizedBox(width: 4),
              Text(room.spoilerLock ? '스포일러 잠금 · 읽은 장까지만 보여요' : '스포일러 잠금 꺼짐', style: RidiText.sub),
            ]),
          ),
          // ----- 이 문장만 볼 때: 문장 인용 -----
          if (_oneLine)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text('Chapter ${widget.chapter! + 1} · 문장 ${widget.line! + 1}', style: RidiText.sub),
                  const Spacer(),
                  InkWell(
                    onTap: () => setState(() => _oneLine = false),
                    child: const Text('이 책 방 메모 전체  ›', style: TextStyle(fontFamily: RidiText.f, fontSize: 13, fontWeight: FontWeight.w700, color: RidiColors.ink)),
                  ),
                ]),
                const SizedBox(height: 8),
                _Quote(text: ridiSentence(widget.chapter!, widget.line!), maxLines: 3),
              ]),
            ),
          // ----- 누구 메모만 -----
          SizedBox(
            height: 60,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              children: [
                RidiChip('전체', on: _who == null, onTap: () => setState(() => _who = null)),
                const SizedBox(width: 8),
                RidiChip('나', on: _who == '', onTap: () => setState(() => _who = '')),
                for (final a in authors) ...[
                  const SizedBox(width: 8),
                  RidiChip(a, on: _who == a, onTap: () => setState(() => _who = a)),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          // ----- 목록 -----
          Expanded(
            child: items.isEmpty
                ? RidiEmpty(
                    icon: Icons.forum_outlined,
                    text: _oneLine ? '이 문장에는 아직 방 메모가 없어요' : '아직 이 방에 남겨진 메모가 없어요\n문장을 길게 눌러 첫 메모를 남겨보세요',
                  )
                : ListView(
                    children: [
                      for (final chapter in items.map((n) => n.chapter).toSet().toList()..sort()) ...[
                        if (!_oneLine)
                          Padding(
                            padding: const EdgeInsets.only(top: 20, bottom: 4),
                            child: Text('Chapter ${chapter + 1}', textAlign: TextAlign.center, style: RidiText.sub.copyWith(fontSize: 15)),
                          ),
                        for (final n in items.where((e) => e.chapter == chapter))
                          _RoomMemoTile(
                            roomId: widget.roomId,
                            note: n,
                            showQuote: !_oneLine,
                            onGoto: widget.onGoto == null
                                ? null
                                : () {
                                    Navigator.of(context).pop();
                                    widget.onGoto!(n.chapter, n.line);
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

/// 방 메모 한 건 — 이름 · 나/AI 배지 · 시간 · 형광펜 색 · 인용 문장 · 메모 · 댓글 N · 이 문장으로.
/// 스포일러면 인용 문장까지 가리고 자물쇠 문구, 댓글도 못 연다.
class _RoomMemoTile extends StatelessWidget {
  const _RoomMemoTile({required this.roomId, required this.note, required this.showQuote, this.onGoto});

  /// 보고 있는 방 — 스포일러는 이 방의 잠금 설정으로 판단 (메모가 여러 방에 공유될 수 있음)
  final String roomId;
  final RidiNote note;
  final bool showQuote;
  final VoidCallback? onGoto;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<RidiStore>();
    final spoiler = store.isSpoiler(note, roomId);
    final count = store.commentsOf(note.id).length;
    final name = store.authorOf(note);

    return InkWell(
      onTap: spoiler ? () => ridiToast(context, '${note.chapter + 1}장까지 읽으면 보여요') : () => showCommentsDialog(context, noteId: note.id),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            RidiAvatar(label: name, ai: note.ai, size: 32),
            const SizedBox(width: 10),
            Text(name, style: RidiText.bodyBold.copyWith(fontSize: 14)),
            if (note.mine) const _Badge('나'),
            if (note.ai) const _Badge('AI', purple: true),
            const SizedBox(width: 8),
            Text(ridiAgo(note.createdAt), style: RidiText.sub.copyWith(fontSize: 12)),
            const Spacer(),
            RidiPenMark(colorIndex: note.colorIndex, underline: note.penStyle == PenStyle.underline, size: 12),
          ]),
          if (showQuote && !spoiler) ...[
            const SizedBox(height: 10),
            Padding(padding: const EdgeInsets.only(left: 42), child: _Quote(text: ridiSentence(note.chapter, note.line), maxLines: 2)),
          ],
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(left: 42),
            child: spoiler
                ? Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(color: RidiColors.panel, borderRadius: BorderRadius.circular(4)),
                    child: Row(children: [
                      const Icon(Icons.lock_outline_rounded, size: 16, color: RidiColors.gray),
                      const SizedBox(width: 8),
                      Expanded(child: Text('아직 안 읽은 부분의 메모예요 · ${note.chapter + 1}장까지 읽으면 보여요', style: RidiText.sub)),
                    ]),
                  )
                : Text(note.memo.isEmpty ? '(형광펜만 남겼어요)' : note.memo, style: note.memo.isEmpty ? RidiText.sub : RidiText.body),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 30),
            child: Row(children: [
              TextButton.icon(
                onPressed: spoiler ? null : () => showCommentsDialog(context, noteId: note.id),
                icon: Icon(Icons.mode_comment_outlined, size: 16, color: spoiler ? RidiColors.grayLight : RidiColors.gray),
                label: Text(count == 0 ? '댓글 쓰기' : '댓글 $count', style: RidiText.sub.copyWith(color: spoiler ? RidiColors.grayLight : RidiColors.text)),
              ),
              const Spacer(),
              if (onGoto != null)
                TextButton(
                  onPressed: onGoto,
                  child: const Text('이 문장으로  ›', style: TextStyle(fontFamily: RidiText.f, fontSize: 13, color: RidiColors.gray)),
                ),
            ]),
          ),
          const Divider(height: 1),
        ]),
      ),
    );
  }
}

// ================= 댓글 =================
/// 댓글 창 열기 (방 메모 항목 · 댓글 알림에서)
Future<void> showCommentsDialog(BuildContext context, {required String noteId}) => showDialog<void>(
      context: context,
      builder: (_) => _CommentsDialog(noteId: noteId),
    );

class _CommentsDialog extends StatefulWidget {
  const _CommentsDialog({required this.noteId});

  final String noteId;

  @override
  State<_CommentsDialog> createState() => _CommentsDialogState();
}

class _CommentsDialogState extends State<_CommentsDialog> {
  final _text = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// 등록: 빈 글은 무시, 올린 뒤 입력칸을 비우고 맨 아래로 스크롤
  void _send(RidiStore store) {
    if (store.addComment(widget.noteId, _text.text) == null) return;
    _text.clear();
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    });
  }

  @override
  Widget build(BuildContext context) => ScreenTag('RIDI_COMMENT_01', child: _screen(context));

  Widget _screen(BuildContext context) {
    final store = context.watch<RidiStore>();
    final note = store.note(widget.noteId);
    if (note == null) {
      return RidiDialogFrame(
        height: 300,
        child: RidiEmpty(icon: Icons.delete_outline_rounded, text: '지워진 메모예요', action: RidiOutlineButton('닫기', onTap: () => Navigator.of(context).pop())),
      );
    }
    final list = store.commentsOf(note.id);
    final name = store.authorOf(note);
    final roomName = store.sharedLabel(note);

    return RidiDialogFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RidiDialogHeader(
            left: '닫기',
            onLeft: () => Navigator.of(context).pop(),
            title: Text.rich(TextSpan(children: [
              const TextSpan(text: '댓글 ', style: RidiText.heading),
              TextSpan(text: '${list.length}', style: RidiText.sub),
            ])),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              children: [
                // ----- 원래 메모 -----
                Row(children: [
                  RidiAvatar(label: name, ai: note.ai, size: 36),
                  const SizedBox(width: 10),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Text(name, style: RidiText.bodyBold.copyWith(fontSize: 15)),
                      if (note.ai) const _Badge('AI', purple: true),
                    ]),
                    Text([?roomName, 'Chapter ${note.chapter + 1} · 문장 ${note.line + 1}', ridiAgo(note.createdAt)].join('  ·  '), style: RidiText.sub.copyWith(fontSize: 12)),
                  ]),
                ]),
                const SizedBox(height: 12),
                _Quote(text: ridiSentence(note.chapter, note.line), maxLines: 3, color: RidiColors.penColors[note.colorIndex]),
                const SizedBox(height: 10),
                Text(note.memo.isEmpty ? '(형광펜만 남겼어요)' : note.memo, style: RidiText.body.copyWith(fontSize: 16)),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 8),
                if (list.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Text('첫 댓글을 남겨보세요', textAlign: TextAlign.center, style: RidiText.sub),
                  ),
                for (final c in list) _CommentRow(comment: c),
              ],
            ),
          ),
          // ----- 입력 -----
          Container(
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: RidiColors.grayLight))),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Row(children: [
              Expanded(
                child: RidiInput(
                  controller: _text,
                  hint: '댓글을 남겨보세요',
                  maxLength: 300,
                  onSubmitted: (_) => _send(store),
                ),
              ),
              const SizedBox(width: 10),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _text,
                builder: (context, value, child) => Opacity(
                  opacity: value.text.trim().isEmpty ? 0.35 : 1,
                  child: child,
                ),
                child: RidiButton('등록', height: 48, onTap: () => _send(store)),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

/// 댓글 한 줄 — 이름 · 시간 · 내용. 내 댓글이면 × 로 지우기(확인 후)
class _CommentRow extends StatelessWidget {
  const _CommentRow({required this.comment});

  final RidiComment comment;

  @override
  Widget build(BuildContext context) {
    final store = context.read<RidiStore>();
    final name = store.commentAuthor(comment);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        RidiAvatar(label: name, ai: comment.ai, size: 30),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(name, style: RidiText.bodyBold.copyWith(fontSize: 13)),
              if (comment.mine) const _Badge('나'),
              const SizedBox(width: 8),
              Text(ridiAgo(comment.createdAt), style: RidiText.sub.copyWith(fontSize: 12)),
            ]),
            const SizedBox(height: 4),
            Text(comment.text, style: RidiText.body),
          ]),
        ),
        if (comment.mine)
          IconButton(
            tooltip: '댓글 지우기',
            icon: const Icon(Icons.close_rounded, size: 18, color: RidiColors.gray),
            onPressed: () async {
              final ok = await ridiConfirm(context, title: '댓글을 지울까요?', ok: '삭제', danger: true);
              if (ok) store.deleteComment(comment.id);
            },
          ),
      ]),
    );
  }
}

// ---------------- 작은 부품 ----------------
/// 인용 문장 (왼쪽 띠 색 = 형광펜 색)
class _Quote extends StatelessWidget {
  const _Quote({required this.text, this.maxLines = 2, this.color = RidiColors.grayLight});

  final String text;
  final int maxLines;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 12),
      decoration: BoxDecoration(border: Border(left: BorderSide(color: color, width: 3))),
      child: Text(text, maxLines: maxLines, overflow: TextOverflow.ellipsis, style: RidiText.sub.copyWith(fontSize: 14, color: RidiColors.text, fontFamily: 'NotoSerifKR')),
    );
  }
}

/// 이름 옆 작은 배지 — 나 / AI(보라)
class _Badge extends StatelessWidget {
  const _Badge(this.label, {this.purple = false});

  final String label;
  final bool purple;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: purple ? const Color(0xFFEDE8F6) : RidiColors.panel,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: TextStyle(fontFamily: RidiText.f, fontSize: 11, fontWeight: FontWeight.w700, color: purple ? const Color(0xFF7A5FB0) : RidiColors.gray)),
    );
  }
}
