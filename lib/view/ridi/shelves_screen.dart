import 'package:flutter/material.dart';

import 'dart:async';

import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../model/book.dart';
import '../../model/shelf.dart';
import '../../repository/book_repository.dart';
import '../../repository/shelf_repository.dart';
import '../../viewmodel/favorite_viewmodel.dart';
import 'advanced_book_reader.dart';
import 'book_catalog.dart';
import 'reading_rooms_screen.dart';
import 'ridi_store.dart';

class ShelvesScreen extends StatefulWidget {
  const ShelvesScreen({super.key, this.initialSection = 0});
  final int initialSection;

  @override
  State<ShelvesScreen> createState() => _ShelvesScreenState();
}

class _ShelvesScreenState extends State<ShelvesScreen>
    with SingleTickerProviderStateMixin {
  late final ShelfRepository _repository;
  late final BookRepository _books;
  late Future<List<Shelf>> _shelves;
  List<Shelf> _shelfCache = const [];
  int _section = 0;
  late final TabController _tabs;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _repository = ShelfRepository(
      ApiClient(tokenProvider: () => context.read<RidiStore>().accessToken),
    );
    _books = BookRepository(
      ApiClient(tokenProvider: () => context.read<RidiStore>().accessToken),
    );
    _shelves = _loadShelves();
    context.read<FavoriteViewModel>().load(clearFirst: true);
    _section = widget.initialSection;
    _tabs = TabController(length: 2, vsync: this, initialIndex: _section)
      ..addListener(() {
        if (!_tabs.indexIsChanging && mounted && _section != _tabs.index) {
          setState(() => _section = _tabs.index);
        }
      });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _tabs.dispose();
    super.dispose();
  }

  Future<List<Shelf>> _loadShelves() async {
    final shelves = await _repository.list();
    _shelfCache = shelves;
    return shelves;
  }

  void _reloadShelves() => setState(() => _shelves = _loadShelves());

  void _updateShelfCard(Shelf shelf) {
    if (!mounted) return;
    final next = _shelfCache
        .map((item) => item.id == shelf.id ? shelf : item)
        .toList();
    setState(() {
      _shelfCache = next;
      _shelves = Future.value(next);
    });
  }

  void _syncShelvesInBackground() {
    unawaited(
      _loadShelves()
          .then((shelves) {
        if (mounted) setState(() => _shelves = Future.value(shelves));
      })
          .catchError((_) {}),
    );
  }

  void _removeShelfFromList(int shelfId) {
    final next = _shelfCache.where((shelf) => shelf.id != shelfId).toList();
    setState(() {
      _shelfCache = next;
      _shelves = Future.value(next);
    });
    _syncShelvesInBackground();
  }

  Future<void> _refresh() async {
    final shelves = _loadShelves();
    setState(() {
      _shelves = shelves;
    });
    final favorites = context.read<FavoriteViewModel>().load();
    try {
      await Future.wait([shelves, favorites]);
    } catch (_) {
      /* each section renders its own error */
    }
  }

  Future<void> _create() async {
    final created = await Navigator.of(context).push<Shelf>(
      MaterialPageRoute(
        builder: (_) =>
            ShelfCreateScreen(repository: _repository, books: _books),
      ),
    );
    if (created == null || !mounted) return;
    // The create response is authoritative enough to render the new card at
    // once; the background sync only reconciles fields changed on the server.
    final next = <Shelf>[
      created,
      ..._shelfCache.where((shelf) => shelf.id != created.id),
    ];
    setState(() {
      _shelfCache = next;
      _shelves = Future.value(next);
    });
    _syncShelvesInBackground();
  }

  Future<void> _deleteAllShelves(int shelfCount) async {
    final deleted =
        await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) {
            var deleting = false;
            String? error;
            return StatefulBuilder(
              builder: (context, setDialogState) => AlertDialog(
                title: const Text('책장 전체 삭제'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('내 책장 $shelfCount개를 모두 삭제할까요?'),
                    const SizedBox(height: 8),
                    const Text('도서, 즐겨찾기, 읽기 기록은 삭제되지 않습니다.'),
                    if (error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: deleting
                        ? null
                        : () => Navigator.of(dialogContext).pop(false),
                    child: const Text('취소'),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.error,
                    ),
                    onPressed: deleting
                        ? null
                        : () async {
                      setDialogState(() {
                        deleting = true;
                        error = null;
                      });
                      try {
                        await _repository.deleteAll();
                        if (dialogContext.mounted)
                          Navigator.of(dialogContext).pop(true);
                      } on ApiException catch (e) {
                        if (dialogContext.mounted) {
                          setDialogState(() {
                            deleting = false;
                            error = e.message;
                          });
                        }
                      } catch (_) {
                        if (dialogContext.mounted) {
                          setDialogState(() {
                            deleting = false;
                            error = '책장을 삭제하지 못했습니다. 다시 시도해주세요.';
                          });
                        }
                      }
                    },
                    child: deleting
                        ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                        : const Text('모두 삭제'),
                  ),
                ],
              ),
            );
          },
        ) ??
            false;
    if (deleted && mounted) _reloadShelves();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('내 서재'),
      bottom: TabBar(
        controller: _tabs,
        tabs: const [
          Tab(text: '내 책장'),
          Tab(text: '교환독서'),
        ],
      ),

    ),
    body: _section == 1
        ? const ReadingRoomsScreen(embedded: true)
        : RefreshIndicator(
      onRefresh: _refresh,
      child: Scrollbar(
        controller: _scrollController,
        thumbVisibility: false,
        scrollbarOrientation: ScrollbarOrientation.right,
        notificationPredicate: (notification) => notification.depth == 0,
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '최근 읽은 도서',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    const RecentReadingSection(),
                  ],
                ),
              ),
            ),
            FutureBuilder<List<Shelf>>(
              future: _shelves,
              builder: (context, snapshot) {
                return SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    child: Row(
                      children: [
                        Text(
                          '내 책장',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: _create,
                          icon: const Icon(Icons.add),
                          label: const Text('새 책장'),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            FutureBuilder<List<Shelf>>(
              future: _shelves,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done)
                  return const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  );
                if (snapshot.hasError)
                  return SliverToBoxAdapter(
                    child: SizedBox(
                      height: 160,
                      child: _ErrorState(
                        error: snapshot.error,
                        onRetry: _reloadShelves,
                      ),
                    ),
                  );
                final shelves = snapshot.data ?? const [];

                // 책장을 세로 카드로 나란히 (필기 수정2-36)
                return SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                  sliver: SliverGrid.builder(
                    gridDelegate:
                    const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 190,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      childAspectRatio: .68,
                    ),
                    itemCount: shelves.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return const _FavoriteShelfTile();
                      }
                      final shelf = shelves[index - 1];
                      return _ShelfTile(
                        shelf: shelf,
                        onTap: () async {
                          final deletedShelfId = await Navigator.of(context)
                              .push<int>(
                            MaterialPageRoute(
                              builder: (_) => ShelfDetailScreen(
                                repository: _repository,
                                shelfId: shelf.id,
                                onChanged: _updateShelfCard,
                              ),
                            ),
                          );
                          if (!mounted) return;
                          if (deletedShelfId != null) {
                            _removeShelfFromList(deletedShelfId);
                          } else {
                            _reloadShelves();
                          }
                        },
                      );
                    },
                  ),
                );
              },
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 8)),
          ],
        ),
      ),
    ),
  );
}


