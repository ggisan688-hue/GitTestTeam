import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../model/room.dart';
import '../../theme/app_theme.dart';
import '../../viewmodel/auth_viewmodel.dart';
import '../../viewmodel/room_viewmodel.dart';
import '../../widgets/app_card.dart';
import '../../widgets/buttons.dart';
import '../../widgets/screen_tag.dart';
import '../auth/login_screen.dart';
import '../friends/friends_screen.dart';
import 'room_screen.dart';
import 'room_sheets.dart';
import 'room_widgets.dart';

/// 로그인 후 첫 화면: 내 독서방 목록. 방을 만들거나 코드로 들어간다.
class RoomsScreen extends StatefulWidget {
  const RoomsScreen({super.key});

  @override
  State<RoomsScreen> createState() => _RoomsScreenState();
}

class _RoomsScreenState extends State<RoomsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() {
    final me = context.read<AuthViewModel>().member;
    if (me == null) return Future.value();
    return context.read<RoomViewModel>().load(
      memberId: me.id,
      memberName: me.name,
    );
  }

  void _open(Room room) {
    context.read<RoomViewModel>().select(room);
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const RoomScreen()));
  }

  Future<void> _create() async {
    final room = await showCreateRoomSheet(context);
    if (room != null && mounted) _open(room);
  }

  Future<void> _join() async {
    final room = await showJoinRoomSheet(context);
    if (room != null && mounted) _open(room);
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<RoomViewModel>();
    final name = context.watch<AuthViewModel>().member?.name ?? '';

    return ScreenTag(
      'S10',
      child: Scaffold(
        appBar: AppBar(
          title: Text('$name님의 독서방'),
          actions: [
            PopupMenuButton<String>(
              tooltip: '메뉴',
              icon: const Icon(
                Icons.account_circle_outlined,
                size: 26,
                color: AppColors.ink,
              ),
              onSelected: (v) async {
                if (v == 'friends') {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const FriendsScreen()),
                  );
                } else if (v == 'logout') {
                  await context.read<AuthViewModel>().logout();
                  if (!context.mounted) return;
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                    (_) => false,
                  );
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'friends',
                  child: Text('친구 · 공유 설정 (이전 방식)', style: AppText.label),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'logout',
                  child: Text('로그아웃', style: AppText.label),
                ),
              ],
            ),
            const SizedBox(width: AppSpace.sm),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _load,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              AppSpace.lg,
              AppSpace.sm,
              AppSpace.lg,
              AppSpace.xxl,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('함께 읽는 방', style: AppText.heading),
                              const SizedBox(height: 2),
                              Text(
                                vm.rooms.isEmpty
                                    ? '방을 만들거나 친구가 알려준 코드로 들어가세요'
                                    : '${vm.rooms.length}개 · 방을 누르면 이어서 읽어요',
                                style: AppText.caption,
                              ),
                            ],
                          ),
                        ),
                        AppButton(
                          '코드로 입장',
                          icon: Icons.login_rounded,
                          onPressed: _join,
                        ),
                        const SizedBox(width: AppSpace.sm),
                        AppButton.primary(
                          '방 만들기',
                          icon: Icons.add_rounded,
                          onPressed: _create,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpace.lg),
                    if (vm.isLoading && vm.rooms.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(AppSpace.xxl + AppSpace.sm),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (vm.errorMessage != null &&
                        vm.rooms.isEmpty &&
                        vm.catalog.isEmpty)
                      AppCard(
                        child: Column(
                          children: [
                            Text(vm.errorMessage!, style: AppText.error),
                            const SizedBox(height: AppSpace.md),
                            AppButton('다시 시도', onPressed: _load),
                          ],
                        ),
                      )
                    else if (vm.rooms.isEmpty)
                      AreaTag(
                        'S10.3',
                        child: _EmptyRooms(onCreate: _create, onJoin: _join),
                      )
                    else
                      LayoutBuilder(
                        builder: (context, c) {
                          final cols = c.maxWidth > 700 ? 2 : 1;
                          return GridView.count(
                            crossAxisCount: cols,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            mainAxisSpacing: AppSpace.md,
                            crossAxisSpacing: AppSpace.md,
                            childAspectRatio: cols == 1 ? 2.6 : 2.9,
                            children: [
                              for (final r in vm.rooms)
                                AreaTag(
                                  'S10.2',
                                  child: _RoomCard(
                                    room: r,
                                    onTap: () => _open(r),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoomCard extends StatelessWidget {
  const _RoomCard({required this.room, required this.onTap});

  final Room room;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final vm = context.read<RoomViewModel>();
    final books = vm.booksOf(room);
    final next = vm.continueBookOf(room);
    return Material(
      color: AppColors.panel,
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        child: Container(
          padding: const EdgeInsets.all(AppSpace.lg),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.line),
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      room.name,
                      style: AppText.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  StatusBadge(
                    room.code,
                    tone: StatusTone.neutral,
                    icon: Icons.key_rounded,
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.xs),
              Text(
                books.isEmpty
                    ? '아직 책이 없어요'
                    : books.map((b) => b.title).join(' · '),
                style: AppText.caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const Spacer(),
              Row(
                children: [
                  MemberAvatarsRow(room: room),
                  const Spacer(),
                  if (next != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.menu_book_rounded,
                          size: 16,
                          color: AppColors.accentText,
                        ),
                        const SizedBox(width: AppSpace.xs),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 160),
                          child: Text(
                            '${next.title} 이어 읽기 →',
                            style: AppText.labelAccent,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    )
                  else
                    const Text('책 고르기 →', style: AppText.labelAccent),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 아바타 + `N명 · AI 이름` 한 줄
class MemberAvatarsRow extends StatelessWidget {
  const MemberAvatarsRow({super.key, required this.room});

  final Room room;

  @override
  Widget build(BuildContext context) {
    final ai = room.members.where((m) => m.ai).firstOrNull;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        MemberAvatars(room.members),
        const SizedBox(width: AppSpace.sm),
        Text(
          '${room.humanCount}명${ai != null ? " · ${ai.name}" : ""}',
          style: AppText.caption,
        ),
      ],
    );
  }
}

class _EmptyRooms extends StatelessWidget {
  const _EmptyRooms({required this.onCreate, required this.onJoin});

  final VoidCallback onCreate;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpace.xxl),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.accentSoft,
              borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            ),
            child: const Icon(
              Icons.groups_2_outlined,
              size: 32,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(height: AppSpace.lg),
          const Text('아직 독서방이 없어요', style: AppText.heading),
          const SizedBox(height: AppSpace.xs),
          const Text(
            '방을 만들어 책을 고르고, 코드를 친구에게 알려주세요.\n같은 방에서는 서로의 문장 메모가 보여요.',
            style: AppText.labelMuted,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpace.xl),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            alignment: WrapAlignment.center,
            children: [
              AppButton.primary(
                '방 만들기',
                icon: Icons.add_rounded,
                onPressed: onCreate,
              ),
              AppButton('코드로 입장', icon: Icons.login_rounded, onPressed: onJoin),
            ],
          ),
        ],
      ),
    );
  }
}
