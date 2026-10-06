import 'package:flutter/material.dart';

import 'dart:async';

import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../model/book.dart';
import '../../model/shelf.dart';
import '../../repository/book_repository.dart';
import '../../repository/shelf_repository.dart';
import '../../viewmodel/favorite_viewmodel.dart';
import 'book_catalog.dart';
import 'reading_rooms_screen.dart';
import 'ridi_store.dart';

class ShelvesScreen extends StatefulWidget {
  const ShelvesScreen({super.key});

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
    _tabs = TabController(length: 2, vsync: this)
      ..addListener(() {
        if (!_tabs.indexIsChanging && mounted && _section != _tabs.index) {
          setState(() => _section = _tabs.index);
        }
      });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<List<Shelf>> _loadShelves() async {
    final shelves = await _repository.list();
    _shelfCache = shelves;
    return shelves;
  }

  void _reloadShelves() => setState(() => _shelves = _loadShelves());

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
      actions: [
        FutureBuilder<List<Shelf>>(
          future: _shelves,
          builder: (context, snapshot) {
            final shelves = snapshot.data ?? const <Shelf>[];
            // 책장 메뉴(⋮)는 내 책장 탭에서만 — 교환독서 탭에서는 숨김 (수정 확인 피드백)
            if (shelves.isEmpty || _section != 0)
              return const SizedBox.shrink();
            return PopupMenuButton<String>(
              tooltip: '책장 메뉴',
              onSelected: (value) {
                if (value == 'deleteAll') _deleteAllShelves(shelves.length);
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'deleteAll',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline),
                      SizedBox(width: 10),
                      Text('책장 전체 삭제'),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ],
    ),
    body: _section == 1
        ? const ReadingRoomsScreen(embedded: true)
        : RefreshIndicator(
            onRefresh: _refresh,
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: _FavoriteSection(
                    future: Future.value(
                      context.watch<FavoriteViewModel>().favorites,
                    ),
                    onRetry: () => context.read<FavoriteViewModel>().load(),
                  ),
                ),
                FutureBuilder<List<Shelf>>(
                  future: _shelves,
                  builder: (context, snapshot) {
                    final shelves = snapshot.data ?? const <Shelf>[];
                    return SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                        child: Row(
                          children: [
                            Text(
                              '내 책장',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const Spacer(),
                            if (shelves.isNotEmpty)
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
                    if (shelves.isEmpty)
                      return SliverToBoxAdapter(
                        child: SizedBox(
                          height: 180,
                          child: _EmptyShelves(onCreate: _create),
                        ),
                      );
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
                        itemCount: shelves.length,
                        itemBuilder: (context, index) {
                          final shelf = shelves[index];
                          return _ShelfTile(
                            shelf: shelf,
                            onTap: () async {
                              final deletedShelfId = await Navigator.of(context)
                                  .push<int>(
                                    MaterialPageRoute(
                                      builder: (_) => ShelfDetailScreen(
                                        repository: _repository,
                                        shelfId: shelf.id,
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
                const SliverToBoxAdapter(child: SizedBox(height: 96)),
              ],
            ),
          ),
  );
}

class _FavoriteSection extends StatelessWidget {
  const _FavoriteSection({required this.future, required this.onRetry});
  final Future<List<Book>> future;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => FutureBuilder<List<Book>>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done)
        return const SizedBox(
          height: 190,
          child: Center(child: CircularProgressIndicator()),
        );
      if (snapshot.hasError)
        return SizedBox(
          height: 150,
          child: _ErrorState(error: snapshot.error, onRetry: onRetry),
        );
      final books = snapshot.data ?? const [];
      return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(
                    '즐겨찾기 도서',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const FavoriteBooksScreen(),
                      ),
                    ),
                    child: const Text('전체보기'),
                  ),
                ],
              ),
            ),
            if (books.isEmpty)
              const SizedBox(
                height: 92,
                child: Center(child: Text('즐겨찾기한 도서가 없습니다.')),
              )
            else
              SizedBox(
                height: 168,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: books.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    final book = books[index];
                    return SizedBox(
                      width: 116,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => BookDetailScreen(bookId: book.id),
                            ),
                          );
                          if (context.mounted) onRetry();
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            BookCover(
                              url: book.coverImageUrl,
                              width: 88,
                              height: 116,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              book.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              book.author ?? '',
                              style: Theme.of(context).textTheme.bodySmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      );
    },
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
    body: FutureBuilder<List<Book>>(
      future: _favorites,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done)
          return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError)
          return _ErrorState(error: snapshot.error, onRetry: _reload);
        final books = snapshot.data ?? const [];
        if (books.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.favorite_border, size: 44),
                SizedBox(height: 12),
                Text('즐겨찾기한 도서가 없습니다.'),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          // 표지가 큰 세로 카드 격자 (필기 수정2-33)
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            gridDelegate: _coverGrid,
            itemCount: books.length,
            itemBuilder: (context, index) {
              final book = books[index];
              return _CoverTile(
                book: book,
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => BookDetailScreen(bookId: book.id),
                    ),
                  );
                  if (mounted) _reload();
                },
              );
            },
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
  });

  final ShelfRepository repository;
  final int shelfId;

  @override
  State<ShelfDetailScreen> createState() => _ShelfDetailScreenState();
}