class FavoriteBooksScreen extends StatefulWidget {
  const FavoriteBooksScreen({super.key});

  @override
  State<FavoriteBooksScreen> createState() => _FavoriteBooksScreenState();
}

class _FavoriteBooksScreenState extends State<FavoriteBooksScreen> {
  late final BookRepository _repository;
  late Future<List<Book>> _favorites;

  @override
  void initState() {
    super.initState();
    _repository = BookRepository(
      ApiClient(tokenProvider: () => context.read<RidiStore>().accessToken),
    );
    _favorites = _repository.favoriteBooks();
  }

  void _reload() => setState(() => _favorites = _repository.favoriteBooks());

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('즐겨찾기 도서')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => _FavoriteBookPicker(
            repository: _repository,
            existingBookIds: context.read<FavoriteViewModel>()
                .favorites.map((book) => book.id).toSet(),
          )),
        );
        if (mounted) _reload();
      },
      icon: const Icon(Icons.add),
      label: const Text('도서 추가'),
    ),
    body: FutureBuilder<List<Book>>(
      future: _favorites,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done)
          return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError)
          return _ErrorState(error: snapshot.error, onRetry: _reload);
        final books = snapshot.data ?? const [];
        return RefreshIndicator(
          onRefresh: () async {
            final future = _repository.favoriteBooks();
            setState(() => _favorites = future);
            await future;
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 96),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('즐겨찾기',
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text('${books.length}권'),
                const Divider(height: 36),
                if (books.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(child: Text('즐겨찾기한 도서가 없습니다.')),
                  )
                else
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: _coverGrid,
                    itemCount: books.length,
                    itemBuilder: (context, index) {
                      final book = books[index];
                      return _CoverTile(
                        book: book,
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => AdvancedBookReaderScreen(bookId: book.id),
                            ),
                          );
                          if (mounted) _reload();
                        },
                        overlay: Material(
                          color: Colors.white.withValues(alpha: .92),
                          shape: const CircleBorder(),
                          child: IconButton(
                            tooltip: '즐겨찾기에서 제거',
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.remove_circle_outline, size: 20),
                            onPressed: () async {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (dialogContext) => AlertDialog(
                                  title: const Text('삭제하시겠습니까?'),
                                  content: Text('「${book.title}」을 즐겨찾기에서 삭제합니다.'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.of(dialogContext).pop(false),
                                      child: const Text('취소'),
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.of(dialogContext).pop(true),
                                      child: const Text('확인'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirmed != true || !mounted) return;
                              try {
                                await context.read<FavoriteViewModel>()
                                    .setFavorite(book.id, false);
                                if (mounted) _reload();
                              } on ApiException catch (error) {
                                if (mounted) _showError(context, error);
                              }
                            },
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class ShelfDetailScreen extends StatefulWidget {
  const ShelfDetailScreen({
    super.key,
    required this.repository,
    required this.shelfId,
    this.onChanged,
  });

  final ShelfRepository repository;
  final int shelfId;
  final ValueChanged<Shelf>? onChanged;

  @override
  State<ShelfDetailScreen> createState() => _ShelfDetailScreenState();
}

class _ShelfDetailScreenState extends State<ShelfDetailScreen> {
  late Future<ShelfDetail> _detail;
  ShelfDetail? _cachedDetail;
  final Set<int> _removingBooks = <int>{};

  @override
  void initState() {
    super.initState();
    _detail = _loadDetail();
  }

  Future<ShelfDetail> _loadDetail() async {
    final detail = await widget.repository.detail(widget.shelfId);
    if (mounted) _cachedDetail = detail;
    return detail;
  }

  void _reload() => setState(() => _detail = _loadDetail());

  void _updateBooks(List<Book> books) {
    final previous = _cachedDetail;
    if (!mounted || previous == null) return;
    final old = previous.shelf;
    final shelf = Shelf(
      id: old.id,
      name: old.name,
      description: old.description,
      isPublic: old.isPublic,
      bookCount: books.length,
      coverBookId: books.isEmpty ? null : books.first.id,
      coverImageUrl: books.isEmpty ? null : books.first.coverImageUrl,
      previewCoverImageUrls: books
          .map((book) => book.coverImageUrl)
          .whereType<String>()
          .where((url) => url.isNotEmpty)
          .take(3)
          .toList(),
      createdAt: old.createdAt,
      updatedAt: old.updatedAt,
    );
    final detail = ShelfDetail(shelf: shelf, books: books);
    setState(() {
      _cachedDetail = detail;
      _detail = Future.value(detail);
    });
    widget.onChanged?.call(shelf);
  }

  Future<void> _removeBook(Book book) async {
    if (_removingBooks.contains(book.id)) return;
    final lastBook = _cachedDetail?.books.length == 1;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('삭제하시겠습니까?'),
        content: Text(lastBook
            ? '마지막 도서를 삭제하면 책장도 함께 삭제됩니다.'
            : '이 책장에서 도서를 삭제합니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _removingBooks.contains(book.id)) return;
    setState(() => _removingBooks.add(book.id));
    try {
      final shelfDeleted = await widget.repository.removeBook(widget.shelfId, book.id);
      if (!mounted) return;
      if (shelfDeleted) {
        Navigator.of(context).pop(widget.shelfId);
        return;
      }
      _updateBooks((_cachedDetail?.books ?? const <Book>[])
          .where((item) => item.id != book.id).toList());
    } on ApiException catch (error) {
      if (mounted) _showError(context, error);
    } finally {
      if (mounted) setState(() => _removingBooks.remove(book.id));
    }
  }

  Future<void> _edit(Shelf shelf) async {
    final values = await showShelfEditor(context, shelf: shelf);
    if (values == null || !mounted) return;
    try {
      final saved = await widget.repository.update(
        widget.shelfId,
        name: values.name,
        description: values.description,
        isPublic: values.isPublic,
      );
      if (!mounted) return;
      final previous = _cachedDetail;
      if (previous != null) {
        final detail = ShelfDetail(shelf: saved, books: previous.books);
        setState(() {
          _cachedDetail = detail;
          _detail = Future.value(detail);
        });
        widget.onChanged?.call(saved);
      } else {
        _reload();
      }
    } on ApiException catch (error) {
      if (mounted) _showError(context, error);
    }
  }

  Future<void> _delete() async {
    final deleted =
        await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) {
            var deleting = false;
            String? error;
            return StatefulBuilder(
              builder: (context, setDialogState) => AlertDialog(
                title: const Text('책장을 삭제할까요?'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('책장만 삭제되며, 원본 도서와 읽기 기록은 유지됩니다.'),
                    if (error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: deleting
                        ? null
                        : () => Navigator.of(dialogContext).pop(false),
                    child: const Text('취소'),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.error,
                    ),
                    onPressed: deleting
                        ? null
                        : () async {
                      setDialogState(() {
                        deleting = true;
                        error = null;
                      });
                      try {
                        await widget.repository.delete(widget.shelfId);
                        if (dialogContext.mounted)
                          Navigator.of(dialogContext).pop(true);
                      } on ApiException catch (e) {
                        if (dialogContext.mounted)
                          setDialogState(() {
                            deleting = false;
                            error = e.message;
                          });
                      } catch (_) {
                        if (dialogContext.mounted)
                          setDialogState(() {
                            deleting = false;
                            error = '책장을 삭제하지 못했습니다. 다시 시도해주세요.';
                          });
                      }
                    },
                    child: deleting
                        ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                        : const Text('삭제'),
                  ),
                ],
              ),
            );
          },
        ) ??
            false;
    if (deleted && mounted) Navigator.of(context).pop(widget.shelfId);
  }

  Future<void> _addBook([ShelfDetail? detail]) async {
    if (_cachedDetail == null) return;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _BookPicker(
          repository: widget.repository,
          shelfId: widget.shelfId,
          existingBookIds:
          (_cachedDetail?.books ?? const <Book>[]).map((book) => book.id).toSet(),
          onAdded: (book) {
            final books = _cachedDetail?.books ?? const <Book>[];
            if (!books.any((item) => item.id == book.id)) {
              _updateBooks([...books, book]);
            }
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('책장 상세'),
      actions: [
        FutureBuilder<ShelfDetail>(
          future: _detail,
          builder: (context, snapshot) => snapshot.hasData
              ? PopupMenuButton<String>(
            onSelected: (value) =>
            value == 'edit' ? _edit(snapshot.data!.shelf) : _delete(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('책장 수정')),
              PopupMenuItem(value: 'delete', child: Text('책장 삭제')),
            ],
          )
              : const SizedBox.shrink(),
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _addBook,
      icon: const Icon(Icons.add),
      label: const Text('도서 추가'),
    ),
    body: FutureBuilder<ShelfDetail>(
      future: _detail,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done)
          return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError)
          return _ErrorState(error: snapshot.error, onRetry: _reload);
        final detail = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 96),
          children: [
            Text(
              detail.shelf.name,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              detail.shelf.description?.isNotEmpty == true
                  ? detail.shelf.description!
                  : '설명 없음',
            ),
            const SizedBox(height: 6),
            Text(
              '${detail.shelf.bookCount}권',
            ),
            const Divider(height: 36),
            if (detail.books.isEmpty)
              _EmptyBooks(onAdd: () => _addBook(detail))
            else
            // 책장 도서 표지 격자
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: _coverGrid,
                itemCount: detail.books.length,
                itemBuilder: (context, index) {
                  final book = detail.books[index];
                  return _CoverTile(
                    book: book,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AdvancedBookReaderScreen(bookId: book.id),
                      ),
                    ),

                    overlay: Material(
                      color: Colors.white.withValues(alpha: .92),
                      shape: const CircleBorder(),
                      child: IconButton(
                        tooltip: '책장에서 제거',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.remove_circle_outline, size: 20),
                        onPressed: _removingBooks.contains(book.id)
                            ? null
                            : () => _removeBook(book),
                      ),
                    ),
                  );
                },
              ),
          ],
        );
      },
    ),
  );
}

