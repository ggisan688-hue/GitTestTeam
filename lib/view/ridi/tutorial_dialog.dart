import 'package:flutter/material.dart';

/// 첫 가입 안내창 (튜토리얼). 홈 화면의 ? 버튼으로 언제든 다시 볼 수 있다.
/// 사진은 assets/tutorial/t1.jpg ~ t5.jpg (pubspec.yaml 에 assets/tutorial/ 등록 필요).
Future<void> showTutorialDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _TutorialDialog(),
  );
}

const _blue = Color(0xFF1F8CEB);

class _TutorialPage {
  const _TutorialPage({
    required this.icon,
    required this.title,
    required this.lines,
    this.image,
  });

  final IconData icon;
  final String title;
  final List<String> lines;
  final String? image;
}

const _pages = <_TutorialPage>[
  _TutorialPage(
    icon: Icons.menu_book_rounded,
    title: '북체인에 오신 것을 환영해요!',
    lines: [
      '친구와 같은 책을 읽으며',
      '메모를 나누는 앱이에요.',
      '[다음]을 눌러 사용법을 확인해요.',
    ],
  ),
  _TutorialPage(
    icon: Icons.groups_rounded,
    title: '1. 독서 방 들어가기',
    image: 'assets/tutorial/t1.jpg',
    lines: [
      '[내 서재] → [교환독서]에서',
      '[+ 방 만들기]로 새 방을 만들거나',
      '[코드 참여]로 친구 방에 들어가요.',
    ],
  ),
  _TutorialPage(
    icon: Icons.add_circle_outline,
    title: '2. 독서 방 만들기',
    image: 'assets/tutorial/t2.jpg',
    lines: [
      '방 이름을 쓰고 함께 읽을 책을 골라요.',
      '[만들기]를 누르면 방이 생겨요.',
    ],
  ),
  _TutorialPage(
    icon: Icons.vpn_key_outlined,
    title: '3. 방 코드 공유하기',
    image: 'assets/tutorial/t3.jpg',
    lines: [
      '방 코드를 복사해서 친구에게 보내요.',
      '친구가 그 코드를 입력하면',
      '내 방에 들어올 수 있어요.',
    ],
  ),
  _TutorialPage(
    icon: Icons.sticky_note_2_outlined,
    title: '4. 독서노트로 한눈에 보기',
    image: 'assets/tutorial/t4.jpg',
    lines: [
      '책 읽는 중 [독서노트]를 누르면',
      '메모·형광펜·책갈피를 한눈에 봐요.',
      '아직 안 읽은 부분의 메모는 가려져요.',
    ],
  ),
  _TutorialPage(
    icon: Icons.auto_awesome_outlined,
    title: '5. 책 읽으며 AI 친구 쓰기',
    image: 'assets/tutorial/t5.jpg',
    lines: [
      '책 읽는 중 [보기 설정]을 눌러요.',
      '[AI 친구 설정]에서 친구를 고르고 [완료]!',
      '이 안내는 홈의 ? 버튼으로 다시 볼 수 있어요.',
    ],
  ),
];

class _TutorialDialog extends StatefulWidget {
  const _TutorialDialog();

  @override
  State<_TutorialDialog> createState() => _TutorialDialogState();
}

class _TutorialDialogState extends State<_TutorialDialog> {
  final PageController _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_index >= _pages.length - 1) {
      Navigator.of(context).pop();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _prev() {
    if (_index <= 0) return;
    _controller.previousPage(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  /// 사진을 누르면 크게 보기 (손가락으로 확대 가능)
  void _zoom(String path) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: SizedBox.expand(
          child: Stack(
            children: [
              Positioned.fill(
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 5,
                  child: Center(
                    child: Image.asset(path, fit: BoxFit.contain),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 28),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bodyHeight =
    (MediaQuery.sizeOf(context).height - 260).clamp(300.0, 540.0).toDouble();
    final last = _index == _pages.length - 1;
    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 4, right: 8),
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('건너뛰기'),
                ),
              ),
            ),
            SizedBox(
              height: bodyHeight,
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (_, i) =>
                    _TutorialSlide(page: _pages[i], onZoom: _zoom),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _pages.length; i++)
                    Container(
                      width: i == _index ? 18 : 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: i == _index ? _blue : const Color(0xFFD5D9DE),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _index == 0 ? null : _prev,
                      style: OutlinedButton.styleFrom(
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('이전'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: _next,
                      style: FilledButton.styleFrom(
                        backgroundColor: _blue,
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(last ? '시작하기' : '다음'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 한 장: 사진(있으면) + 제목 + 쉬운 설명
class _TutorialSlide extends StatelessWidget {
  const _TutorialSlide({required this.page, required this.onZoom});

  final _TutorialPage page;
  final void Function(String path) onZoom;

  @override
  Widget build(BuildContext context) {
    final image = page.image;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          if (image != null) ...[
            GestureDetector(
              onTap: () => onZoom(image),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: AspectRatio(
                  aspectRatio: 1400 / 796,
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFE3E6EA)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Image.asset(
                      image,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Center(
                        child: Icon(Icons.image_not_supported_outlined),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '사진을 누르면 크게 볼 수 있어요',
              style: TextStyle(fontSize: 12, color: Color(0xFF8A9098)),
            ),
            const SizedBox(height: 14),
          ] else ...[
            const SizedBox(height: 40),
            Icon(page.icon, size: 72, color: _blue),
            const SizedBox(height: 24),
          ],
          Text(
            page.title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          for (final line in page.lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                line,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, height: 1.45),
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}