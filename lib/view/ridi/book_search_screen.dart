import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../model/book.dart';
import '../../model/shelf.dart';
import '../../repository/book_repository.dart';
import '../../repository/shelf_repository.dart';
import 'book_catalog.dart';
import 'ridi_store.dart';

class BookSearchScreen extends StatefulWidget {
  const BookSearchScreen({super.key});
  @override
  State<BookSearchScreen> createState() => _BookSearchScreenState();
}

class _BookSearchScreenState extends State<BookSearchScreen> {
  final _query = TextEditingController();
  Timer? _debounce;
  late final BookRepository _repository;
  Future<List<Book>>? _results;
  Object? _error;
  int _request = 0;
  @override
  void initState() {
    super.initState();
    _repository = BookRepository(
      ApiClient(tokenProvider: () => context.read<RidiStore>().accessToken),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _search(String value) {
    _debounce?.cancel();
    final term = value.trim();
    if (term.isEmpty) {
      setState(() {
        _results = null;
        _error = null;
      });
      return;
    }
    final request = ++_request;
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(() {
        _error = null;
        _results = _repository.search(term).catchError((Object e) {
          if (mounted && request == _request) _error = e;
          return <Book>[];
        });
      });
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('도서 검색')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _query,
            autofocus: true,
            onChanged: _search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _query.clear();
                        _search('');
                      },
                    ),
              hintText: '제목, 저자, 카테고리 검색',
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        Expanded(child: _body()),
      ],
    ),
  );
  Widget _body() {
    if (_results == null) return const Center(child: Text('검색어를 입력해 주세요.'));
    return FutureBuilder<List<Book>>(
      future: _results,
      builder: (context, s) {
        if (s.connectionState != ConnectionState.done)
          return const Center(child: CircularProgressIndicator());
        if (_error != null)
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _error is ApiException
                      ? (_error as ApiException).message
                      : '검색에 실패했습니다.',
                ),
                OutlinedButton(
                  onPressed: () => _search(_query.text),
                  child: const Text('다시 시도'),
                ),
              ],
            ),
          );
        final books = s.data ?? const <Book>[];
        if (books.isEmpty) return const Center(child: Text('검색 결과가 없습니다.'));
        return _SearchGrid(books: books, onAdd: _addToShelf);
      },
    );
  }

  Future<void> _addToShelf(Book book) async {
    final shelves = ShelfRepository(
      ApiClient(tokenProvider: () => context.read<RidiStore>().accessToken),
    );
    try {
      final choices = await shelves.list();
      if (!mounted) return;
      if (choices.isEmpty) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('먼저 책장을 만들어 주세요.')));
        return;
      }
      final shelf = await showModalBottomSheet<Shelf>(
        context: context,
        builder: (sheet) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final item in choices)
                ListTile(
                  title: Text(item.name),
                  subtitle: Text('${item.bookCount}권'),
                  onTap: () => Navigator.pop(sheet, item),
                ),
            ],
          ),
        ),
      );
      if (shelf == null || !mounted) return;
      await shelves.addBook(shelf.id, book.id);
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('${shelf.name}에 담았습니다.')));
    } on ApiException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

class _SearchGrid extends StatelessWidget {
  const _SearchGrid({required this.books, required this.onAdd});
  final List<Book> books;
  final ValueChanged<Book> onAdd;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final cols = c.maxWidth >= 750
          ? 5
          : (c.maxWidth / 148).floor().clamp(2, 4).toInt();
      return GridView.builder(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          mainAxisSpacing: 22,
          crossAxisSpacing: 16,
          childAspectRatio: .49,
        ),
        itemCount: books.length,
        itemBuilder: (context, i) => BookCatalogCard(
          book: books[i],
          onAddToShelf: () => onAdd(books[i]),
        ),
      );
    },
  );
}
