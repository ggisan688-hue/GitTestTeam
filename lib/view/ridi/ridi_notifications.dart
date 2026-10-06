import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'ridi_reader.dart';
import 'ridi_room_memos.dart';
import 'ridi_store.dart';
import 'ridi_theme.dart';
import 'ridi_widgets.dart';
import '../../widgets/screen_tag.dart';

/// RIDI_NOTI_01 알림 · RIDI_NOTI_SET_01 알림 설정 — UC-06
/// 알림 종류: ai(방 AI 친구가 메모) · room(새 멤버) · comment(내 메모에 댓글). 안 읽은 것은 굵게 + 빨간 점.
/// 탭: 전체 / 보관함. 알림을 왼쪽으로 밀면 [보관][삭제] (보관함에서는 [되돌리기][삭제]). 지우면 스낵바로 되돌리기.
/// 서버: GET /api/notifications, 읽음 POST …/{id}/read · …/read-all, 보관 POST/DELETE …/{id}/archive, 삭제 DELETE …/{id},
/// 설정 GET/PUT /api/me/notification-settings
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _archive = false; // false = 전체, true = 보관함

  @override
  Widget build(BuildContext context) => ScreenTag('RIDI_NOTI_01', alignment: Alignment.topCenter, child: _screen(context));

  /// 지우고 스낵바에 되돌리기
  void _delete(RidiStore store, RidiNotification n) {
    final removed = store.deleteNotification(n.id);
    if (removed == null) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: const Text('알림을 지웠어요'),
        duration: const Duration(seconds: 3),
        persist: false, // 되돌리기 버튼이 있어도 3초 뒤 사라지게
        action: SnackBarAction(label: '되돌리기', onPressed: () => store.restoreNotification(removed.$1, removed.$2)),
      ));
  }

  Widget _tab(String label, bool on, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 20),
        padding: const EdgeInsets.fromLTRB(2, 12, 2, 10),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: on ? RidiColors.ink : Colors.transparent, width: 2))),
        child: Text(label, style: on ? RidiText.tabOn : RidiText.tab),
      ),
    );
  }

  Widget _screen(BuildContext context) {
    final store = context.watch<RidiStore>();
    final items = store.notifications.where((n) => n.archived == _archive).toList();
    final archivedCount = store.notifications.where((n) => n.archived).length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('알림'),
        actions: [
          if (store.unreadCount() > 0)
            TextButton(
              onPressed: store.markAllRead,
              child: const Text('모두 읽음', style: TextStyle(fontFamily: RidiText.f, fontSize: 14, fontWeight: FontWeight.w700, color: RidiColors.ink)),
            ),
          IconButton(
            icon: const Icon(Icons.settings_outlined, size: 26),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotiSettingsScreen())),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: RidiColors.grayLight))),
            padding: const EdgeInsets.only(left: 16),
            child: Row(children: [
              _tab('전체', !_archive, () => setState(() => _archive = false)),
              _tab(archivedCount == 0 ? '보관함' : '보관함 $archivedCount', _archive, () => setState(() => _archive = true)),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(right: 20),
                child: Text('왼쪽으로 밀면 ${_archive ? '되돌리기' : '보관'} · 삭제', style: RidiText.sub.copyWith(fontSize: 12)),
              ),
            ]),
          ),
          Expanded(
            child: items.isEmpty
                ? RidiEmpty(icon: _archive ? Icons.inventory_2_outlined : Icons.notifications_none_rounded, text: _archive ? '보관한 알림이 없어요' : '새 알림이 없어요')
                : ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const Divider(height: 1, indent: 16, endIndent: 16),
                    itemBuilder: (_, i) {
                      final n = items[i];
                      return RidiSwipeActions(
                        key: ValueKey(n.id),
                        actions: [
                          if (_archive)
                            RidiSwipeAction(label: '되돌리기', icon: Icons.unarchive_outlined, color: RidiColors.gray, onTap: () => store.unarchiveNotification(n.id))
                          else
                            RidiSwipeAction(label: '보관', icon: Icons.archive_outlined, color: RidiColors.gray, onTap: () {
                              store.archiveNotification(n.id);
                              ridiToast(context, '보관함으로 옮겼어요');
                            }),
                          RidiSwipeAction(label: '삭제', icon: Icons.delete_outline_rounded, color: RidiColors.red, onTap: () => _delete(store, n)),
                        ],
                        child: _NotiTile(n: n, onTap: () => _open(context, store, n)),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// 알림 한 줄 — 종류 아이콘 · 제목(안 읽었으면 굵게) · 내용 · 시간 · 빨간 점
class _NotiTile extends StatelessWidget {
  const _NotiTile({required this.n, required this.onTap});

  final RidiNotification n;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 66,
              height: 66,
              decoration: BoxDecoration(
                color: switch (n.kind) { 'ai' => const Color(0xFF7B61FF), 'room' => const Color(0xFF1F8CE6), _ => const Color(0xFF4CAF7D) },
                shape: BoxShape.circle,
              ),
              child: Icon(
                switch (n.kind) { 'ai' => Icons.smart_toy_outlined, 'room' => Icons.groups_2_outlined, _ => Icons.mode_comment_outlined },
                color: Colors.white,
                size: 30,
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const SizedBox(height: 6),
                Text(n.title, style: n.read ? RidiText.body : RidiText.bodyBold),
                const SizedBox(height: 4),
                Text(n.body, style: RidiText.body),
                const SizedBox(height: 6),
                Text(n.time, style: RidiText.sub),
              ]),
            ),
            if (!n.read) const Padding(padding: EdgeInsets.only(top: 12), child: CircleAvatar(radius: 4, backgroundColor: RidiColors.red)),
          ],
        ),
      ),
    );
  }
}

