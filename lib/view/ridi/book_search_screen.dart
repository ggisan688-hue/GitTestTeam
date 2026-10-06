import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../model/book.dart';
import '../../repository/book_repository.dart';
import '../../repository/shelf_repository.dart';
import '../../model/shelf.dart';
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
  String? _category;
  Object? _error;

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
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(() {
        _error = null;
        _results = _repository.search(term, category: _category).catchError((
          Object error,
        ) {
          _error = error;
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
              hintText: '제목 또는 저자로 검색',
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: DropdownButtonFormField<String?>(
            value: _category,
            decoration: const InputDecoration(
              labelText: '카테고리',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: null, child: Text('전체 카테고리')),
            ],
            onChanged: (value) {
              setState(() => _category = value);
              _search(_query.text);
            },
          ),
        ),
        const SizedBox(height: 8),
        Expanded(child: _body()),
      ],
    ),
  );

  Widget _body() {
    if (_results == null)
      return const Center(child: Text('제목 또는 저자를 입력해 주세요.'));
    return FutureBuilder<List<Book>>(
      future: _results,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done)
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
        final books = snapshot.data ?? const [];
        if (books.isEmpty) return const Center(child: Text('검색 결과가 없습니다.'));
        return ListView.separated(
          itemCount: books.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final book = books[index];
            return ListTile(
              leading: const Icon(Icons.menu_book_outlined),
              title: Text(book.title),
              subtitle: Text(
                '${book.author ?? ''}${book.category?.isNotEmpty == true ? ' · ${book.category}' : ''}',
              ),
              trailing: IconButton(
                tooltip: '책장에 담기',
                icon: const Icon(Icons.playlist_add_outlined),
                onPressed: () => _addToShelf(book),
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => BookDetailScreen(bookId: book.id),
                ),
              ),
            );
          },
        );
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
        builder: (context) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final value in choices)
                ListTile(
                  title: Text(value.name),
                  subtitle: Text('${value.bookCount}권'),
                  onTap: () => Navigator.pop(context, value),
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
    } on ApiException catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }
}
