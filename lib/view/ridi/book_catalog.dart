import 'dart:async';
import 'ridi_auth.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/app_config.dart';
import '../../model/book.dart';
import '../../repository/book_repository.dart';
import '../../viewmodel/book_viewmodel.dart';
import 'ridi_theme.dart';
import 'ridi_widgets.dart';
import 'advanced_book_reader.dart';
import 'ridi_store.dart';
import '../../viewmodel/favorite_viewmodel.dart';

class BookCatalogSection extends StatefulWidget {
  const BookCatalogSection({super.key});
  @override
  State<BookCatalogSection> createState() => _BookCatalogSectionState();
}

class _BookCatalogSectionState extends State<BookCatalogSection> {
  final ScrollController _scrollController = ScrollController();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
          (_) => context.read<BookViewModel>().loadBooks(),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 320) {
      context.read<BookViewModel>().loadNextBooks();
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<BookViewModel>();
    if (vm.state == BookLoadState.loading && vm.books.isEmpty) {
      return const SizedBox(
        height: 170,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (vm.state == BookLoadState.empty) {
      return const SizedBox(
        height: 150,
        child: RidiEmpty(icon: Icons.menu_book_outlined, text: '등록된 책이 없습니다.'),
      );
    }
    if ((vm.state == BookLoadState.networkError ||
        vm.state == BookLoadState.serverError) &&
        vm.books.isEmpty) {
      return SizedBox(
        height: 170,
        child: RidiEmpty(
          icon: Icons.cloud_off_rounded,
          text: vm.errorMessage ?? '책 목록을 불러오지 못했습니다.',
          action: RidiOutlineButton('다시 시도', onTap: vm.loadBooks),
        ),
      );
    }
    // 표지가 주인공인 세로 카드 (리디처럼): 표지 → 제목 → 저자
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 750
            ? 5
            : (constraints.maxWidth / 148).floor().clamp(2, 4).toInt();
        return NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification is ScrollUpdateNotification) _onScroll();
            return false;
          },
          child: Scrollbar(
            controller: _scrollController,
            thumbVisibility: true,
            interactive: true,
            thickness: 10,
            radius: const Radius.circular(10),
            child: GridView.builder(
              controller: _scrollController,
              primary: false,
              padding: const EdgeInsets.only(right: 12, bottom: 24),
              itemCount: vm.books.length +
                  (vm.isLoadingNextBooks || vm.booksHasNext ? 1 : 0),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: 24,
                crossAxisSpacing: 16,
                childAspectRatio: 0.72,
              ),
              itemBuilder: (_, index) {
                if (index >= vm.books.length) {
                  return vm.isLoadingNextBooks
                      ? const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                      : const SizedBox.shrink();
                }
                return BookCatalogCard(book: vm.books[index]);
              },
            ),
          ),
        );
      },
    );
  }
}

class BookCatalogCard extends StatelessWidget {
  const BookCatalogCard({
    super.key,
    required this.book,
    this.onAddToShelf,
  });

  final Book book;
  final VoidCallback? onAddToShelf;

  static const coverW = 175.0;
  static const coverH = 260.0;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BookDetailScreen(bookId: book.id),
      ),
    ),
    borderRadius: BorderRadius.circular(8),
    child: Center(
      child: SizedBox(
        width: coverW,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                BookCover(
                  url: book.coverImageUrl,
                  width: coverW,
                  height: coverH,
                ),
                if (onAddToShelf != null)
                  Positioned(
                    right: 4,
                    top: 4,
                    child: Material(
                      color: Colors.white.withValues(alpha: .9),
                      shape: const CircleBorder(),
                      child: IconButton(
                        tooltip: '책장에 추가',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(
                          Icons.playlist_add_outlined,
                          size: 18,
                        ),
                        onPressed: () {
                          if (!context.read<RidiStore>().loggedIn) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('로그인이 필요합니다.'),
                              ),
                            );
                            return;
                          }

                          onAddToShelf?.call();
                        },
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              book.title,
              style: RidiText.bodyBold.copyWith(fontSize: 15),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              book.author ?? '',
              style: RidiText.sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    ),
  );
}

class BookDetailScreen extends StatefulWidget {
  const BookDetailScreen({super.key, required this.bookId});
  final int bookId;
  @override
  State<BookDetailScreen> createState() => _BookDetailScreenState();
}

class _BookDetailScreenState extends State<BookDetailScreen> {
  late final BookRepository _repository;
  bool _favorite = false;
  bool _favoriteLoading = true;
  bool _favoriteSaving = false;

