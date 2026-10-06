import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../model/book.dart';
import '../../model/room.dart';
import '../../theme/app_theme.dart';
import '../../viewmodel/auth_viewmodel.dart';
import '../../viewmodel/reading_viewmodel.dart';
import '../../viewmodel/room_viewmodel.dart';
import '../../widgets/app_card.dart';
import '../../widgets/buttons.dart';
import '../../widgets/screen_tag.dart';
import '../home/home_screen.dart';
import 'room_sheets.dart';
import 'room_widgets.dart';

/// 독서방 하나: 함께 읽는 책 · 멤버 · AI 친구 · 방 코드
class RoomScreen extends StatelessWidget {
  const RoomScreen({super.key});

  Future<void> _read(BuildContext context, Room room, Book book) async {
    final rooms = context.read<RoomViewModel>();
    final reading = context.read<ReadingViewModel>();
    await rooms.markOpened(room, book.id);
    if (!context.mounted) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HomeScreen()));
    await reading.open(book);
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<RoomViewModel>();
    final room = vm.current;
    if (room == null) {
      return const Scaffold(body: Center(child: Text('방을 찾을 수 없어요', style: AppText.labelMuted)));
    }
    final me = context.watch<AuthViewModel>().member;
    final books = vm.booksOf(room);
    final ai = vm.personaIn(room);
    final next = vm.continueBookOf(room);
    final isOwner = me != null && room.isOwner(me.id);

    return ScreenTag('S20', child: Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(room.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          Text('${room.humanCount}명 · 책 ${books.length}권', style: AppText.caption),
        ]),
        actions: [
          PopupMenuButton<String>(
            tooltip: '방 설정',
            icon: const Icon(Icons.more_horiz_rounded, size: 26, color: AppColors.ink),
            onSelected: (v) async {
              switch (v) {
                case 'rename':
                  final name = await showRenameRoomSheet(context, room);
                  if (name != null && context.mounted) await vm.rename(room, name);
                case 'persona':
                  await showPersonaSheet(context, room);
                case 'leave':
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: Text(isOwner ? '방을 닫을까요?' : '방에서 나갈까요?', style: AppText.title),
                      content: Text(isOwner ? '이 기기에서 방이 사라져요. 멤버들의 메모는 남아 있어요.' : '언제든 코드로 다시 들어올 수 있어요.', style: AppText.body),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
                        TextButton(onPressed: () => Navigator.pop(context, true), child: Text(isOwner ? '닫기' : '나가기')),
                      ],
                    ),
                  );
                  if (ok == true && context.mounted) {
                    await vm.leave(room);
                    if (context.mounted) Navigator.of(context).pop();
                  }
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'rename', child: Text('방 이름 바꾸기', style: AppText.label)),
              PopupMenuItem(value: 'persona', child: Text('AI 독서 친구 바꾸기', style: AppText.label)),
              const PopupMenuDivider(),
              PopupMenuItem(value: 'leave', child: Text(isOwner ? '방 닫기' : '방 나가기', style: AppText.label.copyWith(color: AppColors.newBadge))),
            ],
          ),
          const SizedBox(width: AppSpace.sm),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.sm, AppSpace.lg, AppSpace.xxl),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ----- 초대 + 이어 읽기 -----
                AreaTag('S20.1', child: AppCard(
                  padding: const EdgeInsets.all(AppSpace.xl),
                  child: LayoutBuilder(builder: (context, c) {
                    final wide = c.maxWidth > 620;
                    final invite = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      const Text('방 코드', style: AppText.caption),
                      const SizedBox(height: AppSpace.xs),
                      RoomCodeChip(room.code, large: true),
                      const SizedBox(height: AppSpace.sm),
                      const Text('친구가 이 코드로 들어오면 서로의 문장 메모가 보여요', style: AppText.caption),
                    ]);
                    final cta = next == null
                        ? AppButton.primary('책 고르기', icon: Icons.add_rounded, onPressed: () => _addBooks(context, room))
                        : AppButton.primary('${next.title} 이어 읽기', icon: Icons.menu_book_rounded, onPressed: () => _read(context, room, next));
                    return wide
                        ? Row(children: [Expanded(child: invite), const SizedBox(width: AppSpace.lg), cta])
                        : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [invite, const SizedBox(height: AppSpace.lg), cta]);
                  }),
                )),
                const SizedBox(height: AppSpace.lg),

                // ----- 책 -----
                AreaTag('S20.2', child: AppCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SectionTitle('함께 읽는 책', hint: books.isEmpty ? '이 방에서 읽을 책을 골라요' : '${books.length}권 · 누르면 이어서 읽어요',
                        trailing: AppButton('책 추가', icon: Icons.add_rounded, compact: true, onPressed: () => _addBooks(context, room))),
                    if (books.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
                        child: Row(children: [
                          const Expanded(child: Text('아직 책이 없어요. 첫 책을 골라 함께 읽어보세요.', style: AppText.labelMuted)),
                          AppButton.primary('책 고르기', onPressed: () => _addBooks(context, room)),
                        ]),
                      ),
                    for (final b in books)
                      _BookRow(book: b, current: b.id == next?.id, onRead: () => _read(context, room, b), onRemove: () => vm.removeBook(room, b.id)),
                  ]),
                )),
                const SizedBox(height: AppSpace.lg),

                // ----- 멤버 + AI -----
                AreaTag('S20.3', child: AppCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SectionTitle('멤버', hint: '${room.humanCount}명${ai != null ? " + AI 독서 친구" : ""}'),
                    for (final m in room.members.where((m) => !m.ai))
                      _MemberRow(member: m, badge: m.memberId == room.ownerId ? '방장' : (m.memberId == me?.id ? '나' : null)),
                    const Divider(height: AppSpace.xl),
                    Row(children: [
                      Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: ai == null ? AppColors.codeBg : const Color(0xFFEDE8F6), borderRadius: BorderRadius.circular(AppTheme.radiusControl)),
                        child: ai == null ? const Icon(Icons.smart_toy_outlined, color: AppColors.muted) : Text(ai.avatar, style: const TextStyle(fontSize: 24)),
                      ),
                      const SizedBox(width: AppSpace.md),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(ai == null ? 'AI 독서 친구 없음' : ai.name, style: AppText.label),
                          Text(ai == null ? '캐릭터를 고르면 방에서 먼저 메모와 질문을 남겨요' : ai.intro, style: AppText.caption, maxLines: 2, overflow: TextOverflow.ellipsis),
                        ]),
                      ),
                      const SizedBox(width: AppSpace.sm),
                      AppButton(ai == null ? '고르기' : '바꾸기', compact: true, kind: ai == null ? AppButtonKind.primary : AppButtonKind.secondary,
                          onPressed: () => showPersonaSheet(context, room)),
                    ]),
                  ]),
                )),
              ],
            ),
          ),
        ),
      ),
    ));
  }

  Future<void> _addBooks(BuildContext context, Room room) async {
    final ids = await showAddBooksSheet(context, room);
    if (ids != null && ids.isNotEmpty && context.mounted) {
      await context.read<RoomViewModel>().addBooks(room, ids);
    }
  }
}