class _ShelfDetailScreenState extends State<ShelfDetailScreen> {
  late Future<ShelfDetail> _detail;

  @override
  void initState() {
    super.initState();
    _detail = widget.repository.detail(widget.shelfId);
  }

  void _reload() =>
      setState(() => _detail = widget.repository.detail(widget.shelfId));

  Future<void> _edit(Shelf shelf) async {
    final values = await showShelfEditor(context, shelf: shelf);
    if (values == null || !mounted) return;
    try {
      await widget.repository.update(
        widget.shelfId,
        name: values.name,
        description: values.description,
        isPublic: values.isPublic,
      );
      _reload();
    } on ApiException catch (error) {
      if (mounted) _showError(context, error);
    }
  }

  Future<void> _deleteLegacy() async {
    final ok =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('책장을 삭제할까요?'),
            content: const Text('책장만 삭제되며, 원본 도서와 읽기 기록은 유지됩니다.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('삭제'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok || !mounted) return;
    try {
      await widget.repository.delete(widget.shelfId);
      if (mounted) Navigator.pop(context, widget.shelfId);
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

  Future<void> _addBook() async {
    final selected = await Navigator.of(context)
        .push<Book>(MaterialPageRoute(builder: (_) => _BookPicker()));
    if (selected == null || !mounted) return;
    try {
      await widget.repository.addBook(widget.shelfId, selected.id);
      _reload();
    } on ApiException catch (error) {
      if (mounted) _showError(context, error);
    }
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
              '${detail.shelf.bookCount}권 · ${detail.shelf.isPublic ? '공개 책장' : '비공개 책장'}',
            ),
            const Divider(height: 36),
            if (detail.books.isEmpty)
              _EmptyBooks(onAdd: _addBook)
            else
              // 표지 격자 (필기 수정2-38). 표지 오른쪽 위 [−] = 책장에서 빼기
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
                        builder: (_) => BookDetailScreen(bookId: book.id),
                      ),
                    ),
                    overlay: Material(
                      color: Colors.white.withValues(alpha: .92),
                      shape: const CircleBorder(),
                      child: IconButton(
                        tooltip: '책장에서 제거',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.remove_circle_outline, size: 20),
                        onPressed: () async {
                          try {
                            await widget.repository.removeBook(
                              widget.shelfId,
                              book.id,
                            );
                            _reload();
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
  bool _isPublic = false;
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
        isPublic: _isPublic,
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
    body: Column(
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
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('공개 책장'),
                value: _isPublic,
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _isPublic = value),
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
        Expanded(
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
  @override
  State<_BookPicker> createState() => _BookPickerState();
}

class _BookPickerState extends State<_BookPicker> {
  late final BookRepository _books;
  late Future<List<Book>> _future;

  @override
  void initState() {
    super.initState();
    _books = BookRepository(
      ApiClient(tokenProvider: () => context.read<RidiStore>().accessToken),
    );
    _future = _books.books();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('도서 추가')),
    body: FutureBuilder<List<Book>>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        return ListView(
          children: [
            for (final book in snapshot.data!)
              ListTile(
                leading: const Icon(Icons.menu_book_outlined),
                title: Text(book.title),
                subtitle: Text(book.author ?? ''),
                onTap: () => Navigator.pop(context, book),
              ),
          ],
        );
      },
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
  const _ShelfTile({required this.shelf, required this.onTap});
  final Shelf shelf;
  final VoidCallback onTap;

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
            child: const Icon(
              Icons.collections_bookmark_outlined,
              size: 44,
              color: Color(0xFF8A94A8),
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
          '${shelf.bookCount}권 · ${shelf.isPublic ? '공개' : '비공개'}',
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