  @override
  void initState() {
    super.initState();
    _repository = BookRepository(
      ApiClient(tokenProvider: () => context.read<RidiStore>().accessToken),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BookViewModel>().openBook(widget.bookId);
      _loadFavorite();
    });
  }

  Future<void> _loadFavorite() async {
    if (!context.read<RidiStore>().loggedIn) {
      if (mounted) {
        setState(() {
          _favorite = false;
          _favoriteLoading = false;
        });
      }
      return;
    }

    try {
      final favorite = await _repository.favoriteStatus(widget.bookId);
      if (mounted) {
        setState(() {
          _favorite = favorite;
          _favoriteLoading = false;
        });
      }
    } on ApiException catch (error) {
      if (!mounted) return;

      setState(() => _favoriteLoading = false);

      if (!error.isUnauthorized) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
      }
    }
  }

  Future<void> _toggleFavorite() async {
    // 비로그인 상태에서는 안내 문구만 표시
    if (!context.read<RidiStore>().loggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('로그인이 필요합니다.'),
        ),
      );
      return;
    }

    if (_favoriteSaving || _favoriteLoading) return;

    final before = _favorite;
    setState(() {
      _favorite = !before;
      _favoriteSaving = true;
    });

    try {
      await context.read<FavoriteViewModel>().setFavorite(
        widget.bookId,
        !before,
      );
    } on ApiException catch (error) {
      if (mounted) {
        setState(() => _favorite = before);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
      }
    } finally {
      if (mounted) setState(() => _favoriteSaving = false);
    }
  }

  void _openReader() {
    if (!context.read<RidiStore>().loggedIn) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: ridiAppBar(context, '읽기 시작'),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '로그인이 필요한 서비스입니다.',
                    style: TextStyle(
                      fontFamily: RidiText.f,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: RidiColors.ink,
                    ),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: () => showLoginDialog(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: RidiColors.ink,
                      side: const BorderSide(color: RidiColors.grayLight),
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 12,
                      ),
                    ),
                    child: const Text('로그인'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdvancedBookReaderScreen(bookId: widget.bookId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<BookViewModel>();
    final book = vm.selectedBook;
    return Scaffold(
      appBar: ridiAppBar(
        context,
        '책 상세',
        actions: [
          IconButton(
            tooltip: _favorite ? '즐겨찾기 해제' : '즐겨찾기',
            onPressed: _favoriteLoading || _favoriteSaving
                ? null
                : _toggleFavorite,
            icon: _favoriteSaving
                ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
            // Bookmarks belong to the reader's per-position note feature.
            // A heart makes this book-level, personal favorite unambiguous.
                : Icon(
              _favorite ? Icons.favorite : Icons.favorite_border,
              color: _favorite ? RidiColors.red : RidiColors.ink,
            ),
          ),
        ],
      ),
      body: vm.state == BookLoadState.loading
          ? const Center(child: CircularProgressIndicator())
          : book == null
          ? RidiEmpty(
        icon: Icons.error_outline,
        text: vm.errorMessage ?? '책 정보를 불러오지 못했습니다.',
        action: RidiOutlineButton(
          '다시 시도',
          onTap: () => vm.loadBook(widget.bookId),
        ),
      )
          : SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: InkWell(
                onTap: _openReader,
                borderRadius: BorderRadius.circular(5),
                child: BookCover(
                  url: book.coverImageUrl,
                  width: 160,
                  height: 240,
                ),
              ),
            ),
            const SizedBox(height: 28),
            if (book.category?.isNotEmpty == true)
              _Category(label: book.category!),
            const SizedBox(height: 10),
            Text(
              book.title,
              style: RidiText.title.copyWith(fontSize: 26),
            ),
            const SizedBox(height: 6),
            Text(
              book.author ?? '',
              style: RidiText.body.copyWith(color: RidiColors.gray),
            ),
            const SizedBox(height: 28),
            Text(
              book.description?.isNotEmpty == true
                  ? book.description!
                  : '책 소개가 아직 등록되지 않았습니다.',
              style: RidiText.body,
            ),
            const SizedBox(height: 28),
            RidiButton(
              '읽기 시작',
              icon: Icons.menu_book_rounded,
              expand: true,
              onTap: _openReader,
            ),
          ],
        ),
      ),
    );
  }
}

class BookReaderScreen extends StatefulWidget {
  const BookReaderScreen({super.key, required this.bookId});
  final int bookId;

  @override
  State<BookReaderScreen> createState() => _BookReaderScreenState();
}

