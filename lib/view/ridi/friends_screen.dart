import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../repository/ai_reading_repository.dart';
import 'ridi_theme.dart';
import 'ridi_store.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  List<_AiFriend> _friends = const [
    _AiFriend(
      name: 'A',
      age: 18,
      gender: '여자',
      relationship: '온라인에서 만난 편한 친구',
      personality: '반응이 빠르고 장난기가 많아요.',
      speech: '또래 친구처럼 편하고 자연스럽게 말해요.',
      feature: '사람 관계에 쉽게 과몰입하고 인터넷 문화에 익숙해요.',
      isDefault: true,
    ),
    _AiFriend(
      name: 'B',
      age: 22,
      gender: '여자',
      relationship: '편하게 이야기할 수 있는 친구',
      personality: '차분하고 다정한 성격이에요.',
      speech: '상대방의 이야기를 잘 들어주며 부드럽게 말해요.',
      feature: '작은 감정의 변화도 잘 알아차리는 편이에요.',
      isDefault: true,
    ),
    _AiFriend(
      name: 'C',
      age: 24,
      gender: '남자',
      relationship: '솔직하게 이야기하는 친구',
      personality: '현실적이고 솔직한 성격이에요.',
      speech: '돌려 말하기보다는 생각을 편하게 이야기해요.',
      feature: '상황을 객관적으로 보는 편이에요.',
      isDefault: true,
    ),
  ];

  int _selectedIndex = 0;
  bool _isCreating = false;
  bool _submitting = false;

  final _nameController = TextEditingController();
  final _ageController = TextEditingController();
  final _relationshipController = TextEditingController();
  final _personalityController = TextEditingController();
  final _speechController = TextEditingController();
  final _featureController = TextEditingController();

  String _gender = '여자';

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  Future<void> _loadFriends() async {
    try {
      final token = context.read<RidiStore>().accessToken;
      final repository = AiReadingRepository(
        ApiClient(tokenProvider: () => token),
      );
      final loaded = await Future.wait([
        repository.getDefaultFriends(),
        repository.getMyFriends(),
      ]);
      final custom = loaded[1];
      if (!mounted) return;
      setState(() {
        _friends = [
          ...loaded[0].map(_friendFromApi),
          ...custom.map(
            (friend) => _AiFriend(
              id: friend.id,
              name: friend.name,
              age: 0,
              gender: '사용자 설정',
              relationship: '',
              personality: friend.persona ?? '',
              speech: '',
              feature: '',
              isDefault: false,
            ),
          ),
        ];
        _selectedIndex = _selectedIndex.clamp(0, _friends.length - 1).toInt();
      });
    } catch (_) {
      // Built-ins remain available while a background refresh fails.
    }
  }

  _AiFriend _friendFromApi(AiReadingFriend friend) => _AiFriend(
    id: friend.id,
    name: friend.name,
    age: 0,
    gender: '',
    relationship: '',
    personality: friend.persona ?? '',
    speech: '',
    feature: '',
    isDefault: friend.isDefault,
  );

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    _relationshipController.dispose();
    _personalityController.dispose();
    _speechController.dispose();
    _featureController.dispose();
    super.dispose();
  }

  void _selectFriend(int index) {
    setState(() {
      _selectedIndex = index;
      _isCreating = false;
    });
  }

  void _startCreating() {
    setState(() {
      _isCreating = true;
    });
  }

  Future<void> _createFriend() async {
    final name = _nameController.text.trim();
    final relationship = _relationshipController.text.trim();
    final personality = _personalityController.text.trim();
    final speech = _speechController.text.trim();
    final feature = _featureController.text.trim();
    if (name.isEmpty ||
        relationship.isEmpty ||
        personality.isEmpty ||
        speech.isEmpty ||
        feature.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('모든 항목을 입력해 주세요.')));
      return;
    }
    if (_submitting) return;
    setState(() => _submitting = true);
    final persona =
        '나이: ${_ageController.text.trim()}\n성별: $_gender\n관계: $relationship\n성격: $personality\n말투: $speech\n특징: $feature';
    try {
      final token = context.read<RidiStore>().accessToken;
      final saved = await AiReadingRepository(
        ApiClient(tokenProvider: () => token),
      ).createFriend(name: name, persona: persona);
      if (!mounted) return;
      setState(() {
        _friends = [
          ..._friends,
          _AiFriend(
            id: saved.id,
            name: saved.name,
            age: int.tryParse(_ageController.text.trim()) ?? 0,
            gender: _gender,
            relationship: relationship,
            personality: personality,
            speech: speech,
            feature: feature,
            isDefault: false,
          ),
        ];
        _selectedIndex = _friends.length - 1;
        _isCreating = false;
      });
      _nameController.clear();
      _ageController.clear();
      _relationshipController.clear();
      _personalityController.clear();
      _speechController.clear();
      _featureController.clear();
    } on ApiException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI 친구')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(44, 24, 44, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('함께 책을 읽을 AI 친구를 만나보세요.', style: RidiText.sub),

            const SizedBox(height: 22),

            SizedBox(
              height: 150,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _friends.length + 1,
                separatorBuilder: (_, _) => const SizedBox(width: 16),
                itemBuilder: (context, index) {
                  if (index == _friends.length) {
                    return _CreateFriendCard(
                      selected: _isCreating,
                      onTap: _startCreating,
                    );
                  }

                  final friend = _friends[index];

                  return _FriendCard(
                    friend: friend,
                    selected: !_isCreating && _selectedIndex == index,
                    onTap: () => _selectFriend(index),
                  );
                },
              ),
            ),

            const SizedBox(height: 24),

            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: _isCreating
                  ? _buildCreatePanel()
                  : _buildFriendDetail(_friends[_selectedIndex]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFriendDetail(_AiFriend friend) {
    return Container(
      key: ValueKey('detail-${friend.name}'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 42, vertical: 30),
      decoration: BoxDecoration(
        color: RidiColors.bg,
        border: Border.all(color: RidiColors.grayLight),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 54,
            backgroundColor: RidiColors.panel,
            child: Text(
              friend.name,
              style: const TextStyle(
                fontFamily: RidiText.f,
                fontSize: 32,
                fontWeight: FontWeight.w700,
                color: RidiColors.ink,
              ),
            ),
          ),

          const SizedBox(width: 42),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      friend.name,
                      style: const TextStyle(
                        fontFamily: RidiText.f,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: RidiColors.ink,
                      ),
                    ),
                    const SizedBox(width: 12),

                    // 기본 A/B/C는 수정 불가.
                    // 이후 사용자가 만든 친구만 수정 버튼 표시.
                    if (!friend.isDefault)
                      OutlinedButton(
                        onPressed: friend.id == null
                            ? null
                            : () => _deleteFriend(friend),
                        child: const Text('삭제'),
                      ),
                  ],
                ),

                const SizedBox(height: 6),

                Text('${friend.age}살 · ${friend.gender}', style: RidiText.sub),

                const SizedBox(height: 26),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _DetailRow(
                        label: '나와의 관계',
                        value: friend.relationship,
                      ),
                    ),
                    const SizedBox(width: 48),
                    Expanded(
                      child: _DetailRow(label: '성격', value: friend.personality),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _DetailRow(label: '특징', value: friend.feature),
                    ),
                    const SizedBox(width: 48),
                    Expanded(
                      child: _DetailRow(label: '말투', value: friend.speech),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteFriend(_AiFriend friend) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('AI 친구 삭제'),
        content: Text('${friend.name}을(를) 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || friend.id == null) return;
    try {
      final token = context.read<RidiStore>().accessToken;
      await AiReadingRepository(ApiClient(tokenProvider: () => token))
          .deleteFriend(friend.id!);
      if (!mounted) return;
      setState(() {
        _friends = _friends.where((item) => item.id != friend.id).toList();
        _selectedIndex = _selectedIndex.clamp(0, _friends.length - 1).toInt();
      });
    } on ApiException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Widget _buildCreatePanel() {
    return Container(
      key: const ValueKey('create'),
      width: double.infinity,
      decoration: BoxDecoration(
        color: RidiColors.bg,
        border: Border.all(color: RidiColors.grayLight),
        borderRadius: BorderRadius.circular(16),
      ),

      // 상단 친구 카드는 그대로 두고
      // 생성 폼 안쪽만 세로 스크롤
      padding: const EdgeInsets.fromLTRB(34, 26, 34, 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('새로운 AI 친구 만들기', style: RidiText.heading),

          const SizedBox(height: 24),

          // 이름 / 나이 / 성별
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _InputField(
                  label: '이름',
                  controller: _nameController,
                  hint: '예) hihi',
                ),
              ),

              const SizedBox(width: 18),

              SizedBox(
                width: 150,
                child: _InputField(
                  label: '나이',
                  controller: _ageController,
                  hint: '예) 20',
                  keyboardType: TextInputType.number,
                ),
              ),

              const SizedBox(width: 18),

              SizedBox(
                width: 180,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('성별', style: RidiText.bodyBold),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: _gender,
                      decoration: _inputDecoration(),
                      items: const [
                        DropdownMenuItem(value: '여자', child: Text('여자')),
                        DropdownMenuItem(value: '남자', child: Text('남자')),
                        DropdownMenuItem(value: '없음', child: Text('없음')),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            _gender = value;
                          });
                        }
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 26),

          // 나와의 관계
          _InputField(
            label: '나와의 관계',
            controller: _relationshipController,
            hint: '예) 아는 동생! 친하다',
            minLines: 3,
            maxLines: 6,
          ),

          const SizedBox(height: 24),

          // 성격
          _InputField(
            label: '성격',
            controller: _personalityController,
            hint: '예) 유쾌발랄상쾌. 항상 밝아서 보기 좋다.',
            minLines: 3,
            maxLines: 6,
          ),

          const SizedBox(height: 24),

          // 말투
          _InputField(
            label: '말투',
            controller: _speechController,
            hint: '예) 나를 언니라고 부름. 또래 여학생 말투다.',
            minLines: 3,
            maxLines: 6,
          ),

          const SizedBox(height: 24),

          // 특징
          _InputField(
            label: '특징',
            controller: _featureController,
            hint: '예) 사소한 거에도 감동 받고, 기뻐하는 타입',
            minLines: 3,
            maxLines: 6,
          ),

          const SizedBox(height: 28),

          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: _submitting ? null : _createFriend,
              child: const Text('AI 친구 만들기'),
            ),
          ),
        ],
      ),
    );
  }
}

