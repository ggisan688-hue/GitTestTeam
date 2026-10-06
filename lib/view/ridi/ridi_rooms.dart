import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import 'ridi_reader.dart';
import 'ridi_store.dart';
import 'ridi_theme.dart';
import 'ridi_widgets.dart';
import '../../widgets/screen_tag.dart';

/// 교환독서 방 화면들 — UC-03 방 만들기(프로필 설정·책 선택·방 설정 포함), UC-04 방 참여
///
/// - RIDI_ROOM_CREATE_01 방 만들기 (입장 방식: 코드만 / 코드 + 비밀번호, 최대 인원 2~50 + / −) → 만들면 방 코드 안내 팝업
/// - RIDI_ROOM_JOIN_01 코드로 입장 → 입력 즉시 미리보기 → (비밀번호) → 들어가기 → RIDI_PROFILE_01 → 입장
/// - RIDI_PROFILE_01 프로필 설정 (MY › 내 정보에서도 씀)
/// - RIDI_ROOMS_02 방 메뉴(⋯): 이름 · 코드 · 책 추가 · 멤버 · 스포일러 잠금 · (방장) 최대 인원 · 비밀번호 · AI 친구 · 나가기
/// - RIDI_ROOM_MEMBERS_01 멤버 관리 (방장): 방장 넘기기 · 내보내기 · 차단 · 차단 해제
/// - 방 나가기: 방장이 나가면 가장 먼저 들어온 사람이 방장, 혼자면 방이 사라진다
/// - AI 친구 고르기 시트 (방 메뉴 · 뷰어 도구 공통)

/// 방 만들기 화면 열기 (내 서재 › 교환독서 › + 방 만들기)
void showCreateRoomSheet(BuildContext context) =>
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const RoomCreateScreen()));

/// 코드로 입장 화면 열기 (내 서재 › 교환독서 › 코드로 입장)
void showJoinRoomSheet(BuildContext context) =>
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const RoomJoinScreen()));

// ================= 방 만들기 =================
class RoomCreateScreen extends StatefulWidget {
  const RoomCreateScreen({super.key});

  @override
  State<RoomCreateScreen> createState() => _RoomCreateScreenState();
}

class _RoomCreateScreenState extends State<RoomCreateScreen> {
  final _name = TextEditingController();
  late final TextEditingController _nick;
  final _picked = <String>{};
  String? _personaId;
  bool _spoilerLock = true;
  int _max = 6;
  String? _password; // null = 코드만으로 입장

  @override
  void initState() {
    super.initState();
    _nick = TextEditingController(text: context.read<RidiStore>().nickname);
  }

  @override
  void dispose() {
    _name.dispose();
    _nick.dispose();
    super.dispose();
  }

  /// 만들기: 방 이름 필수 · 닉네임 2~12자(비우면 지금 이름 그대로) → 닉네임 저장 → 방 생성(코드 발급) → 이 화면을 닫고 코드 안내 팝업
  Future<void> _create() async {
    final store = context.read<RidiStore>();
    if (_name.text.trim().isEmpty) {
      ridiToast(context, '방 이름을 적어주세요');
      return;
    }
    final nick = _nick.text.trim();
    if (nick.isNotEmpty && nick.length < 2) {
      ridiToast(context, '닉네임은 2~12자로 적어주세요');
      return;
    }
    try {
      if (nick.isNotEmpty)
        await store.saveProfile(nick: nick, intro: store.bio);
    } on ApiException catch (error) {
      if (mounted) ridiToast(context, _profileErrorMessage(error));
      return;
    }
    final room = store.createRoom(
      name: _name.text,
      bookIds: _picked.toList(),
      personaId: _personaId,
      spoilerLock: _spoilerLock,
      maxMembers: _max,
      password: _password,
    );
    if (!mounted) return;
    // Do not use this State's BuildContext after popping its route.  That was
    // the source of the intermittent "deactivated widget" red screen in the
    // legacy prototype flow.  The navigator owns a still-mounted context.
    final navigator = Navigator.of(context);
    navigator.pop();
    if (!navigator.mounted) return;
    await showRoomCodeDialog(navigator.context, room);
  }

  @override
  Widget build(BuildContext context) =>
      ScreenTag('RIDI_ROOM_CREATE_01', child: _screen(context));

  Widget _screen(BuildContext context) {
    final store = context.watch<RidiStore>();
    return Scaffold(
      appBar: ridiAppBar(context, '독서방 만들기', right: '만들기', onRight: _create),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) {
            final two = c.maxWidth > 900;
            final left = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _Label('방 이름'),
                RidiInput(
                  controller: _name,
                  hint: '예: 목요일 밤 독서회',
                  maxLength: 20,
                  autofocus: true,
                ),
                const SizedBox(height: 28),
                _Label(
                  '함께 읽을 책',
                  sub: _picked.isEmpty
                      ? '나중에 추가해도 돼요'
                      : '${_picked.length}권 선택',
                ),
                for (final b in store.books)
                  _PickRow(
                    title: b.title,
                    sub: '${b.author} · ${b.chapters}장',
                    picked: _picked.contains(b.id),
                    onTap: () => setState(
                      () => _picked.contains(b.id)
                          ? _picked.remove(b.id)
                          : _picked.add(b.id),
                    ),
                  ),
                const SizedBox(height: 28),
                const _Label('프로필 설정', sub: '이 방에서 보일 이름·아바타'),
                Row(
                  children: [
                    RidiAvatar(label: store.avatar, size: 60),
                    const SizedBox(width: 16),
                    Expanded(
                      child: RidiInput(
                        controller: _nick,
                        hint: '닉네임 2~12자 (기본: 회원 이름)',
                        maxLength: 12,
                      ),
                    ),
                  ],
                ),
              ],
            );