class _BookRow extends StatelessWidget {
  const _BookRow({required this.book, required this.current, required this.onRead, required this.onRemove});

  final Book book;
  final bool current;
  final VoidCallback onRead;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: current ? AppColors.accentSoft.withValues(alpha: 0.5) : AppColors.sceneBg,
      borderRadius: BorderRadius.circular(AppTheme.radiusControl),
      child: InkWell(
        onTap: onRead,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        child: Container(
          margin: const EdgeInsets.only(bottom: AppSpace.sm),
          padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.xs, AppSpace.sm),
          decoration: BoxDecoration(
            border: Border.all(color: current ? AppColors.accentSoft : AppColors.line),
            borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          ),
          child: Row(children: [
            Container(
              width: 36,
              height: 48,
              decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(6), border: Border.all(color: AppColors.line)),
              child: const Icon(Icons.menu_book_rounded, color: AppColors.accent, size: 18),
            ),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(book.title, style: AppText.heading, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text('${book.author ?? ''} · ${book.chapterCount}장', style: AppText.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
            if (current) const StatusBadge('읽는 중', icon: Icons.bookmark_outline_rounded),
            const SizedBox(width: AppSpace.xs),
            IconButton(tooltip: '방에서 빼기', icon: const Icon(Icons.close_rounded, size: 20, color: AppColors.muted), onPressed: onRemove),
          ]),
        ),
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.member, this.badge});

  final RoomMember member;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Row(children: [
        MemberAvatar(member, size: 36),
        const SizedBox(width: AppSpace.md),
        Expanded(child: Text(member.name, style: AppText.label)),
        if (badge != null) StatusBadge(badge!, tone: badge == '방장' ? StatusTone.accent : StatusTone.neutral),
      ]),
    );
  }
}
