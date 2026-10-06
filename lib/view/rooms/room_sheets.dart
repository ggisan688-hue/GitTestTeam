import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../model/book.dart';
import '../../model/friend.dart';
import '../../model/room.dart';
import '../../theme/app_theme.dart';
import '../../viewmodel/room_viewmodel.dart';
import '../../widgets/app_card.dart';
import '../../widgets/buttons.dart';
import '../../widgets/screen_tag.dart';
import 'room_widgets.dart';

/// 독서방 관련 하단 시트 모음: 만들기 / 코드 입장 / 책 추가 / AI 친구 / 이름 바꾸기

Future<T?> _sheet<T>(BuildContext context, Widget child) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTheme.radiusCard),
        ),
      ),
      builder: (_) => child,
    );

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({
    required this.tag,
    required this.title,
    this.hint,
    required this.child,
    this.actions,
  });

  final String tag;
  final String title;
  final String? hint;
  final Widget child;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final height = MediaQuery.sizeOf(context).height;
    return ScreenTag(
      tag,
      alignment: Alignment.topLeft,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: height * 0.88),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(
                        top: AppSpace.md,
                        bottom: AppSpace.sm,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.line,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpace.xl,
                      AppSpace.sm,
                      AppSpace.xl,
                      0,
                    ),
                    child: SectionTitle(title, hint: hint),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpace.xl,
                        AppSpace.sm,
                        AppSpace.xl,
                        0,
                      ),
                      child: child,
                    ),
                  ),
                  if (actions != null)
                    SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpace.xl,
                          AppSpace.lg,
                          AppSpace.xl,
                          AppSpace.lg,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            for (var i = 0; i < actions!.length; i++) ...[
                              if (i > 0) const SizedBox(width: AppSpace.sm),
                              actions![i],
                            ],
                          ],
                        ),
                      ),
                    )
                  else
                    const SizedBox(height: AppSpace.xl),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------- 방 만들기 (이름 → 책 → AI 친구) ----------------
Future<Room?> showCreateRoomSheet(BuildContext context) =>
    _sheet<Room>(context, const _CreateRoomSheet());

class _CreateRoomSheet extends StatefulWidget {
  const _CreateRoomSheet();

  @override
  State<_CreateRoomSheet> createState() => _CreateRoomSheetState();
}

class _CreateRoomSheetState extends State<_CreateRoomSheet> {
  final _name = TextEditingController();
  final _picked = <int>{};
  Persona? _persona;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_name.text.trim().isEmpty) {
      showToast(context, '방 이름을 적어주세요');
      return;
    }
    setState(() => _busy = true);
    final room = await context.read<RoomViewModel>().create(
      name: _name.text,
      bookIds: _picked.toList(),
      persona: _persona,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (room != null) Navigator.of(context).pop(room);
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<RoomViewModel>();
    return _SheetFrame(
      tag: 'S11',
      title: '독서방 만들기',
      hint: '이름을 정하고 함께 읽을 책을 골라요. 코드는 만들면 바로 나와요.',
      actions: [
        AppButton.ghost('취소', onPressed: () => Navigator.of(context).pop()),
        AppButton.primary('방 만들기', busy: _busy, onPressed: _create),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            textInputAction: TextInputAction.done,
            maxLength: 20,
            decoration: const InputDecoration(
              labelText: '방 이름',
              hintText: '예: 목요일 밤 독서회',
              counterText: '',
            ),
          ),
          const SizedBox(height: AppSpace.xl),
          Text(
            '함께 읽을 책',
            style: AppText.label.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: AppSpace.xs),
          Text(
            _picked.isEmpty ? '나중에 추가해도 돼요' : '${_picked.length}권 선택',
            style: AppText.caption,
          ),
          const SizedBox(height: AppSpace.sm),
          _BookPicker(
            books: vm.catalog,
            picked: _picked,
            onToggle: (id) => setState(
              () => _picked.contains(id) ? _picked.remove(id) : _picked.add(id),
            ),
          ),
          const SizedBox(height: AppSpace.xl),
          Text(
            'AI 독서 친구',
            style: AppText.label.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: AppSpace.xs),
          const Text('방마다 하나. 읽는 장마다 먼저 메모와 질문을 남겨요.', style: AppText.caption),
          const SizedBox(height: AppSpace.sm),
          _PersonaPicker(
            personas: vm.personas,
            chosen: _persona,
            onPick: (p) => setState(() => _persona = p),
          ),
        ],
      ),
    );
  }
}