            final right = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _Label('방 설정'),
                _SettingRow(
                  label: '입장 방식',
                  value: _password == null ? '코드 입력' : '코드 + 비밀번호',
                  onTap: () async {
                    final r = await _pickEntry(context, _password);
                    if (r != null)
                      setState(() => _password = r.isEmpty ? null : r);
                  },
                ),
                _SettingRow(
                  label: '스포일러 잠금',
                  sub: '읽는 지점 뒤 메모 숨김',
                  toggle: _spoilerLock,
                  onToggle: (v) => setState(() => _spoilerLock = v),
                ),
                _SettingRow(
                  label: '최대 인원',
                  sub: '$kRoomMinMembers~$kRoomMaxMembers명 · AI 친구는 빼고 세요',
                  trailing: RidiStepper(
                    value: _max,
                    min: kRoomMinMembers,
                    max: kRoomMaxMembers,
                    onChanged: (v) => setState(() => _max = v),
                  ),
                ),
                const SizedBox(height: 28),
                const _Label('AI 독서 친구', sub: '방마다 하나'),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final p in store.personas)
                      _PersonaCard(
                        persona: p,
                        on: _personaId == p.id,
                        onTap: () => setState(
                          () => _personaId = _personaId == p.id ? null : p.id,
                        ),
                      ),
                  ],
                ),
              ],
            );

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
              child: two
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: left),
                        const SizedBox(width: 40),
                        Expanded(child: right),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [left, const SizedBox(height: 28), right],
                    ),
            );
          },
        ),
      ),
    );
  }
}

/// 입장 방식 고르기 시트 (RIDI_ROOM_CREATE_01 › 입장 방식) — 코드만 / 코드 + 비밀번호(숫자 4자리).
/// 돌려주는 값: '' = 코드만, '1234' = 비밀번호, null = 취소(그대로)
Future<String?> _pickEntry(BuildContext context, String? current) async {
  final pick = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
    ),
    builder: (ctx) => ScreenTag(
      'RIDI_ROOM_CREATE_01 › 입장 방식',
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('입장 방식', style: RidiText.heading),
              const SizedBox(height: 8),
              for (final (pw, title, sub) in const [
                (false, '코드만', '방 코드를 아는 사람은 바로 들어와요'),
                (true, '코드 + 비밀번호', '방 코드와 숫자 4자리 비밀번호를 모두 알아야 들어와요'),
              ])
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    pw ? Icons.lock_outline_rounded : Icons.key_outlined,
                    color: RidiColors.ink,
                  ),
                  title: Text(
                    title,
                    style: (current != null) == pw
                        ? RidiText.bodyBold
                        : RidiText.body,
                  ),
                  subtitle: Text(sub, style: RidiText.sub),
                  trailing: (current != null) == pw
                      ? const Icon(Icons.check_rounded)
                      : null,
                  onTap: () => Navigator.pop(ctx, pw),
                ),
            ],
          ),
        ),
      ),
    ),
  );
  if (pick == null || !context.mounted) return null;
  if (!pick) return '';
  return showRoomPasswordDialog(
    context,
    tag: 'RIDI_ROOM_CREATE_01 › 입장 방식 › 비밀번호',
    current: current,
  );
}