/// A full screen owns its input controllers for its complete lifetime.  This
/// avoids disposing a controller while a dialog builder is still reading it.
class ShelfCreateScreen extends StatefulWidget {
  const ShelfCreateScreen({
    super.key,
    required this.repository,
    required this.books,
  });
  final ShelfRepository repository;
  final BookRepository books;
  @override
  State<ShelfCreateScreen> createState() => _ShelfCreateScreenState();
}

class _ShelfCreateScreenState extends State<ShelfCreateScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final Future<List<Book>> _allBooks;
  final Set<int> _selectedIds = <int>{};
  String _query = '';
  String? _nameError;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _descriptionController = TextEditingController();
    _allBooks = widget.books.books();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    // Copy controller values before any await/Navigator operation.
    final name = _nameController.text.trim();
    final description = _descriptionController.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = '책장 이름을 입력해 주세요.');
      return;
    }
    setState(() {
      _nameError = null;
      _saving = true;
    });
    try {
      final shelf = await widget.repository.create(
        name: name,
        description: description,
        isPublic: false,
        bookIds: _selectedIds.toList(),
      );
      if (mounted) Navigator.of(context).pop(shelf);
    } on ApiException catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('새 책장 만들기')),
    bottomNavigationBar: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
              : const Icon(Icons.save_outlined),
          label: Text(_saving ? '저장 중…' : '책장 만들기'),
        ),
      ),
    ),
    body: ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            children: [
              TextField(
                controller: _nameController,
                maxLength: 80,
                autofocus: true,
                onChanged: (_) {
                  if (_nameError != null) setState(() => _nameError = null);
                },
                decoration: InputDecoration(
                  labelText: '책장 이름',
                  errorText: _nameError,
                ),
              ),
              TextField(
                controller: _descriptionController,
                maxLength: 300,
                minLines: 1,
                maxLines: 2,
                decoration: const InputDecoration(labelText: '설명 (선택)'),
              ),
              TextField(
                onChanged: (value) =>
                    setState(() => _query = value.trim().toLowerCase()),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: '제목 또는 저자로 도서 검색',
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Text('도서 선택', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              Text('선택한 도서 ${_selectedIds.length}권'),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: FutureBuilder<List<Book>>(
            future: _allBooks,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done)
                return const Center(child: CircularProgressIndicator());
              if (snapshot.hasError)
                return _ErrorState(
                  error: snapshot.error,
                  onRetry: () => setState(() {}),
                );
              final books = (snapshot.data ?? const <Book>[])
                  .where(
                    (book) =>
                _query.isEmpty ||
                    book.title.toLowerCase().contains(_query) ||
                    (book.author ?? '').toLowerCase().contains(_query),
              )
                  .toList();
              if (books.isEmpty)
                return const Center(child: Text('조건에 맞는 도서가 없습니다.'));
              // 표지 격자에서 눌러서 고르기 (필기 수정2-34). 고른 책은 표지에 파란 체크
              return GridView.builder(
                shrinkWrap: true,
                primary: false,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.only(top: 8, bottom: 16),
                gridDelegate: _coverGrid,
                itemCount: books.length,
                itemBuilder: (context, index) {
                  final book = books[index];
                  final selected = _selectedIds.contains(book.id);
                  return _CoverTile(
                    book: book,
                    onTap: _saving
                        ? null
                        : () => setState(() {
                      if (selected) {
                        _selectedIds.remove(book.id);
                      } else {
                        _selectedIds.add(book.id);
                      }
                    }),
                    overlay: Icon(
                      selected
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 28,
                      color: selected ? const Color(0xFF1E88E5) : Colors.white,
                      shadows: const [
                        Shadow(color: Colors.black38, blurRadius: 4),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    ),
  );
}

class _BookPicker extends StatefulWidget {
  const _BookPicker({
    required this.repository,
    required this.shelfId,
    required this.existingBookIds,
    required this.onAdded,
  });
  final ShelfRepository repository;
  final int shelfId;
  final Set<int> existingBookIds;
  final ValueChanged<Book> onAdded;
  @override
  State<_BookPicker> createState() => _BookPickerState();
}

class _BookPickerState extends State<_BookPicker> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _matchesSearch(Book book) {
    final query = _query.trim().toLowerCase();
    return query.isEmpty || book.title.toLowerCase().contains(query) ||
        (book.author ?? '').toLowerCase().contains(query);
  }

  late Future<List<Book>> _future;
  final Set<int> _pending = <int>{};
  final Set<int> _added = <int>{};
  Object? _error;

  @override
  void initState() {
    super.initState();
    _future = widget.repository.candidates(widget.shelfId);
  }

  void _retry() => setState(() {
    _error = null;
    _future = widget.repository.candidates(widget.shelfId);
  });

  Future<void> _add(Book book) async {
    if (_pending.contains(book.id) || _added.contains(book.id)) return;
    setState(() {
      _pending.add(book.id);
      _error = null;
    });
    try {
      await widget.repository.addBook(widget.shelfId, book.id);
      // The picker may already be closed while the save finishes.
      // Its parent still needs the successful result.
      widget.onAdded(book);
      if (mounted) setState(() => _added.add(book.id));
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _pending.remove(book.id));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('도서 추가')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            controller: _searchController,
            onChanged: (value) => setState(() => _query = value),
            decoration: InputDecoration(
              hintText: '책 제목 또는 저자 검색',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.isEmpty ? null : IconButton(
                tooltip: '검색어 지우기',
                icon: const Icon(Icons.close),
                onPressed: () {
                  _searchController.clear();
                  setState(() => _query = '');
                },
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        Expanded(child: FutureBuilder<List<Book>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done)
              return const Center(child: CircularProgressIndicator());
            if (snapshot.hasError)
              return _ErrorState(error: snapshot.error, onRetry: _retry);
            final excluded = {...widget.existingBookIds, ..._added};
            final books = (snapshot.data ?? const <Book>[])
                .where((book) => !excluded.contains(book.id) && _matchesSearch(book))
                .toList();
            if (books.isEmpty)
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.library_add_check_outlined, size: 42),
                    const SizedBox(height: 12),
                    Text(_query.trim().isNotEmpty
                        ? '검색 결과가 없습니다.'
                        : '추가할 수 있는 도서가 없습니다.'),
                    TextButton(onPressed: _retry, child: const Text('다시 조회')),
                  ],
                ),
              );
            return Column(
              children: [
                if (_error != null)
                  MaterialBanner(
                    content: const Text('도서 추가에 실패했습니다.'),
                    actions: [
                      TextButton(onPressed: _retry, child: const Text('재시도')),
                    ],
                  ),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate: _coverGrid,
                    itemCount: books.length,
                    itemBuilder: (context, index) {
                      final book = books[index];
                      final pending = _pending.contains(book.id);
                      return _CoverTile(
                        book: book,
                        onTap: pending ? null : () => _add(book),
                        overlay: pending
                            ? const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                            : const Material(
                          color: Colors.white70,
                          shape: CircleBorder(),
                          child: Padding(
                            padding: EdgeInsets.all(5),
                            child: Icon(Icons.add),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        )),
      ],
    ),
  );
}

class _EmptyShelves extends StatelessWidget {
  const _EmptyShelves({required this.onCreate});
  final VoidCallback onCreate;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.collections_bookmark_outlined, size: 44),
        const SizedBox(height: 12),
        const Text('아직 만든 책장이 없습니다.'),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: onCreate,
          icon: const Icon(Icons.add),
          label: const Text('새 책장 만들기'),
        ),
      ],
    ),
  );
}