/// 알림 종류별 토글 5개 — 누르면 바로 저장(store.setNoti)
class NotiSettingsScreen extends StatelessWidget {
  const NotiSettingsScreen({super.key});

  static const _subs = {
    '방 메모 알림': '같은 방 멤버가 문장 메모를 남기면',
    '댓글 알림': '내 메모에 댓글이 달리면',
    'AI 독서 친구 알림': 'AI 친구가 메모·질문을 남기면',
    '새 멤버 입장': '내 방에 누군가 들어오면',
    '방해 금지 (22:00~08:00)': '이 시간에는 모아 두었다가 아침에 알려줘요',
  };

  @override
  Widget build(BuildContext context) => ScreenTag('RIDI_NOTI_SET_01', child: _screen(context));

  Widget _screen(BuildContext context) {
    final store = context.watch<RidiStore>();
    return Scaffold(
      appBar: ridiAppBar(context, '알림 설정'),
      body: SafeArea(
        child: ListView(
          children: [
            for (final e in store.notiSettings.entries) ...[
              RidiToggleRow(
                title: e.key,
                sub: _subs[e.key],
                value: e.value,
                onChanged: (v) => store.setNoti(e.key, v),
              ),
              const Divider(height: 1),
            ],
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Text('기기 알림이 꺼져 있으면 여기 설정과 상관없이 오지 않아요', style: RidiText.sub),
            ),
          ],
        ),
      ),
    );
  }
}

/// 알림을 누르면: 댓글 → 그 메모의 댓글, 방·AI → 그 방에서 책 열기
void _open(BuildContext context, RidiStore store, RidiNotification n) {
  store.markRead(n.id);
  if (n.kind == 'comment' && n.noteId != null) {
    showCommentsDialog(context, noteId: n.noteId!);
    return;
  }
  final bookId = n.bookId;
  final roomId = n.roomId;
  if (roomId != null && store.room(roomId) == null) {
    ridiToast(context, '이미 나간 방이에요');
    return;
  }
  if (bookId == null || store.book(bookId) == null) return;
  store.openBook(bookId, roomId: roomId);
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => RidiReaderScreen(bookId: bookId, roomId: roomId)));
}