/// 방 비밀번호 정하기 팝업 — 숫자 4자리. 저장하면 비밀번호를, 취소하면 null 을 돌려준다
/// (RIDI_ROOMS_02 › 비밀번호 설정 · 방 만들기의 입장 방식에서 같이 씀)
Future<String?> showRoomPasswordDialog(
  BuildContext context, {
  String tag = 'RIDI_ROOMS_02 › 비밀번호 설정',
  String? current,
}) {
  final c = TextEditingController(text: current ?? '');
  String? error;
  return showDialog<String>(
    context: context,
    builder: (ctx) => ScreenTag(
      tag,
      child: StatefulBuilder(
        builder: (ctx, setDialog) {
          void save() {
            if (!RegExp(r'^\d{4}$').hasMatch(c.text)) {
              setDialog(() => error = '숫자 4자리로 적어주세요');
              return;
            }
            Navigator.pop(ctx, c.text);
          }

          return AlertDialog(
            backgroundColor: Colors.white,
            title: const Text('방 비밀번호', style: RidiText.heading),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('코드와 함께 이 번호를 알아야 들어올 수 있어요', style: RidiText.sub),
                const SizedBox(height: 16),
                RidiInput(
                  controller: c,
                  hint: '0000',
                  autofocus: true,
                  keyboard: TextInputType.number,
                  maxLength: 4,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: RidiText.f,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 10,
                    color: RidiColors.ink,
                  ),
                  onSubmitted: (_) => save(),
                ),
                const SizedBox(height: 8),
                Text(
                  error ?? '방장은 방 메뉴에서 언제든 바꾸거나 끌 수 있어요',
                  style: RidiText.sub.copyWith(
                    color: error == null ? null : RidiColors.red,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text(
                  '취소',
                  style: TextStyle(
                    fontFamily: RidiText.f,
                    color: RidiColors.gray,
                  ),
                ),
              ),
              TextButton(
                onPressed: save,
                child: const Text(
                  '저장',
                  style: TextStyle(
                    fontFamily: RidiText.f,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

// ================= 코드로 입장 =================
class RoomJoinScreen extends StatefulWidget {
  const RoomJoinScreen({super.key});

  @override
  State<RoomJoinScreen> createState() => _RoomJoinScreenState();
}

class _RoomJoinScreenState extends State<RoomJoinScreen> {
  final _code = TextEditingController();
  final _pw = TextEditingController();
  RidiRoom? _found;
  String? _error;
  String? _pwError;

  @override
  void dispose() {
    _code.dispose();
    _pw.dispose();
    super.dispose();
  }

  /// 찾은 방에 비밀번호가 걸려 있고 내가 아직 멤버가 아니면 비밀번호 칸을 보여 준다
  bool get _needPassword =>
      _found?.password != null && !context.read<RidiStore>().isMember(_found!);

  /// 입력할 때마다 조회: RM- 자동 보정 · 대문자. RM-XXXX(7자)가 되면 찾아서 미리보기,
  /// 없거나 · 차단됐거나 · 정원이 찼으면(이미 멤버면 괜찮음) 아래에 문구
  void _lookup(String s) {
    final store = context.read<RidiStore>();
    final t = s.trim().toUpperCase();
    final full = t.startsWith('RM-') ? t : 'RM-$t';
    final f = full.length >= 7 ? store.findByCode(full) : null;
    final member = f != null && store.isMember(f);
    final blocked = f != null && !member && f.blocked.contains(store.nickname);
    final isFull =
        f != null && !member && !blocked && f.humanCount >= f.maxMembers;
    setState(() {
      _found = blocked || isFull ? null : f;
      _pwError = null;
      _error = full.length < 7
          ? null
          : (f == null
                ? '방을 찾을 수 없어요'
                : (blocked
                      ? '이 방에는 들어갈 수 없어요'
                      : (isFull ? '정원(${f.maxMembers}명)이 다 찼어요' : null)));
    });
  }

  /// 들어가기: (비밀번호 확인) → 프로필 설정 화면을 거쳐(UC-04 ⊃ 프로필 설정) 입장 → 코드 입장 화면을 닫고 안내
  Future<void> _join() async {
    if (_found == null) {
      setState(() => _error = '방을 찾을 수 없어요');
      return;
    }
    final room = _found!;
    if (_needPassword && _pw.text != room.password) {
      setState(
        () =>
            _pwError = _pw.text.length < 4 ? '비밀번호 4자리를 적어주세요' : '비밀번호가 맞지 않아요',
      );
      return;
    }
    final store = context.read<RidiStore>();
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    // 프로필 설정을 거쳐 입장 (UC-04 ⊃ 프로필 설정)
    await nav.push(
      MaterialPageRoute(builder: (_) => const ProfileScreen(forJoin: true)),
    );
    final result = store.joinRoom(room.code, password: _pw.text);
    if (result != JoinResult.ok) {
      setState(
        () => _error = switch (result) {
          JoinResult.full => '정원(${room.maxMembers}명)이 다 찼어요',
          JoinResult.blocked => '이 방에는 들어갈 수 없어요',
          JoinResult.wrongPassword => '비밀번호가 맞지 않아요',
          _ => '방을 찾을 수 없어요',
        },
      );
      return;
    }
    nav.pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('${room.name} 에 들어왔어요'),
          duration: const Duration(milliseconds: 1600),
        ),
      );
  }

  @override
  Widget build(BuildContext context) =>
      ScreenTag('RIDI_ROOM_JOIN_01', child: _screen(context));

  Widget _screen(BuildContext context) {
    final store = context.read<RidiStore>();
    return Scaffold(
      appBar: ridiAppBar(
        context,
        '코드로 입장',
        right: '들어가기',
        onRight: _found == null ? null : _join,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                children: [
                  const SizedBox(height: 24),
                  const Text('방을 만든 친구가 알려준 코드를 입력하세요', style: RidiText.sub),
                  const SizedBox(height: 20),
                  RidiInput(
                    controller: _code,
                    hint: 'RM-XXXX',
                    autofocus: true,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: RidiText.f,
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 3,
                      color: RidiColors.ink,
                    ),
                    onChanged: _lookup,
                    onSubmitted: (s) {
                      _lookup(s);
                      if (_found != null) _join();
                    },
                  ),
                  const SizedBox(height: 10),
                  if (_error != null)
                    Text(
                      _error!,
                      style: RidiText.sub.copyWith(color: RidiColors.red),
                    )
                  else
                    const Text(
                      '코드는 영문·숫자 4자리 (예: RM-7K2M)',
                      style: RidiText.sub,
                    ),
                  const SizedBox(height: 28),
                  if (_found != null)
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: RidiColors.panel,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('입장할 방', style: RidiText.sub),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        _found!.name,
                                        style: RidiText.title.copyWith(
                                          fontSize: 20,
                                        ),
                                      ),
                                    ),
                                    if (_found!.password != null) ...[
                                      const SizedBox(width: 8),
                                      const Icon(
                                        Icons.lock_rounded,
                                        size: 18,
                                        color: RidiColors.gray,
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '${store.roomBooks(_found!).map((b) => b.title).join(" · ")} · ${_found!.humanCount}명 · 방장 ${_found!.members.firstWhere((m) => m.owner, orElse: () => _found!.members.first).name}',
                                  style: RidiText.sub,
                                ),
                              ],
                            ),
                          ),
                          if (store.persona(_found!.personaId) case final p?)
                            RidiAvatar(label: p.name, ai: true, size: 60),
                        ],
                      ),
                    ),
                  if (_needPassword) ...[
                    const SizedBox(height: 20),
                    const Text('비밀번호가 걸린 방이에요', style: RidiText.sub),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: 220,
                      child: RidiInput(
                        controller: _pw,
                        hint: '숫자 4자리',
                        obscure: true,
                        keyboard: TextInputType.number,
                        maxLength: 4,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: RidiText.f,
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 10,
                          color: RidiColors.ink,
                        ),
                        onChanged: (_) => setState(() => _pwError = null),
                        onSubmitted: (_) => _join(),
                      ),
                    ),
                    if (_pwError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _pwError!,
                        style: RidiText.sub.copyWith(color: RidiColors.red),
                      ),
                    ],
                  ],
                  const SizedBox(height: 24),
                  const Text('들어가면 프로필 설정 화면으로 이동합니다', style: RidiText.sub),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ================= 프로필 설정 =================
/// 방에서 보일 아바타 글자 · 닉네임 · 한 줄 소개. forJoin 이면 오른쪽 위 버튼이 "입장"(방 입장 흐름)
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.forJoin = false});

  /// 방 참여 흐름에서 열렸는지 (오른쪽 버튼 글자만 다름)
  final bool forJoin;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final TextEditingController _nick;
  late final TextEditingController _bio;
  final ImagePicker _imagePicker = ImagePicker();
  XFile? _pickedImage;
  Uint8List? _pickedImageBytes;
  bool _removeProfileImage = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final s = context.read<RidiStore>();
    _nick = TextEditingController(text: s.nickname);
    _bio = TextEditingController(text: s.bio);
  }

  @override
  void dispose() {
    _nick.dispose();
    _bio.dispose();
    super.dispose();
  }

  /// 저장하고 이전 화면으로 (입장 흐름이면 RoomJoinScreen._join 이 이어서 방에 넣는다). 닉네임은 2~12자
  Future<void> _save() async {
    final nickname = _nick.text.trim();
    if (nickname.length < 2 || nickname.length > 50) {
      ridiToast(context, '닉네임은 2자 이상 50자 이하로 입력해주세요.');
      return;
    }
    setState(() => _saving = true);
    try {
      await context.read<RidiStore>().saveProfile(
        nick: nickname,
        intro: _bio.text.trim(),
        imageBytes: _pickedImageBytes,
        imageFilename: _pickedImage?.name,
        imageContentType: _pickedImage?.mimeType,
        removeProfileImage: _removeProfileImage,
      );
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (error) {
      if (mounted) ridiToast(context, _profileErrorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _choosePhoto() async {
    final hasPhoto =
        _pickedImageBytes != null ||
        context.read<RidiStore>().profileImageUrl?.isNotEmpty == true;
    final action = await showModalBottomSheet<_ProfilePhotoAction>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('갤러리에서 선택'),
              onTap: () =>
                  Navigator.pop(sheetContext, _ProfilePhotoAction.gallery),
            ),
            if (hasPhoto)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('프로필 사진 삭제'),
                textColor: Colors.red,
                iconColor: Colors.red,
                onTap: () =>
                    Navigator.pop(sheetContext, _ProfilePhotoAction.remove),
              ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('취소'),
              onTap: () => Navigator.pop(sheetContext),
            ),
          ],
        ),
      ),
    );
    if (action == _ProfilePhotoAction.remove) {
      setState(() {
        _pickedImage = null;
        _pickedImageBytes = null;
        _removeProfileImage = true;
      });
      return;
    }
    if (action != _ProfilePhotoAction.gallery) return;
    try {
      final image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1280,
        imageQuality: 85,
      );
      if (image == null) return;
      final validExtension = RegExp(
        r'\.(jpe?g|png|webp)$',
        caseSensitive: false,
      ).hasMatch(image.name);
      final bytes = await image.readAsBytes();
      if (!validExtension) {
        if (mounted) ridiToast(context, 'JPG, PNG, WEBP 형식의 이미지만 선택할 수 있습니다.');
        return;
      }
      if (bytes.length > 5 * 1024 * 1024) {
        if (mounted) ridiToast(context, '프로필 사진은 5MB 이하만 등록할 수 있습니다.');
        return;
      }
      if (!mounted) return;
      setState(() {
        _pickedImage = image;
        _pickedImageBytes = bytes;
        _removeProfileImage = false;
      });
    } catch (_) {
      if (mounted) ridiToast(context, '사진을 불러오지 못했습니다. 권한과 파일을 확인해주세요.');
    }
  }

  @override
  Widget build(BuildContext context) =>
      ScreenTag('RIDI_PROFILE_01', child: _screen(context));

  Widget _screen(BuildContext context) {
    return Scaffold(
      appBar: ridiAppBar(
        context,
        '프로필 수정',
        right: _saving ? '저장 중...' : (widget.forJoin ? '입장' : '저장'),
        onRight: _saving ? null : _save,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 16),
                  Center(
                    child: _ProfilePhotoPicker(
                      imageBytes: _pickedImageBytes,
                      imageUrl: _removeProfileImage
                          ? null
                          : context.watch<RidiStore>().profileImageUrl,
                      onTap: _saving ? null : _choosePhoto,
                    ),
                  ),
                  const SizedBox(height: 28),
                  const _Label('닉네임'),
                  RidiInput(
                    controller: _nick,
                    hint: '2자 이상 50자 이하',
                    maxLength: 50,
                  ),
                  const SizedBox(height: 24),
                  const _Label('소개'),
                  RidiInput(
                    controller: _bio,
                    hint: '예: 밤에 조금씩 읽어요',
                    maxLength: 300,
                  ),
                  const SizedBox(height: 24),
                  const Text('선택한 프로필은 방 멤버에게 보여요.', style: RidiText.sub),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _ProfilePhotoAction { gallery, remove }

class _ProfilePhotoPicker extends StatelessWidget {
  const _ProfilePhotoPicker({
    required this.imageBytes,
    required this.imageUrl,
    required this.onTap,
  });
  final Uint8List? imageBytes;
  final String? imageUrl;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final hasLocalImage = imageBytes != null;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          SizedBox(
            width: 120,
            height: 120,
            child: ClipOval(
              child: hasLocalImage
                  ? Image.memory(imageBytes!, fit: BoxFit.cover)
                  : RidiProfileImage(imageUrl: imageUrl, size: 120),
            ),
          ),
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: RidiColors.ink,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: const Icon(Icons.edit, size: 18, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

String _profileErrorMessage(ApiException error) {
  if (error.statusCode == 401 || error.statusCode == 403)
    return '로그인 정보가 만료되었습니다. 다시 로그인해주세요.';
  if (error.errorCode == 'DUPLICATE_NICKNAME' || error.statusCode == 409)
    return '이미 사용 중인 닉네임입니다.';
  if (error.statusCode == 400) return '닉네임 또는 소개의 형식을 확인해주세요.';
  if (error.statusCode == null) return '네트워크 연결을 확인해주세요.';
  return '일시적인 서버 오류가 발생했습니다. 잠시 후 다시 시도해주세요.';
}

// ================= 방 코드 안내 · 방 정보 시트 =================
/// 방을 만든 직후: 방 코드를 크게 보여 주는 팝업 (코드를 누르면 복사)
Future<void> showRoomCodeDialog(BuildContext context, RidiRoom room) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => ScreenTag(
      'RIDI_ROOM_CREATE_01 › 방 코드 안내',
      child: AlertDialog(
        backgroundColor: Colors.white,
        title: Text('${room.name} 방이 만들어졌어요', style: RidiText.heading),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              room.password == null
                  ? '아래 코드를 친구에게 알려주면 바로 들어와요'
                  : '코드와 비밀번호를 함께 알려주세요',
              style: RidiText.sub,
            ),
            const SizedBox(height: 16),
            _CodeChip(code: room.code, large: true),
            if (room.password case final pw?) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.lock_rounded,
                    size: 18,
                    color: RidiColors.gray,
                  ),
                  const SizedBox(width: 6),
                  Text('비밀번호 $pw', style: RidiText.bodyBold),
                ],
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              '확인',
              style: TextStyle(
                fontFamily: RidiText.f,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// RIDI_ROOMS_02 — 방 카드 ⋯ 메뉴 (코드 복사·책 추가·멤버(방장: 관리)·스포일러 잠금·(방장) 최대 인원·비밀번호·AI 친구·나가기)
Future<void> showRoomSheet(BuildContext context, RidiRoom room) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
    ),
    builder: (_) => _RoomSheet(roomId: room.id),
  );
}

/// 방 메뉴 내용 — store 를 watch 해서 이름·책·AI 를 바꾸면 시트가 바로 다시 그려진다
class _RoomSheet extends StatelessWidget {
  const _RoomSheet({required this.roomId});

  final String roomId;

  @override
  Widget build(BuildContext context) => ScreenTag(
    'RIDI_ROOMS_02',
    alignment: Alignment.bottomRight,
    child: _screen(context),
  );

  Widget _screen(BuildContext context) {
    final store = context.watch<RidiStore>();
    final room = store.room(roomId);
    if (room == null) return const SizedBox(height: 200);
    final books = store.roomBooks(room);
    final ai = store.persona(room.personaId);
    final owner = store.isOwner(room);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: RidiColors.grayLight,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      room.name,
                      style: RidiText.title.copyWith(fontSize: 22),
                    ),
                  ),
                  IconButton(
                    tooltip: '이름 바꾸기',
                    icon: const Icon(
                      Icons.edit_outlined,
                      size: 20,
                      color: RidiColors.gray,
                    ),
                    onPressed: () async {
                      final name = await _renameDialog(context, room.name);
                      if (name != null && context.mounted)
                        store.renameRoom(room.id, name);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Text('방 코드', style: RidiText.sub),
                  const SizedBox(width: 12),
                  _CodeChip(code: room.code),
                  if (room.password != null) ...[
                    const SizedBox(width: 10),
                    const Icon(
                      Icons.lock_rounded,
                      size: 16,
                      color: RidiColors.gray,
                    ),
                    const SizedBox(width: 4),
                    const Text('비밀번호', style: RidiText.sub),
                  ],
                  const Spacer(),
                  Text(
                    room.password == null
                        ? '친구에게 알려주면 바로 들어와요'
                        : '코드 + 비밀번호로 들어와요',
                    style: RidiText.sub,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  const Text('함께 읽는 책', style: RidiText.heading),
                  const Spacer(),
                  RidiOutlineButton(
                    '책 추가',
                    icon: Icons.add_rounded,
                    height: 34,
                    onTap: () => _addBooks(context, room),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (books.isEmpty)
                const Text('아직 책이 없어요', style: RidiText.sub)
              else
                for (final b in books)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const RidiCover(width: 40, height: 56),
                    title: Text(b.title, style: RidiText.bodyBold),
                    subtitle: Text(
                      '${b.author} · ${b.chapters}장',
                      style: RidiText.sub,
                    ),
                    trailing: const Text(
                      '이어보기  ›',
                      style: TextStyle(
                        fontFamily: RidiText.f,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: RidiColors.ink,
                      ),
                    ),
                    onTap: () {
                      final nav = Navigator.of(context);
                      store.openBook(b.id, roomId: room.id);
                      nav.pop();
                      nav.push(
                        MaterialPageRoute(
                          builder: (_) =>
                              RidiReaderScreen(bookId: b.id, roomId: room.id),
                        ),
                      );
                    },
                  ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text('멤버 ${room.humanCount}명', style: RidiText.heading),
                  const Spacer(),
                  if (owner)
                    RidiOutlineButton(
                      '관리',
                      icon: Icons.manage_accounts_outlined,
                      height: 34,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => RoomMembersScreen(roomId: room.id),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              for (final m in room.members)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      RidiAvatar(label: m.name, ai: m.ai),
                      const SizedBox(width: 12),
                      Expanded(child: Text(m.name, style: RidiText.body)),
                      if (m.owner) const _Tag('방장'),
                      if (m.ai) const _Tag('AI 독서 친구', purple: true),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              _SpoilerRow(room: room),
              if (owner) ...[
                const SizedBox(height: 16),
                _OwnerRow(
                  title: '최대 인원',
                  sub: '지금 ${room.humanCount}명 · 그보다 적게는 못 줄여요',
                  trailing: RidiStepper(
                    value: room.maxMembers,
                    min: room.humanCount > kRoomMinMembers
                        ? room.humanCount
                        : kRoomMinMembers,
                    max: kRoomMaxMembers,
                    onChanged: (v) => store.setRoomMaxMembers(room.id, v),
                  ),
                ),
                const SizedBox(height: 16),
                _OwnerRow(
                  title: '비밀번호',
                  sub: room.password == null
                      ? '끄면 코드만으로 들어와요'
                      : '코드와 숫자 4자리를 알아야 들어와요',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (room.password != null)
                        TextButton(
                          onPressed: () async {
                            final pw = await showRoomPasswordDialog(
                              context,
                              current: room.password,
                            );
                            if (pw != null) store.setRoomPassword(room.id, pw);
                          },
                          child: const Text(
                            '변경',
                            style: TextStyle(
                              fontFamily: RidiText.f,
                              fontWeight: FontWeight.w700,
                              color: RidiColors.blue,
                            ),
                          ),
                        ),
                      _RidiSwitch(
                        value: room.password != null,
                        onChanged: (v) async {
                          if (!v) {
                            store.setRoomPassword(room.id, null);
                            ridiToast(context, '비밀번호를 껐어요');
                            return;
                          }
                          final pw = await showRoomPasswordDialog(context);
                          if (pw != null) store.setRoomPassword(room.id, pw);
                        },
                      ),
                    ],
                  ),
                ),
              ],
              const Divider(height: 32),
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        RidiAvatar(label: ai?.name ?? '', ai: true, size: 44),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                ai == null ? 'AI 독서 친구 없음' : ai.name,
                                style: RidiText.bodyBold,
                              ),
                              Text(
                                ai?.intro ?? '고르면 방에서 먼저 메모를 남겨요',
                                style: RidiText.sub,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  RidiOutlineButton(
                    ai == null ? '고르기' : '바꾸기',
                    height: 36,
                    onTap: () => showPersonaPicker(context, roomId: room.id),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Center(
                child: TextButton(
                  onPressed: () async {
                    final nav = Navigator.of(context);
                    if (await leaveRoomFlow(context, room)) nav.pop();
                  },
                  child: const Text(
                    '방 나가기',
                    style: TextStyle(
                      fontFamily: RidiText.f,
                      fontSize: 15,
                      color: RidiColors.red,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 방에 없는 책만 골라 추가하는 시트 (RIDI_ROOMS_02 › 책 추가). 다 들어 있으면 안내만
  Future<void> _addBooks(BuildContext context, RidiRoom room) async {
    final store = context.read<RidiStore>();
    final rest = store.books
        .where((b) => !room.bookIds.contains(b.id))
        .toList();
    if (rest.isEmpty) {
      ridiToast(context, '추가할 수 있는 책을 모두 넣었어요');
      return;
    }
    final picked = <String>{};
    final ok = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (ctx) => ScreenTag(
        'RIDI_ROOMS_02 › 책 추가',
        child: StatefulBuilder(
          builder: (ctx, setSheet) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('책 추가', style: RidiText.heading),
                  const SizedBox(height: 12),
                  for (final b in rest)
                    _PickRow(
                      title: b.title,
                      sub: '${b.author} · ${b.chapters}장',
                      picked: picked.contains(b.id),
                      onTap: () => setSheet(
                        () => picked.contains(b.id)
                            ? picked.remove(b.id)
                            : picked.add(b.id),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text(
                          '취소',
                          style: TextStyle(
                            fontFamily: RidiText.f,
                            color: RidiColors.gray,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      RidiButton(
                        picked.isEmpty ? '추가' : '${picked.length}권 추가',
                        height: 44,
                        onTap: picked.isEmpty
                            ? null
                            : () => Navigator.pop(ctx, true),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (ok == true && context.mounted)
      store.addRoomBooks(room.id, picked.toList());
  }
}

/// 방 이름 바꾸기 팝업 (20자, RIDI_ROOMS_02 › 이름 바꾸기). 저장하면 새 이름을 돌려준다
Future<String?> _renameDialog(BuildContext context, String current) {
  final c = TextEditingController(text: current);
  return showDialog<String>(
    context: context,
    builder: (ctx) => ScreenTag(
      'RIDI_ROOMS_02 › 이름 바꾸기',
      child: AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('방 이름 바꾸기', style: RidiText.heading),
        content: RidiInput(
          controller: c,
          hint: '방 이름',
          maxLength: 20,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              '취소',
              style: TextStyle(fontFamily: RidiText.f, color: RidiColors.gray),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, c.text),
            child: const Text(
              '저장',
              style: TextStyle(
                fontFamily: RidiText.f,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// AI 친구 고르기 (방 메뉴 · 뷰어 도구 공통) — UC-05-3. 고른 캐릭터를 다시 누르거나 "없음"이면 AI 친구를 뺀다
Future<void> showPersonaPicker(
  BuildContext context, {
  required String roomId,
}) async {
  final store = context.read<RidiStore>();
  final room = store.room(roomId);
  if (room == null) return;
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
    ),
    builder: (ctx) => ScreenTag(
      'RIDI_ROOMS_02 › AI 친구 고르기',
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${room.name} 의 AI 독서 친구', style: RidiText.heading),
              const SizedBox(height: 4),
              const Text('방 멤버 모두에게 같은 메모가 보여요', style: RidiText.sub),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final p in store.personas)
                    _PersonaCard(
                      persona: p,
                      on: room.personaId == p.id,
                      onTap: () {
                        store.setRoomPersona(
                          room.id,
                          room.personaId == p.id ? null : p.id,
                        );
                        Navigator.pop(ctx);
                      },
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Center(
                child: TextButton(
                  onPressed: () {
                    store.setRoomPersona(room.id, null);
                    Navigator.pop(ctx);
                  },
                  child: const Text(
                    '없이 읽기',
                    style: TextStyle(
                      fontFamily: RidiText.f,
                      fontSize: 14,
                      color: RidiColors.gray,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

// ---------------- 조각들 ----------------
/// 방 만들기 화면의 구역 제목 (+ 작은 설명)
class _Label extends StatelessWidget {
  const _Label(this.text, {this.sub});

  final String text;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Text(text, style: RidiText.heading.copyWith(fontSize: 15)),
          if (sub != null) ...[
            const SizedBox(width: 10),
            Text(sub!, style: RidiText.sub),
          ],
        ],
      ),
    );
  }
}

/// 여러 개 고르기 한 줄 (제목 · 설명 · 선택 원) — 책 선택
class _PickRow extends StatelessWidget {
  const _PickRow({
    required this.title,
    required this.sub,
    required this.picked,
    required this.onTap,
  });

  final String title;
  final String sub;
  final bool picked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: picked ? RidiColors.panel : Colors.white,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              border: Border.all(
                color: picked ? RidiColors.ink : RidiColors.grayLight,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  picked ? Icons.check_circle_rounded : Icons.circle_outlined,
                  size: 20,
                  color: picked ? RidiColors.ink : RidiColors.grayLight,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: RidiText.bodyBold),
                      Text(sub, style: RidiText.sub.copyWith(fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 방 설정 한 줄 — 오른쪽에 값(›) 또는 토글
class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.label,
    this.sub,
    this.value,
    this.onTap,
    this.toggle,
    this.onToggle,
    this.trailing,
  });

  final String label;
  final Widget? trailing;
  final String? sub;
  final String? value;
  final VoidCallback? onTap;
  final bool? toggle;
  final ValueChanged<bool>? onToggle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: RidiColors.grayLight),
          borderRadius: BorderRadius.circular(8),
        ),
        child: InkWell(
          onTap:
              onTap ??
              (onToggle == null ? null : () => onToggle!(!(toggle ?? false))),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: RidiText.body.copyWith(fontSize: 15)),
                    if (sub != null)
                      Text(sub!, style: RidiText.sub.copyWith(fontSize: 12)),
                  ],
                ),
              ),
              if (trailing != null)
                trailing!
              else if (toggle != null)
                _RidiSwitch(value: toggle!, onChanged: onToggle)
              else ...[
                Text(value ?? '', style: RidiText.sub),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: RidiColors.gray,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// AI 친구 고르기 카드 (선택되면 검은 테두리)
class _PersonaCard extends StatelessWidget {
  const _PersonaCard({
    required this.persona,
    required this.on,
    required this.onTap,
  });

  final RidiPersona persona;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: on ? RidiColors.panel : Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 172,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            border: Border.all(
              color: on ? RidiColors.ink : RidiColors.grayLight,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              RidiAvatar(label: persona.name, ai: true, size: 44),
              const SizedBox(height: 8),
              Text(persona.name, style: RidiText.bodyBold),
              Text(persona.tone, style: RidiText.sub.copyWith(fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 멤버 옆 작은 표시 — 방장 / AI 독서 친구(보라)
class _Tag extends StatelessWidget {
  const _Tag(this.text, {this.purple = false});

  final String text;
  final bool purple;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: purple ? const Color(0xFFEDE8F6) : RidiColors.panel,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: RidiText.sub.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: purple ? const Color(0xFF7A5FB0) : RidiColors.gray,
        ),
      ),
    );
  }
}

/// 방 코드 칩 — 누르면 클립보드에 복사
class _CodeChip extends StatelessWidget {
  const _CodeChip({required this.code, this.large = false});

  final String code;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: RidiColors.panel,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () async {
          await Clipboard.setData(ClipboardData(text: code));
          if (context.mounted) ridiToast(context, '방 코드 복사됨: $code');
        },
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: large ? 20 : 12,
            vertical: large ? 12 : 8,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                code,
                style: TextStyle(
                  fontFamily: RidiText.f,
                  fontSize: large ? 26 : 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: large ? 3 : 1,
                  color: RidiColors.ink,
                ),
              ),
              SizedBox(width: large ? 12 : 8),
              Icon(
                Icons.copy_rounded,
                size: large ? 20 : 15,
                color: RidiColors.gray,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 방 설정: 스포일러 잠금 (방장만 바꿈) · 최대 인원
class _SpoilerRow extends StatelessWidget {
  const _SpoilerRow({required this.room});

  final RidiRoom room;

  @override
  Widget build(BuildContext context) {
    final store = context.read<RidiStore>();
    final owner = room.members.any((m) => m.owner && m.name == store.nickname);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('스포일러 잠금', style: RidiText.heading),
              const SizedBox(height: 2),
              Text(
                owner
                    ? '내가 읽은 장보다 뒤의 방 메모는 내용을 가려요'
                    : '방장만 바꿀 수 있어요 · 최대 ${room.maxMembers}명',
                style: RidiText.sub,
              ),
            ],
          ),
        ),
        Switch(
          value: room.spoilerLock,
          onChanged: owner ? (v) => store.setRoomSpoilerLock(room.id, v) : null,
          activeThumbColor: Colors.white,
          activeTrackColor: RidiColors.pillBlack,
          inactiveThumbColor: Colors.white,
          inactiveTrackColor: RidiColors.grayLight,
          trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
        ),
      ],
    );
  }
}

/// 방 메뉴의 방장 설정 한 줄 — 제목 · 설명 · 오른쪽 조작(스테퍼·스위치)
class _OwnerRow extends StatelessWidget {
  const _OwnerRow({
    required this.title,
    required this.sub,
    required this.trailing,
  });

  final String title;
  final String sub;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: RidiText.heading),
              const SizedBox(height: 2),
              Text(sub, style: RidiText.sub),
            ],
          ),
        ),
        trailing,
      ],
    );
  }
}

/// 북체인 스위치 (검은 트랙)
class _RidiSwitch extends StatelessWidget {
  const _RidiSwitch({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Switch(
      value: value,
      onChanged: onChanged,
      activeThumbColor: Colors.white,
      activeTrackColor: RidiColors.pillBlack,
      inactiveThumbColor: Colors.white,
      inactiveTrackColor: RidiColors.grayLight,
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    );
  }
}

// ================= 멤버 관리 =================
/// RIDI_ROOM_MEMBERS_01 멤버 관리 (방장만, 방 메뉴 › 멤버 › 관리)
/// - 내보내기: 방에서 뺀다. 코드(와 비밀번호)가 있으면 다시 들어올 수 있다
/// - 차단: 내보내고 다시 못 들어오게 한다 (코드 입장 시 "이 방에는 들어갈 수 없어요")
/// - 차단 해제: 다시 코드로 들어올 수 있게
/// 서버: DELETE /api/rooms/{id}/members/{memberId} · POST/DELETE /api/rooms/{id}/blocks
class RoomMembersScreen extends StatelessWidget {
  const RoomMembersScreen({super.key, required this.roomId});

  final String roomId;

  @override
  Widget build(BuildContext context) =>
      ScreenTag('RIDI_ROOM_MEMBERS_01', child: _screen(context));

  Widget _screen(BuildContext context) {
    final store = context.watch<RidiStore>();
    final room = store.room(roomId);
    return Scaffold(
      appBar: ridiAppBar(context, '멤버 관리'),
      body: room == null
          ? const RidiEmpty(icon: Icons.groups_2_outlined, text: '방을 찾을 수 없어요')
          : SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
                    children: [
                      Text(
                        '멤버 ${room.humanCount}명 · 최대 ${room.maxMembers}명',
                        style: RidiText.heading,
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        '내보낸 멤버는 코드로 다시 들어올 수 있고, 차단한 멤버는 다시 들어올 수 없어요',
                        style: RidiText.sub,
                      ),
                      const SizedBox(height: 16),
                      for (final m in room.members) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(
                            children: [
                              RidiAvatar(label: m.name, ai: m.ai),
                              const SizedBox(width: 12),
                              Text(m.name, style: RidiText.body),
                              if (m.owner) const _Tag('방장'),
                              if (m.ai) const _Tag('AI 독서 친구', purple: true),
                              const Spacer(),
                              if (!m.owner && !m.ai) ...[
                                RidiOutlineButton(
                                  '방장 넘기기',
                                  height: 34,
                                  onTap: () async {
                                    final ok = await ridiConfirm(
                                      context,
                                      title: '${m.name} 님에게 방장을 넘길까요?',
                                      body:
                                          '넘기면 나는 일반 멤버가 되고, 멤버 관리·비밀번호·인원은 ${m.name} 님이 정해요.',
                                      ok: '넘기기',
                                    );
                                    if (!ok || !context.mounted) return;
                                    store.transferOwner(room.id, m.name);
                                    ridiToast(context, '${m.name} 님이 이제 방장이에요');
                                    Navigator.of(context)
                                        .pop(); // 이제 방장이 아니니 관리 화면을 닫는다
                                  },
                                ),
                                const SizedBox(width: 8),
                                RidiOutlineButton(
                                  '내보내기',
                                  height: 34,
                                  onTap: () async {
                                    final ok = await ridiConfirm(
                                      context,
                                      title: '${m.name} 님을 내보낼까요?',
                                      body: '코드가 있으면 다시 들어올 수 있어요.',
                                      ok: '내보내기',
                                      danger: true,
                                    );
                                    if (!ok || !context.mounted) return;
                                    store.kickMember(room.id, m.name);
                                    ridiToast(context, '${m.name} 님을 내보냈어요');
                                  },
                                ),
                                const SizedBox(width: 8),
                                RidiOutlineButton(
                                  '차단',
                                  icon: Icons.block_rounded,
                                  height: 34,
                                  onTap: () async {
                                    final ok = await ridiConfirm(
                                      context,
                                      title: '${m.name} 님을 차단할까요?',
                                      body: '이 방에서 내보내고, 다시 들어올 수 없어요.',
                                      ok: '차단',
                                      danger: true,
                                    );
                                    if (!ok || !context.mounted) return;
                                    store.blockMember(room.id, m.name);
                                    ridiToast(context, '${m.name} 님을 차단했어요');
                                  },
                                ),
                              ],
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                      ],
                      const SizedBox(height: 32),
                      Text(
                        '차단한 멤버 ${room.blocked.length}명',
                        style: RidiText.heading,
                      ),
                      const SizedBox(height: 8),
                      if (room.blocked.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text('차단한 멤버가 없어요', style: RidiText.sub),
                        )
                      else
                        for (final name in room.blocked) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Row(
                              children: [
                                RidiAvatar(label: name),
                                const SizedBox(width: 12),
                                Text(
                                  name,
                                  style: RidiText.body.copyWith(
                                    color: RidiColors.gray,
                                  ),
                                ),
                                const Spacer(),
                                RidiOutlineButton(
                                  '차단 해제',
                                  height: 34,
                                  onTap: () {
                                    store.unblockMember(room.id, name);
                                    ridiToast(context, '$name 님 차단을 풀었어요');
                                  },
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 1),
                        ],
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

// ================= 방 나가기 =================
/// 방 나가기 확인 (방 메뉴 · 내 서재 편집 공통, D5).
/// - 방장이고 다른 사람이 있으면: "나가면 ○○ 님이 방장이 돼요" (가장 먼저 들어온 사람)
/// - 사람 멤버가 나 혼자면: "방이 사라져요"
/// - 일반 멤버: "코드가 있으면 다시 들어올 수 있어요"
/// 나갔으면 true
Future<bool> leaveRoomFlow(BuildContext context, RidiRoom room) async {
  final store = context.read<RidiStore>();
  final others = store.otherHumans(room);
  final alone = others.isEmpty;
  final next = store.isOwner(room) && !alone ? others.first.name : null;
  final ok = await ridiConfirm(
    context,
    title: '${room.name} 에서 나갈까요?',
    body: alone
        ? '방에 나 혼자라 나가면 방이 사라져요. 방 메모도 함께 사라져요.'
        : next != null
        ? '가장 먼저 들어온 $next 님이 방장이 돼요. 코드가 있으면 다시 들어올 수 있어요.'
        : '코드가 있으면 다시 들어올 수 있어요.',
    ok: alone ? '나가고 방 없애기' : '나가기',
    danger: true,
  );
  if (!ok || !context.mounted) return false;
  store.leaveRoom(room.id);
  if (next != null) ridiToast(context, '$next 님이 이제 방장이에요');
  return true;
}