class _EmptyBooks extends StatelessWidget {
  const _EmptyBooks({required this.onAdd});
  final VoidCallback onAdd;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          const Icon(Icons.menu_book_outlined, size: 44),
          const SizedBox(height: 12),
          const Text('이 책장에 담긴 도서가 없습니다.'),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('도서 추가'),
          ),
        ],
      ),
    ),
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});
  final Object? error;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.cloud_off_outlined, size: 40),
        const SizedBox(height: 12),
        Text(
          error is ApiException
              ? (error as ApiException).message
              : '불러오지 못했습니다.',
        ),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: onRetry, child: const Text('다시 시도')),
      ],
    ),
  );
}

class _ShelfValues {
  const _ShelfValues(this.name, this.description, this.isPublic);
  final String name;
  final String? description;
  final bool isPublic;
}

Future<_ShelfValues?> showShelfEditor(BuildContext context, {Shelf? shelf}) =>
    showDialog<_ShelfValues>(
      context: context,
      builder: (_) => _ShelfEditorDialog(shelf: shelf),
    );

/// 책장 이름·설명 팝업. 입력 칸(controller)은 팝업이 완전히 닫힐 때 같이 정리한다.
/// (전에는 닫히는 순간 바로 정리해서, 뒤로가기로 닫으면 닫히는 애니메이션 중에 빨간 오류 화면이 났다)
class _ShelfEditorDialog extends StatefulWidget {
  const _ShelfEditorDialog({this.shelf});
  final Shelf? shelf;
  @override
  State<_ShelfEditorDialog> createState() => _ShelfEditorDialogState();
}