// ---------------- 코드로 입장 ----------------
Future<Room?> showJoinRoomSheet(BuildContext context) =>
    _sheet<Room>(context, const _JoinRoomSheet());

class _JoinRoomSheet extends StatefulWidget {
  const _JoinRoomSheet();

  @override
  State<_JoinRoomSheet> createState() => _JoinRoomSheetState();
}

class _JoinRoomSheetState extends State<_JoinRoomSheet> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final code = _code.text.trim().toUpperCase();
    if (code.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final vm = context.read<RoomViewModel>();
    final room = await vm.join(code); // RM- 자동 추가 제거
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = room == null ? (vm.errorMessage ?? '방을 찾을 수 없어요') : null;
    });
    if (room != null) Navigator.of(context).pop(room);
  }

  @override
  Widget build(BuildContext context) {
    return _SheetFrame(
      tag: 'S12',
      title: '코드로 입장',
      hint: '방을 만든 친구가 알려준 코드를 입력하세요',
      actions: [
        AppButton.ghost('취소', onPressed: () => Navigator.of(context).pop()),
        AppButton.primary('들어가기', busy: _busy, onPressed: _join),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _code,
            autofocus: true,
            // Do not filter or rewrite text while it is being composed. In
            // particular, an IME may send a partially composed Hangul syllable
            // before committing it. The room-code format is validated only when
            // the user submits, in _join().
            style: AppText.title.copyWith(letterSpacing: 2),
            decoration: InputDecoration(hintText: 'RM-XXXX', errorText: _error),
            onSubmitted: (_) => _join(),
          ),
        ],
      ),
    );
  }
}

// ---------------- 책 추가 ----------------
Future<List<int>?> showAddBooksSheet(BuildContext context, Room room) =>
    _sheet<List<int>>(context, _AddBooksSheet(room: room));

class _AddBooksSheet extends StatefulWidget {
  const _AddBooksSheet({required this.room});

  final Room room;

  @override
  State<_AddBooksSheet> createState() => _AddBooksSheetState();
}

class _AddBooksSheetState extends State<_AddBooksSheet> {
  final _picked = <int>{};

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<RoomViewModel>();
    final candidates = vm.catalog
        .where((b) => !widget.room.bookIds.contains(b.id))
        .toList();
    return _SheetFrame(
      tag: 'S21',
      title: '책 추가',
      hint: candidates.isEmpty
          ? '추가할 수 있는 책을 모두 넣었어요'
          : '${widget.room.name} 에서 함께 읽을 책',
      actions: [
        AppButton.ghost('취소', onPressed: () => Navigator.of(context).pop()),
        AppButton.primary(
          _picked.isEmpty ? '추가' : '${_picked.length}권 추가',
          onPressed: _picked.isEmpty
              ? null
              : () => Navigator.of(context).pop(_picked.toList()),
        ),
      ],
      child: _BookPicker(
        books: candidates,
        picked: _picked,
        onToggle: (id) => setState(
          () => _picked.contains(id) ? _picked.remove(id) : _picked.add(id),
        ),
      ),
    );
  }
}

class _BookPicker extends StatelessWidget {
  const _BookPicker({
    required this.books,
    required this.picked,
    required this.onToggle,
  });

  final List<Book> books;
  final Set<int> picked;
  final ValueChanged<int> onToggle;

