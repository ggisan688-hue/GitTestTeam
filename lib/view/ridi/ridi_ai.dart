import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'ridi_store.dart';
import 'ridi_theme.dart';
import 'ridi_widgets.dart';
import '../../widgets/screen_tag.dart';

/// RIDI_AI_01 / RIDI_AI_02 — UC-05-3 AI친구선택, UC-09 AI친구생성
/// AI 친구는 "방마다 하나" 이므로, 고르면 어느 방에 적용할지 먼저 묻는다.
class AiFriendScreen extends StatefulWidget {
  const AiFriendScreen({super.key});

  @override
  State<AiFriendScreen> createState() => _AiFriendScreenState();
}

class _AiFriendScreenState extends State<AiFriendScreen> {
  final _name = TextEditingController();
  final _intro = TextEditingController();
  String _tone = '분석적';
  bool _form = false;

  static const _tones = ['감성적', '분석적', '유머러스', '차분함'];

  @override
  void dispose() {
    _name.dispose();
    _intro.dispose();
    super.dispose();
  }

  /// 캐릭터를 방에 적용 — 방이 하나면 바로, 여럿이면 고르는 시트(RIDI_AI_01 › 방 고르기). 방이 없으면 안내만
  Future<void> _apply(RidiPersona p) async {
    final store = context.read<RidiStore>();
    if (store.rooms.isEmpty) {
      ridiToast(context, '먼저 독서방을 만들어주세요');
      return;
    }
    final rooms = store.rooms;
    final target = rooms.length == 1
        ? rooms.first
        : await showModalBottomSheet<RidiRoom>(
            context: context,
            backgroundColor: Colors.white,
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(14))),
            builder: (ctx) => ScreenTag('RIDI_AI_01 › 방 고르기', child: SafeArea(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const SizedBox(height: 16),
                Text('${p.name} 을(를) 어느 방에 둘까요?', style: RidiText.heading),
                const SizedBox(height: 8),
                for (final r in rooms)
                  ListTile(
                    leading: const Icon(Icons.groups_2_outlined, color: RidiColors.gray),
                    title: Text(r.name, style: RidiText.body),
                    subtitle: Text('${r.humanCount}명 · 현재 ${store.persona(r.personaId)?.name ?? "없음"}', style: RidiText.sub),
                    onTap: () => Navigator.pop(ctx, r),
                  ),
                const SizedBox(height: 12),
              ]),
            )),
          );
    if (target == null || !mounted) return;
    store.setRoomPersona(target.id, p.id);
    if (!mounted) return;
    ridiToast(context, '${target.name} 에서 ${p.name} 이(가) 함께 읽어요');
  }

  /// 새 AI 친구 만들기 — 이름 필수, 말투 칩 1개, 성격 한 줄(선택). 만들면 카드 목록에 추가하고 폼을 닫는다
  void _create() {
    if (_name.text.trim().isEmpty) {
      ridiToast(context, '이름을 적어주세요');
      return;
    }
    final p = context.read<RidiStore>().createPersona(name: _name.text, tone: _tone, intro: _intro.text);
    _name.clear();
    _intro.clear();
    setState(() => _form = false);
    ridiToast(context, '${p.name} 이(가) 만들어졌어요');
  }

  @override
  Widget build(BuildContext context) => ScreenTag(_form ? 'RIDI_AI_02' : 'RIDI_AI_01', alignment: Alignment.topCenter, child: _screen(context));

  Widget _screen(BuildContext context) {
    final store = context.watch<RidiStore>();
    // 방에 이미 들어가 있는 AI 친구 id 모음
    final inUse = {for (final r in store.rooms) r.personaId};

    return Scaffold(
      appBar: AppBar(title: const Text('AI 친구')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          children: [
            Row(children: [
              const Text('내 AI 독서 친구', style: RidiText.heading),
              const SizedBox(width: 10),
              const Text('방마다 하나를 고를 수 있어요', style: RidiText.sub),
            ]),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                for (final p in store.personas) _Card(persona: p, inUse: inUse.contains(p.id), onPick: () => _apply(p)),
                _NewCard(onTap: () => setState(() => _form = !_form)),
              ],
            ),
            if (_form) ...[
              const SizedBox(height: 28),
              const Text('새 AI 친구 만들기', style: RidiText.heading),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: RidiInput(controller: _name, hint: '이름', maxLength: 10, autofocus: true)),
                const SizedBox(width: 16),
                Expanded(
                  child: Row(children: [
                    for (final t in _tones)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: RidiChip(t, on: _tone == t, onTap: () => setState(() => _tone = t)),
                      ),
                  ]),
                ),
              ]),
              const SizedBox(height: 16),
              RidiInput(controller: _intro, hint: '성격 한 줄 — 예: 인물 관계를 잘 짚어 주고 질문을 자주 던져요', maxLength: 40),
              const SizedBox(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(
                  onPressed: () => setState(() => _form = false),
                  child: const Text('취소', style: TextStyle(fontFamily: RidiText.f, color: RidiColors.gray)),
                ),
                const SizedBox(width: 8),
                RidiButton('만들기', onTap: _create, height: 46),
              ]),
            ],
            const SizedBox(height: 28),
            if (store.rooms.isNotEmpty) ...[
              const Text('방별 AI 친구', style: RidiText.heading),
              const SizedBox(height: 8),
              for (final r in store.rooms)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(children: [
                    RidiAvatar(label: store.persona(r.personaId)?.name ?? '', ai: true),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(r.name, style: RidiText.bodyBold),
                        Text(store.persona(r.personaId)?.intro ?? 'AI 친구 없음', style: RidiText.sub),
                      ]),
                    ),
                  ]),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 캐릭터 카드 — 이름 · 성격 · 예시 대사. 어느 방에서 쓰고 있으면 "사용 중" 배지
class _Card extends StatelessWidget {
  const _Card({required this.persona, required this.inUse, required this.onPick});

  final RidiPersona persona;
  final bool inUse;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: inUse ? RidiColors.panel : Colors.white,
        border: Border.all(color: inUse ? RidiColors.ink : RidiColors.grayLight),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          RidiAvatar(label: persona.name, ai: true, size: 56),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(persona.name, style: RidiText.title),
              Text(persona.intro, style: RidiText.sub, maxLines: 2),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        Text(persona.sample, style: RidiText.body.copyWith(fontSize: 13)),
        const SizedBox(height: 12),
        Row(children: [
          RidiOutlineButton(inUse ? '다른 방에도' : '고르기', height: 32, onTap: onPick),
          const Spacer(),
          if (inUse)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: RidiColors.pillBlack, borderRadius: BorderRadius.circular(14)),
              child: const Text('사용 중', style: TextStyle(fontFamily: RidiText.f, fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
            ),
        ]),
      ]),
    );
  }
}

/// "새 AI 친구 만들기" 카드 — 누르면 아래 입력 폼(RIDI_AI_02)을 펼친다
class _NewCard extends StatelessWidget {
  const _NewCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 260,
        height: 168,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: RidiColors.gray, style: BorderStyle.solid),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: RidiColors.grayLight, width: 2)),
            child: const Icon(Icons.add_rounded, color: RidiColors.gray, size: 28),
          ),
          const SizedBox(height: 12),
          const Text('새 AI 친구 만들기', style: RidiText.bodyBold),
          const SizedBox(height: 4),
          const Text('이름 · 말투 · 성격 정하기', style: RidiText.sub),
        ]),
      ),
    );
  }
}