class _ShelfEditorDialogState extends State<_ShelfEditorDialog> {
  late final _name = TextEditingController(text: widget.shelf?.name ?? '');
  late final _description = TextEditingController(
    text: widget.shelf?.description ?? '',
  );

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.shelf == null ? '새 책장 만들기' : '책장 수정'),
    // The dialog form must be allowed to scroll when the keyboard reduces
    // the available height; otherwise its Column overflows vertically.
    scrollable: true,
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            maxLength: 80,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: '책장 이름'),
          ),
          TextField(
            controller: _description,
            maxLength: 300,
            decoration: const InputDecoration(labelText: '설명 (선택)'),
          ),
          // 공개 책장 켜기/끄기는 뺌 (필기 수정2-41) — 지금 값 그대로 저장
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('취소'),
      ),
      FilledButton(
        onPressed: _name.text.trim().isEmpty
            ? null
            : () => Navigator.pop(
          context,
          _ShelfValues(
            _name.text.trim(),
            _description.text.trim(),
            widget.shelf?.isPublic ?? false,
          ),
        ),
        child: const Text('저장'),
      ),
    ],
  );
}

void _showError(BuildContext context, ApiException error) {
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(error.message)));
}

/// 내 책장 한 칸 — 세로 카드 (위: 책장 그림, 아래: 이름 · 권수 · 공개 여부)
class _ShelfTile extends StatelessWidget {
  const _ShelfTile({required this.shelf, required this.onTap, this.subtitle});
  final Shelf shelf;
  final VoidCallback onTap;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F3F8),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE3E6EE)),
            ),
            child: shelf.coverImageUrl == null || shelf.coverImageUrl!.isEmpty
                ? const Icon(
              Icons.collections_bookmark_outlined,
              size: 44,
              color: Color(0xFF8A94A8),
            )
                : LayoutBuilder(
              builder: (context, constraints) {
                final previews = shelf.previewCoverImageUrls
                    .where((url) => url != shelf.coverImageUrl)
                    .take(2)
                    .toList();
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (
                    var index = previews.length - 1;
                    index >= 0;
                    index--
                    )
                      Positioned(
                        left: 10.0 + index * 13,
                        top: 12.0 + index * 7,
                        child: Opacity(
                          opacity: .55,
                          child: BookCover(
                            url: previews[index],
                            width: constraints.maxWidth * .68,
                            height: constraints.maxHeight * .78,
                          ),
                        ),
                      ),
                    Positioned.fill(
                      child: Padding(
                        padding: EdgeInsets.only(
                          left: previews.isEmpty ? 0 : 26,
                          top: previews.isEmpty ? 0 : 8,
                        ),
                        child: BookCover(
                          url: shelf.coverImageUrl,
                          width: constraints.maxWidth,
                          height: constraints.maxHeight,
                          fit: shelf.bookCount == 1
                              ? BoxFit.contain
                              : BoxFit.cover,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          shelf.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle ?? '${shelf.bookCount}권',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: const Color(0xFF8A8A8A)),
        ),
      ],
    ),
  );
}