  @override
  Widget build(BuildContext context) {
    if (books.isEmpty) return const EmptyHint('고를 수 있는 책이 없어요');
    return Column(
      children: [
        for (final b in books)
          Material(
            color: picked.contains(b.id)
                ? AppColors.accentSoft
                : AppColors.sceneBg,
            borderRadius: BorderRadius.circular(AppTheme.radiusControl),
            child: InkWell(
              onTap: () => onToggle(b.id),
              borderRadius: BorderRadius.circular(AppTheme.radiusControl),
              child: Container(
                margin: const EdgeInsets.only(bottom: AppSpace.sm),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.md,
                  vertical: AppSpace.sm,
                ),
                constraints: const BoxConstraints(
                  minHeight: AppSpace.touch + 8,
                ),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: picked.contains(b.id)
                        ? AppColors.accent
                        : AppColors.line,
                  ),
                  borderRadius: BorderRadius.circular(AppTheme.radiusControl),
                ),
                child: Row(
                  children: [
                    Icon(
                      picked.contains(b.id)
                          ? Icons.check_circle_rounded
                          : Icons.circle_outlined,
                      color: picked.contains(b.id)
                          ? AppColors.accent
                          : AppColors.line,
                    ),
                    const SizedBox(width: AppSpace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            b.title,
                            style: AppText.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${b.author ?? ''} · ${b.chapterCount}장',
                            style: AppText.caption,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------- AI 독서 친구 ----------------
Future<void> showPersonaSheet(BuildContext context, Room room) =>
    _sheet<void>(context, _PersonaSheet(room: room));

class _PersonaSheet extends StatefulWidget {
  const _PersonaSheet({required this.room});

  final Room room;

  @override
  State<_PersonaSheet> createState() => _PersonaSheetState();
}

class _PersonaSheetState extends State<_PersonaSheet> {
  Persona? _chosen;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _chosen = context.read<RoomViewModel>().personaIn(widget.room);
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    await context.read<RoomViewModel>().setPersona(widget.room, _chosen);
    if (!mounted) return;
    Navigator.of(context).pop();
    showToast(
      context,
      _chosen == null
          ? 'AI 독서 친구를 뺐어요'
          : '${_chosen!.name}이(가) 함께 읽어요. 다음에 여는 장부터 메모를 남겨요',
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<RoomViewModel>();
    return _SheetFrame(
      tag: 'S22',
      title: 'AI 독서 친구',
      hint: '${widget.room.name} 의 AI 친구. 방 멤버 모두에게 같은 메모가 보여요.',
      actions: [
        if (_chosen != null)
          AppButton.ghost(
            '없이 읽기',
            onPressed: () => setState(() => _chosen = null),
          ),
        AppButton.ghost('취소', onPressed: () => Navigator.of(context).pop()),
        AppButton.primary('저장', busy: _busy, onPressed: _save),
      ],
      child: _PersonaPicker(
        personas: vm.personas,
        chosen: _chosen,
        onPick: (p) => setState(() => _chosen = p),
      ),
    );
  }
}

class _PersonaPicker extends StatelessWidget {
  const _PersonaPicker({
    required this.personas,
    required this.chosen,
    required this.onPick,
  });

  final List<Persona> personas;
  final Persona? chosen;
  final ValueChanged<Persona?> onPick;

  @override
  Widget build(BuildContext context) {
    if (personas.isEmpty) return const EmptyHint('캐릭터 목록을 불러오지 못했어요');
    return Column(
      children: [
        for (final p in personas)
          Material(
            color: chosen?.memberId == p.memberId
                ? AppColors.accentSoft
                : AppColors.sceneBg,
            borderRadius: BorderRadius.circular(AppTheme.radiusControl),
            child: InkWell(
              onTap: () => onPick(chosen?.memberId == p.memberId ? null : p),
              borderRadius: BorderRadius.circular(AppTheme.radiusControl),
              child: Container(
                margin: const EdgeInsets.only(bottom: AppSpace.sm),
                padding: const EdgeInsets.all(AppSpace.md),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: chosen?.memberId == p.memberId
                        ? AppColors.accent
                        : AppColors.line,
                  ),
                  borderRadius: BorderRadius.circular(AppTheme.radiusControl),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.panel,
                        borderRadius: BorderRadius.circular(
                          AppTheme.radiusControl,
                        ),
                        border: Border.all(color: AppColors.line),
                      ),
                      child: Text(
                        p.avatar,
                        style: const TextStyle(fontSize: 22),
                      ),
                    ),
                    const SizedBox(width: AppSpace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.name,
                            style: AppText.label.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            p.intro,
                            style: AppText.caption.copyWith(height: 1.45),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpace.sm),
                    Icon(
                      chosen?.memberId == p.memberId
                          ? Icons.check_circle_rounded
                          : Icons.circle_outlined,
                      color: chosen?.memberId == p.memberId
                          ? AppColors.accent
                          : AppColors.line,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------- 이름 바꾸기 ----------------
Future<String?> showRenameRoomSheet(BuildContext context, Room room) =>
    _sheet<String>(context, _RenameSheet(room: room));

class _RenameSheet extends StatefulWidget {
  const _RenameSheet({required this.room});

  final Room room;

  @override
  State<_RenameSheet> createState() => _RenameSheetState();
}

class _RenameSheetState extends State<_RenameSheet> {
  late final _name = TextEditingController(text: widget.room.name);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _done() {
    if (_name.text.trim().isEmpty) return;
    Navigator.of(context).pop(_name.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return _SheetFrame(
      tag: 'S23',
      title: '방 이름 바꾸기',
      actions: [
        AppButton.ghost('취소', onPressed: () => Navigator.of(context).pop()),
        AppButton.primary('저장', onPressed: _done),
      ],
      child: TextField(
        controller: _name,
        autofocus: true,
        maxLength: 20,
        decoration: const InputDecoration(counterText: ''),
        onSubmitted: (_) => _done(),
      ),
    );
  }
}

/// 목록이 비었을 때 한 줄 안내
class EmptyHint extends StatelessWidget {
  const EmptyHint(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: AppColors.sceneBg,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
      ),
      child: Text(text, style: AppText.labelMuted, textAlign: TextAlign.center),
    );
  }
}

// ---------------- 멤버 보기 (읽기 화면에서) ----------------
Future<void> showRoomMembersSheet(BuildContext context, Room room) =>
    _sheet<void>(context, _MembersSheet(room: room));

class _MembersSheet extends StatelessWidget {
  const _MembersSheet({required this.room});

  final Room room;

  @override
  Widget build(BuildContext context) {
    final ai = context.read<RoomViewModel>().personaIn(room);
    return _SheetFrame(
      tag: 'S24',
      title: room.name,
      hint:
          '${room.humanCount}명${ai != null ? " + AI ${ai.name}" : ""} · 같은 방이면 서로의 문장 메모가 보여요',
      actions: [AppButton('닫기', onPressed: () => Navigator.of(context).pop())],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text('방 코드', style: AppText.label),
              const SizedBox(width: AppSpace.md),
              RoomCodeChip(room.code),
              const Spacer(),
              const Text('친구에게 알려주면 바로 들어와요', style: AppText.caption),
            ],
          ),
          const SizedBox(height: AppSpace.lg),
          for (final m in room.members)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.sm),
              child: Row(
                children: [
                  MemberAvatar(m, size: 36),
                  const SizedBox(width: AppSpace.md),
                  Expanded(child: Text(m.name, style: AppText.label)),
                  if (m.memberId == room.ownerId) const StatusBadge('방장'),
                  if (m.ai) const StatusBadge('AI 독서 친구', tone: StatusTone.ai),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