class _BookReaderScreenState extends State<BookReaderScreen> {
  late final PageController _pageController;
  int _position = 0;
  bool _restored = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final vm = context.read<BookViewModel>();
      await vm.loadReader(widget.bookId);
      final paragraphs = vm.content?.paragraphs;
      if (!mounted || paragraphs == null || paragraphs.isEmpty || _restored)
        return;
      _position = (vm.readingProgress?.lastReadPosition ?? 0)
          .clamp(0, paragraphs.length - 1)
          .toInt();
      _restored = true;
      _pageController.jumpToPage(_position);
      setState(() {});
    });
  }

  Future<bool> _onBack() async {
    final total = context.read<BookViewModel>().content?.paragraphs.length ?? 0;
    await context.read<BookViewModel>().saveReaderProgress(
      widget.bookId,
      _position,
      total,
    );
    return true;
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<BookViewModel>();
    final content = vm.content;
    return WillPopScope(
      onWillPop: _onBack,
      child: Scaffold(
        appBar: ridiAppBar(context, content?.title ?? '책 읽기'),
        body: vm.isReaderLoading
            ? const Center(child: CircularProgressIndicator())
            : content == null
            ? RidiEmpty(
          icon: Icons.article_outlined,
          text: vm.readerErrorMessage ?? '아직 읽을 수 있는 본문이 등록되지 않았습니다.',
          action: RidiOutlineButton(
            '다시 시도',
            onTap: () => vm.loadReader(widget.bookId),
          ),
        )
            : Column(
          children: [
            LinearProgressIndicator(
              value: (_position + 1) / content.paragraphs.length,
              minHeight: 3,
              color: RidiColors.blue,
              backgroundColor: RidiColors.grayLight,
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: content.paragraphs.length,
                onPageChanged: (index) {
                  setState(() => _position = index);
                  context.read<BookViewModel>().saveReaderProgress(
                    widget.bookId,
                    index,
                    content.paragraphs.length,
                  );
                },
                itemBuilder: (_, index) => Padding(
                  padding: const EdgeInsets.fromLTRB(30, 42, 30, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${index + 1} / ${content.paragraphs.length}',
                        style: RidiText.sub,
                      ),
                      const SizedBox(height: 28),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Text(
                            content.paragraphs[index].text,
                            style: RidiText.body.copyWith(
                              fontFamily: 'NotoSerifKR',
                              fontSize: 18,
                              height: 2.0,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RecentReadingSection extends StatefulWidget {
  const RecentReadingSection({super.key});
  @override
  State<RecentReadingSection> createState() => _RecentReadingSectionState();
}

class _RecentReadingSectionState extends State<RecentReadingSection> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
          (_) => context.read<BookViewModel>().loadRecentBooks(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final recent = context.watch<BookViewModel>().recentBooks;
    if (recent.isEmpty) {
      return const SizedBox(
        height: 116,
        child: RidiEmpty(icon: Icons.history_rounded, text: '최근 읽은 도서가 없습니다.'),
      );
    }
    return SizedBox(
      height: 170,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: recent.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (_, index) => _RecentCard(recent: recent[index]),
      ),
    );
  }
}

class _RecentCard extends StatelessWidget {
  const _RecentCard({required this.recent});
  final RecentBook recent;

  @override
  Widget build(BuildContext context) {
    final book = recent.book;
    return InkWell(
      // Recent-reading cards resume directly in the same server-backed reader
      // used by the detail screen; the reader resolves lastReadPosition after
      // pagination rather than guessing from the displayed percentage.
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AdvancedBookReaderScreen(bookId: book.id),
        ),
      ),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 260,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: RidiColors.grayLight),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            BookCover(url: book.coverImageUrl, width: 64, height: 98),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    book.title,
                    style: RidiText.bodyBold,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    book.author ?? '',
                    style: RidiText.sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: recent.progressPercent / 100,
                      minHeight: 4,
                      color: RidiColors.blue,
                      backgroundColor: RidiColors.grayLight,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '진행률 ${recent.progressPercent}%',
                    style: RidiText.sub.copyWith(fontSize: 11),
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

class BookCover extends StatelessWidget {
  const BookCover({
    super.key,
    required this.url,
    required this.width,
    required this.height,
  });
  final String? url;
  final double width;
  final double height;
  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: RidiColors.panel,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: RidiColors.grayLight),
      ),
      child: Icon(
        Icons.menu_book_rounded,
        color: RidiColors.gray,
        size: width * .38,
      ),
    );
    if (url == null || url!.trim().isEmpty) return fallback;
    final source = url!.trim();
    final resolvedUrl = source.startsWith('http')
        ? source
        : '${AppConfig.baseUrl}${source.startsWith('/') ? '' : '/'}$source';
    return ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: Image.network(
        resolvedUrl,
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}

class _Category extends StatelessWidget {
  const _Category({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: RidiColors.panel,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(label, style: RidiText.sub.copyWith(fontSize: 11)),
  );
}