/// 표지 격자 공통 간격 — 즐겨찾기 · 책장 상세 · 책장 만들기 도서 선택
const _coverGrid = SliverGridDelegateWithMaxCrossAxisExtent(
  maxCrossAxisExtent: 150,
  mainAxisSpacing: 20,
  crossAxisSpacing: 18,
  childAspectRatio: .5,
);

/// 책 한 권 — 표지(세로) · 제목 · 저자. overlay 는 표지 위 오른쪽 위(체크·빼기 버튼 등)
class _CoverTile extends StatelessWidget {
  const _CoverTile({required this.book, this.onTap, this.overlay});
  final Book book;
  final VoidCallback? onTap;
  final Widget? overlay;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) => Stack(
              children: [
                BookCover(
                  url: book.coverImageUrl,
                  width: c.maxWidth,
                  height: c.maxHeight,
                ),
                if (overlay != null)
                  Positioned(top: 6, right: 6, child: overlay!),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          book.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        Text(
          book.author ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: Color(0xFF8A8A8A)),
        ),
      ],
    ),
  );
}

class _FavoriteShelfTile extends StatelessWidget {
  const _FavoriteShelfTile();

  @override
  Widget build(BuildContext context) {
    final books = context.watch<FavoriteViewModel>().favorites;
    final covers = books
        .map((book) => book.coverImageUrl)
        .whereType<String>()
        .where((url) => url.isNotEmpty)
        .toList();
    return _ShelfTile(
      shelf: Shelf(
        id: 0,
        name: '즐겨찾기',
        isPublic: false,
        bookCount: books.length,
        coverImageUrl: covers.isEmpty ? null : covers.first,
        previewCoverImageUrls: covers.skip(1).take(2).toList(),
      ),
      subtitle: '${books.length}권',
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const FavoriteBooksScreen()),
        );
        if (context.mounted) context.read<FavoriteViewModel>().load();
      },
    );
  }
}

