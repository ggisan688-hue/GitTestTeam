import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../model/book.dart';
import '../../theme/app_theme.dart';
import '../../viewmodel/auth_viewmodel.dart';
import '../../viewmodel/bookshelf_viewmodel.dart';
import '../../viewmodel/reading_viewmodel.dart';
import '../../widgets/app_card.dart';
import '../../widgets/buttons.dart';
import '../auth/login_screen.dart';
import '../friends/friends_screen.dart';
import '../home/home_screen.dart';
import '../persona/persona_screen.dart';

/// 로그인 후 첫 화면. 책을 고르면 읽기 화면(HomeScreen)으로
class BookshelfScreen extends StatefulWidget {
  const BookshelfScreen({super.key});

  @override
  State<BookshelfScreen> createState() => _BookshelfScreenState();
}

class _BookshelfScreenState extends State<BookshelfScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<BookshelfViewModel>().load());
  }

  Future<void> _open(Book book) async {
    final reading = context.read<ReadingViewModel>();
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HomeScreen()));
    await reading.open(book);
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<BookshelfViewModel>();

    return Scaffold(
      appBar: AppBar(
        title: Text('${context.watch<AuthViewModel>().member?.name ?? ''}님의 책장'),
        actions: [
          IconButton(
            tooltip: '친구',
            icon: const Icon(Icons.people_alt_outlined, size: 22, color: AppColors.ink),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FriendsScreen())),
          ),
          IconButton(
            tooltip: 'AI 독서 친구',
            icon: const Icon(Icons.smart_toy_outlined, size: 22, color: AppColors.ink),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PersonaScreen())),
          ),
          IconButton(
            tooltip: '로그아웃',
            icon: const Icon(Icons.logout, size: 22, color: AppColors.muted),
            onPressed: () async {
              await context.read<AuthViewModel>().logout();
              if (!context.mounted) return;
              Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: vm.load,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.sm, AppSpace.lg, AppSpace.xxl),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    const Text('읽고 있는 책', style: AppText.heading),
                    const Spacer(),
                    if (context.watch<AuthViewModel>().member?.friendCode case final code?)
                      Text('내 코드 $code', style: AppText.captionAccent),
                  ]),
                  const SizedBox(height: 2),
                  Text('${vm.books.length}권 · 책을 누르면 이어서 읽어요', style: AppText.caption),
                  const SizedBox(height: AppSpace.lg),
                  if (vm.isLoading && vm.books.isEmpty)
                    const Padding(padding: EdgeInsets.all(AppSpace.xxl + AppSpace.sm), child: Center(child: CircularProgressIndicator()))
                  else if (vm.errorMessage != null && vm.books.isEmpty)
                    AppCard(child: Column(children: [
                      Text(vm.errorMessage!, style: AppText.error),
                      const SizedBox(height: AppSpace.md),
                      AppButton('다시 시도', onPressed: vm.load),
                    ]))
                  else
                    LayoutBuilder(
                      builder: (context, c) {
                        final cols = c.maxWidth > 700 ? 3 : c.maxWidth > 460 ? 2 : 1;
                        return GridView.count(
                          crossAxisCount: cols,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          mainAxisSpacing: AppSpace.md,
                          crossAxisSpacing: AppSpace.md,
                          childAspectRatio: cols == 1 ? 2.6 : 1.35,
                          children: [for (final b in vm.books) _BookCard(book: b, onTap: () => _open(b))],
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BookCard extends StatelessWidget {
  const _BookCard({required this.book, required this.onTap});

  final Book book;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 책등 느낌의 작은 표지
              Container(
                width: 44,
                height: 60,
                decoration: BoxDecoration(
                  color: AppColors.accentSoft,
                  borderRadius: BorderRadius.circular(AppSpace.sm - 2),
                  border: Border.all(color: AppColors.line),
                ),
                child: const Icon(Icons.menu_book_rounded, color: AppColors.accent, size: 22),
              ),
              const SizedBox(width: AppSpace.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(book.title, style: AppText.heading, maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(book.author ?? '', style: AppText.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                    const Spacer(),
                    Row(children: [
                      StatusBadge('${book.chapterCount}장', tone: StatusTone.neutral),
                      const Spacer(),
                      const Text('읽기 →', style: AppText.labelAccent),
                    ]),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