class _FriendCard extends StatelessWidget {
  const _FriendCard({
    required this.friend,
    required this.selected,
    required this.onTap,
  });

  final _AiFriend friend;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 170,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected
              ? RidiColors.blue.withValues(alpha: 0.06)
              : RidiColors.bg,
          border: Border.all(
            color: selected ? RidiColors.blue : RidiColors.grayLight,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 25,
              backgroundColor: RidiColors.panel,
              child: Text(friend.name, style: RidiText.heading),
            ),
            const SizedBox(height: 10),
            Text(friend.name, style: RidiText.bodyBold),
          ],
        ),
      ),
    );
  }
}

class _CreateFriendCard extends StatelessWidget {
  const _CreateFriendCard({required this.selected, required this.onTap});

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 170,
        decoration: BoxDecoration(
          color: selected
              ? RidiColors.blue.withValues(alpha: 0.06)
              : RidiColors.bg,
          border: Border.all(
            color: selected ? RidiColors.blue : RidiColors.grayLight,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add, size: 34, color: RidiColors.blue),
            SizedBox(height: 10),
            Text('AI 친구 만들기', style: RidiText.bodyBold),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: RidiText.bodyBold),
        const SizedBox(height: 5),
        Text(value, style: RidiText.body),
      ],
    );
  }
}

class _InputField extends StatelessWidget {
  const _InputField({
    required this.label,
    required this.controller,
    required this.hint,
    this.keyboardType,
    this.minLines,
    this.maxLines = 1,
  });

  final String label;
  final TextEditingController controller;
  final String hint;
  final TextInputType? keyboardType;
  final int? minLines;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: RidiText.bodyBold),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          minLines: minLines,
          maxLines: maxLines,
          textAlignVertical: TextAlignVertical.top,
          decoration: _inputDecoration(hint: hint),
        ),
      ],
    );
  }
}

InputDecoration _inputDecoration({String? hint}) {
  return InputDecoration(
    hintText: hint,
    hintStyle: RidiText.sub,
    filled: true,
    fillColor: RidiColors.bg,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: RidiColors.grayLight),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: RidiColors.blue, width: 1.5),
    ),
  );
}

class _AiFriend {
  const _AiFriend({
    this.id,
    required this.name,
    required this.age,
    required this.gender,
    required this.relationship,
    required this.personality,
    required this.speech,
    required this.feature,
    required this.isDefault,
  });

  final int? id;
  final String name;
  final int age;
  final String gender;
  final String relationship;
  final String personality;
  final String speech;
  final String feature;
  final bool isDefault;
}