class _FavoriteBookPicker extends StatefulWidget {
  const _FavoriteBookPicker({
    required this.repository,
    required this.existingBookIds,
  });
  final BookRepository repository;
  final Set<int> existingBookIds;
  @override
  State<_FavoriteBookPicker> createState() => _FavoriteBookPickerState();
}

class _FavoriteBookPickerState extends State<_FavoriteBookPicker> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _matchesSearch(Book book) {
    final query = _query.trim().toLowerCase();
    return query.isEmpty || book.title.toLowerCase().contains(query) ||
        (book.author ?? '').toLowerCase().contains(query);
  }

  late Future<List<Book>> _future;
  final Set<int> _pending = <int>{};
  final Set<int> _added = <int>{};
  Object? _error;

  @override
  void initState() {
    super.initState();
    _future = widget.repository.books();
  }

  void _retry() => setState(() {
    _error = null;
    _future = widget.repository.books();
  });

  Future<void> _add(Book book) async {
    if (_pending.contains(book.id) || _added.contains(book.id)) return;
    setState(() {
      _pending.add(book.id);
      _error = null;
    });
    try {
      await context.read<FavoriteViewModel>().setFavorite(book.id, true);
      if (mounted) setState(() => _added.add(book.id));
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _pending.remove(book.id));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('도서 추가')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            controller: _searchController,
            onChanged: (value) => setState(() => _query = value),
            decoration: InputDecoration(
              hintText: '책 제목 또는 저자 검색',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.isEmpty ? null : IconButton(
                tooltip: '검색어 지우기',
                icon: const Icon(Icons.close),
                onPressed: () {
                  _searchController.clear();
                  setState(() => _query = '');
                },
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        Expanded(child: FutureBuilder<List<Book>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done)
              return const Center(child: CircularProgressIndicator());
            if (snapshot.hasError)
              return _ErrorState(error: snapshot.error, onRetry: _retry);
            final excluded = {...widget.existingBookIds, ..._added};
            final books = (snapshot.data ?? const <Book>[])
                .where((book) => !excluded.contains(book.id) && _matchesSearch(book))
                .toList();
            if (books.isEmpty)
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.library_add_check_outlined, size: 42),
                    const SizedBox(height: 12),
                    Text(_query.trim().isNotEmpty
                        ? '검색 결과가 없습니다.'
                        : '추가할 수 있는 도서가 없습니다.'),
                    TextButton(onPressed: _retry, child: const Text('다시 조회')),
                  ],
                ),
              );
            return Column(
              children: [
                if (_error != null)
                  MaterialBanner(
                    content: const Text('도서 추가에 실패했습니다.'),
                    actions: [
                      TextButton(onPressed: _retry, child: const Text('재시도')),
                    ],
                  ),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate: _coverGrid,
                    itemCount: books.length,
                    itemBuilder: (context, index) {
                      final book = books[index];
                      final pending = _pending.contains(book.id);
                      return _CoverTile(
                        book: book,
                        onTap: pending ? null : () => _add(book),
                        overlay: pending
                            ? const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                            : const Material(
                          color: Colors.white70,
                          shape: CircleBorder(),
                          child: Padding(
                            padding: EdgeInsets.all(5),
                            child: Icon(Icons.add),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        )),
      ],
    ),
  );
}
