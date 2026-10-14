import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../repository/ai_reading_repository.dart';
import 'ridi_theme.dart';
import 'ridi_store.dart';
import 'persona_detail_dialog.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {

  final Map<int, String> _friendColors = {};
  static const _highlightColors = <String, Color>{
    '#FFF59D': Color(0xFFFFF59D),
    '#F8BBD0': Color(0xFFF8BBD0),
    '#A5D6A7': Color(0xFFA5D6A7),
    '#90CAF9': Color(0xFF90CAF9),
    '#CE93D8': Color(0xFFCE93D8),
    '#FFCC80': Color(0xFFFFCC80),
    '#EF9A9A': Color(0xFFEF9A9A),
    '#80CBC4': Color(0xFF80CBC4),
    '#B3E5FC': Color(0xFFB3E5FC),
    '#BDBDBD': Color(0xFFBDBDBD),
  };
  static const _colorNames = <String, String>{
    '#FFF59D': '노랑', '#F8BBD0': '분홍', '#A5D6A7': '초록',
    '#90CAF9': '파랑', '#CE93D8': '보라', '#FFCC80': '주황',
    '#EF9A9A': '빨강', '#80CBC4': '민트', '#B3E5FC': '하늘', '#BDBDBD': '회색',
  };
  final Set<int> _savingColors = {};

  Future<void> _chooseFriendColor(int friendId) async {
    if (_savingColors.contains(friendId)) return;
    final previous = _friendColors[friendId] ?? '#FFF59D';
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('형광펜 색상'),
        content: SizedBox(
          width: 300,
          child: Wrap(
            spacing: 12,
            runSpacing: 16,
            children: _highlightColors.entries.map((entry) {
              final active = entry.key == previous;
              return Semantics(
                button: true,
                selected: active,
                label: _colorNames[entry.key],
                child: InkWell(
                  onTap: () => Navigator.pop(dialogContext, entry.key),
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 48,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: entry.value,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: active ? Colors.black87 : Colors.black12,
                              width: active ? 2 : 1,
                            ),
                          ),
                          child: active ? const Icon(Icons.check, size: 22) : null,
                        ),
                        const SizedBox(height: 4),

                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        actions: [TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('취소'),
        )],
      ),
    );
    if (!mounted || selected == null || selected == previous) return;
    _savingColors.add(friendId);
    setState(() => _friendColors[friendId] = selected);
    try {
      final token = context.read<RidiStore>().accessToken;
      await AiReadingRepository(ApiClient(tokenProvider: () => token))
          .saveFriendHighlightColor(friendId: friendId, color: selected);
    } catch (e) {
      if (!mounted) return;
      setState(() => _friendColors[friendId] = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('형광펜 색상 저장 실패: $e')),
      );
    } finally {
      _savingColors.remove(friendId);
    }
  }


  List<_AiFriend> _friends = [];
  bool _isLoading = true;

  int _selectedIndex = 0;
  bool _isCreating = false;
  bool _submitting = false;

  final _nameController = TextEditingController();
  final _ageController = TextEditingController();
  final _relationshipController = TextEditingController();
  final _personalityController = TextEditingController();
  final _speechController = TextEditingController();
  final _featureController = TextEditingController();

  _AiFriend? _editingFriend;
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


      final allFriends = [
        ...loaded[0],
        ...loaded[1],
      ];

      final loadedColors = <int, String>{};

      await Future.wait(
        allFriends.map((friend) async {
          try {
            final color = await repository.getFriendHighlightColor(friend.id);
            loadedColors[friend.id] = color;
          } catch (e) {
            debugPrint('AI 친구 ${friend.id} 색상 조회 실패: $e');
            loadedColors[friend.id] = '#FFF59D';
          }
        }),
      );


      if (!mounted) return;


      setState(() {
        _friends = [
          ...loaded[0].map(_friendFromApi),
          ...loaded[1].map(_friendFromApi),
        ];

        _friendColors
          ..clear()
          ..addAll(loadedColors);

        _selectedIndex = 0;
        _isLoading = false;
      });

    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('AI 친구 목록을 불러오지 못했어요: $e')));
    }
  }

  _AiFriend _friendFromApi(AiReadingFriend friend) {
    final persona = friend.persona ?? '';

    String section(String title, List<String> nextTitles) {
      final lines = persona.split('\n');
      final heading = RegExp(
        r'^#{1,3}\s*(?:\d+\.\s*)?' + RegExp.escape(title) + r'\s*$',
      );

      final nextHeadings = nextTitles.map(
            (item) =>
            RegExp(r'^#{1,3}\s*(?:\d+\.\s*)?' + RegExp.escape(item) + r'\s*$'),
      );

      final result = <String>[];
      var reading = false;

      for (final line in lines) {
        final trimmed = line.trim();

        if (heading.hasMatch(trimmed)) {
          reading = true;
          continue;
        }

        if (reading && nextHeadings.any((regex) => regex.hasMatch(trimmed))) {
          break;
        }

        if (reading) result.add(line);
      }

      return result.join('\n').trim();
    }

    final profile = section('기본 프로필', ['성격', '생활과 경험', '말하는 방식']);

    final personality = section('성격', ['생활과 경험', '말하는 방식']);

    final experience = section('생활과 경험', ['말하는 방식']);

    final speech = section('말하는 방식', []);

    final ageMatch = RegExp(r'(\d+)\s*(?:살|세|대)').firstMatch(profile);
    final age = ageMatch == null ? 0 : int.tryParse(ageMatch.group(1)!) ?? 0;

    final gender = profile.contains('여성')
        ? '여자'
        : profile.contains('남성')
        ? '남자'
        : '';


    return _AiFriend(
      id: friend.id,
      name: friend.name,
      age: int.tryParse(friend.inputAge ?? '') ?? age,
      gender: friend.inputGender ?? gender,
      relationship: friend.inputRelationship ?? '',
      personality: friend.inputPersonality ?? '',
      speech: friend.inputSpeechStyle ?? '',
      feature: friend.inputTraits ?? '',
      isDefault: friend.isDefault,

      // DB에 저장된 전체 페르소나
      persona: friend.persona ?? '',
    );

  }

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
    _nameController.clear();
    _ageController.clear();
    _relationshipController.clear();
    _personalityController.clear();
    _speechController.clear();
    _featureController.clear();

    setState(() {
      _editingFriend = null;
      _gender = '여자';
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

    try {
      final token = context.read<RidiStore>().accessToken;

      final saved = await AiReadingRepository(
        ApiClient(tokenProvider: () => token),
      ).createFriend(
        name: name,
        age: _ageController.text.trim(),
        gender: _gender,
        relationship: relationship,
        personality: personality,
        speechStyle: speech,
        traits: feature,
      );

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
              child: Row(
                children: [
                  // 왼쪽: AI 친구 목록만 가로 스크롤
                  Expanded(
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _friends.length,
                      separatorBuilder: (_, _) =>
                      const SizedBox(width: 16),
                      itemBuilder: (context, index) {
                        final friend = _friends[index];

                        return _FriendCard(
                          friend: friend,
                          selected: _selectedIndex == index &&
                              (!_isCreating ||
                                  _editingFriend?.id == friend.id),
                          onTap: () => _selectFriend(index),
                        );
                      },
                    ),
                  ),

                  const SizedBox(width: 16),

                  // 오른쪽: AI 친구 만들기 버튼 고정
                  SizedBox(
                    width: 170,
                    child: _CreateFriendCard(
                      selected: _isCreating && _editingFriend == null,
                      onTap: _startCreating,
                    ),
                  ),
                ],
              ),
            ),


            const SizedBox(height: 24),

            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: _isCreating
                  ? _buildCreatePanel()
                  : _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _friends.isEmpty
                  ? const Center(child: Text('표시할 AI 친구가 없어요.'))
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
              friend.name.characters.take(2).toString(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
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
                    Flexible(
                      child: Text(
                        friend.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        softWrap: true,
                        style: const TextStyle(
                          fontFamily: RidiText.f,
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: RidiColors.ink,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Tooltip(
                      message: '형광펜 색상 변경',
                      child: InkWell(
                        onTap: friend.id == null
                            ? null
                            : () => _chooseFriendColor(friend.id!),
                        borderRadius: BorderRadius.circular(20),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: _highlightColors[_friendColors[friend.id] ?? '#FFF59D'],
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.black26),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const Spacer(),
                    const SizedBox(width: 12),

                    // 기본 AI 친구는 수정 및 삭제 불가
                    // 사용자가 생성한 AI 친구만 수정 및 삭제 가능

                    if (!friend.isDefault) ...[
                      // 상세 보기
                      OutlinedButton(
                        onPressed: friend.id == null
                            ? null
                            : () {
                          showDialog<void>(
                            context: context,
                            builder: (dialogContext) => PersonaDetailDialog(
                              persona: friend.persona,
                            ),
                          );
                        },
                        child: const Text('상세 보기'),
                      ),

                      const SizedBox(width: 8),

// 수정
                      OutlinedButton(
                        onPressed: friend.id == null
                            ? null
                            : () => _editFriend(friend),
                        child: const Text('수정'),
                      ),

                      const SizedBox(width: 8),

// 삭제
                      OutlinedButton(
                        onPressed: friend.id == null
                            ? null
                            : () => _deleteFriend(friend),
                        child: const Text('삭제'),
                      ),
                    ],


                  ],
                ),

                const SizedBox(height: 14),


                Text(
                  friend.gender.trim().isEmpty || friend.gender.trim() == '없음'
                      ? '${friend.age}살'
                      : '${friend.age}살 · ${friend.gender}',
                  style: RidiText.sub,
                ),



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


  void _editFriend(_AiFriend friend) {
    if (friend.isDefault || friend.id == null) {
      return;
    }

    _nameController.text = friend.name;
    _ageController.text = friend.age?.toString() ?? '';
    _relationshipController.text = friend.relationship;
    _personalityController.text = friend.personality;
    _speechController.text = friend.speech;
    _featureController.text = friend.feature;

    setState(() {
      _editingFriend = friend;
      _isCreating = true;
      _gender = ['남자', '여자', '없음'].contains(friend.gender)
          ? friend.gender
          : '없음';
    });
  }


  Widget _buildCreatePanel() {

    Future<void> _updateFriend() async {
      final friend = _editingFriend;

      if (friend == null || friend.id == null || friend.isDefault) {
        return;
      }

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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('모든 항목을 입력해 주세요.')),
        );
        return;
      }

      if (_submitting) return;
      setState(() => _submitting = true);

      try {
        final token = context.read<RidiStore>().accessToken;

        final saved = await AiReadingRepository(
          ApiClient(tokenProvider: () => token),
        ).updateFriend(
          friendId: friend.id!,
          name: name,
          age: _ageController.text.trim(),
          gender: _gender,
          relationship: relationship,
          personality: personality,
          speechStyle: speech,
          traits: feature,
        );

        if (!mounted) return;

        setState(() {
          final index = _friends.indexWhere((item) => item.id == saved.id);

          if (index >= 0) {
            _friends[index] = _friendFromApi(saved);
            _selectedIndex = index;
          }

          _editingFriend = null;
          _isCreating = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('AI 친구 정보가 수정되었습니다.')),
        );
      } on ApiException catch (e) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      } catch (e) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('수정 중 오류가 발생했습니다: $e')),
        );
      } finally {
        if (mounted) {
          setState(() => _submitting = false);
        }
      }
    }

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

          Text(
            _editingFriend == null
                ? '새로운 AI 친구 만들기'
                : 'AI 친구 수정하기',
            style: RidiText.heading,
          ),


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
              onPressed: _submitting
                  ? null
                  : _editingFriend == null
                  ? _createFriend
                  : () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: const Text('AI 친구 수정 안내'),
                    content: const Text(
                      'AI 친구의 정보를 수정하면 AI 페르소나가 다시 생성되어 '
                          '기존 캐릭터의 성격, 말투, 대화 방식 등이 달라질 수 있습니다.\n\n'
                          '계속 수정하시겠습니까?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () =>
                            Navigator.pop(dialogContext, false),
                        child: const Text('취소'),
                      ),
                      FilledButton(
                        onPressed: () =>
                            Navigator.pop(dialogContext, true),
                        child: const Text('수정 저장'),
                      ),
                    ],
                  ),
                );

                if (!mounted || confirmed != true) return;

                await _updateFriend();
              },
              child: Text(
                _editingFriend == null ? 'AI 친구 만들기' : '수정 저장',
              ),
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
              child: Text(
                friend.name.characters.take(2).toString(),
                style: RidiText.heading,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),

            const SizedBox(height: 10),

            Text(
              friend.name,
              style: RidiText.bodyBold,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              softWrap: true,
            ),

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
    this.persona = '',
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

  // AI가 생성한 전체 페르소나
  final String persona;
}

