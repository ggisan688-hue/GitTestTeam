import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../repository/book_repository.dart';
import '../../viewmodel/book_viewmodel.dart';
import '../../viewmodel/favorite_viewmodel.dart';

import 'friends_screen.dart';
import 'ridi_home.dart';
import 'shelves_screen.dart';
import 'account_screen.dart';
import 'server_notifications_screen.dart';
import 'ridi_store.dart';
import 'ridi_theme.dart';
import 'ridi_auth.dart';

/// 북체인 앱의 시작점 (main.dart → RidiApp).
///
/// 흐름: RidiGate → 로그인 전이면 LoginScreen, 로그인 후면 RidiShell(하단 탭 5개).
/// RidiStore 하나를 Provider 로 앱 전체에 넣어 두고, 모든 화면이 context.watch / read 로 쓴다.
/// 화면 이동·버튼 위치는 리디북스를 따르고, 데이터는 서버 연결 전까지 메모리(RidiStore)에만 둔다.
class RidiApp extends StatefulWidget {
  const RidiApp({super.key});

  @override
  State<RidiApp> createState() => _RidiAppState();
}

class _RidiAppState extends State<RidiApp> {
  late final RidiStore _store;
  late final BookViewModel _books;
  late final FavoriteViewModel _favorites;

  @override
  void initState() {
    super.initState();
    _store = RidiStore();
    _books = BookViewModel(
      BookRepository(ApiClient(tokenProvider: () => _store.accessToken)),
    );
    _favorites = FavoriteViewModel(
      BookRepository(ApiClient(tokenProvider: () => _store.accessToken)),
    );
    ApiClient.onUnauthorized = () => unawaited(_store.logout());
    _store.addListener(_clearBookCacheAfterLogout);
  }

  void _clearBookCacheAfterLogout() {
    if (!_store.loggedIn) {
      _books.clearReaderSession();
      _favorites.clear();
    }
  }

  @override
  void dispose() {
    _store.removeListener(_clearBookCacheAfterLogout);
    ApiClient.onUnauthorized = null;
    _books.dispose();
    _favorites.dispose();
    _store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // These two instances are owned only by RidiAppState.  Descendant
        // dialogs and bottom sheets read the same instances; none may create
        // or dispose a second BookViewModel for the reader.
        ChangeNotifierProvider.value(value: _store),
        ChangeNotifierProvider.value(value: _books),
        ChangeNotifierProvider.value(value: _favorites),
      ],
      child: MaterialApp(
        title: RidiBrand.appName,
        debugShowCheckedModeBanner: false,
        theme: ridiTheme(),
        onGenerateRoute: (settings) {
          final uri = Uri.tryParse(settings.name ?? '');
          if (uri?.path == '/reset-password') {
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => PasswordResetConfirmScreen(
                token: uri?.queryParameters['token'],
              ),
            );
          }
          return null;
        },
        home: const RidiGate(), // 스플래시 없이 바로 시작
      ),
    );
  }
}

/// 로그인 전이면 로그인 화면, 로그인하면 하단 탭 셸. RidiStore.loggedIn 만 보고 바꾼다
/// (로그인·가입·로그아웃이 따로 화면을 이동하지 않아도 여기서 알아서 바뀐다).
class RidiGate extends StatelessWidget {
  const RidiGate({super.key});

  @override
  Widget build(BuildContext context) {
    final authReady = context.select<RidiStore, bool>((s) => s.authReady);
    if (!authReady) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    // Public catalog browsing is available to guests.  Authentication-gated
    // actions lead to LoginScreen from their own entry point instead of
    // replacing the entire app with a forced-login wall.
    return const RidiShell();
  }
}

// ---------------- 하단 탭 셸 ----------------
/// 하단 탭 5개: 내 서재(0) · AI 친구(1) · 홈(2, 시작 탭) · 알림(3, 안 읽은 알림이 있으면 빨간 점) · MY(4).
/// IndexedStack 이라 탭을 오가도 각 화면의 상태(스크롤·고른 탭)가 유지된다.
class RidiShell extends StatefulWidget {
  const RidiShell({super.key});

  @override
  State<RidiShell> createState() => _RidiShellState();
}

class _RidiShellState extends State<RidiShell> {
  late final List<Widget?> _pages;
  int _index = 2; // 리디처럼 홈에서 시작

  static const _tabs = [
    (Icons.collections_bookmark_outlined, Icons.collections_bookmark, '내 서재'),
    (Icons.smart_toy_outlined, Icons.smart_toy, 'AI 친구'),
    (Icons.home_outlined, Icons.home, '홈'),
    (Icons.notifications_none_rounded, Icons.notifications, '알림'),
    (Icons.person_outline_rounded, Icons.person, '마이'),
  ];

  @override
  void initState() {
    super.initState();
    // Keep a visited tab alive, but defer construction of the other heavy
    // lists and image trees until the user actually opens that tab.
    _pages = List<Widget?>.filled(_tabs.length, null);
    _pages[_index] = const HomeScreen();
  }

  Widget _create(int i) => switch (i) {
    // Do not use const here: a canonical const widget can retain the old
    // Element/State even after IndexedStack's slot is replaced.
    0 => ShelvesScreen(),
    1 => FriendsScreen(),
    2 => HomeScreen(),
    3 => const ServerNotificationsScreen(),
    _ => const AccountScreen(),
  };

  /// 탭 바꾸기. 게스트는 홈 말고는 서버 화면을 만들지 않고 "로그인이 필요" 화면을 보여 준다(build 참고).
  void select(int i) {
    final loggedIn = context.read<RidiStore>().loggedIn;
    setState(() {
      _index = i;
      if (!loggedIn && i != 2) return;
      // IndexedStack keeps visited tabs alive, so their initState fetches do
      // not run again. Recreate only server-backed tabs on selection; reader
      // routes themselves stay outside this shell and are unaffected.
      if (i == 0 || i == 1 || i == 2) _pages[i] = null;
      _pages[i] ??= _create(i);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Builder(
        builder: (context) {
          final loggedIn = context.select<RidiStore, bool>((s) => s.loggedIn);
          // 게스트 → 로그인 팝업으로 로그인하면, 보던 탭의 실제 화면을 그때 만든다
          if (loggedIn && _pages[_index] == null)
            _pages[_index] = _create(_index);
          return IndexedStack(
            index: _index,
            children: [
              for (var i = 0; i < _pages.length; i++)
                if (!loggedIn && i == 4)
                  const _GuestMy()
                else if (!loggedIn && i != 2)
                  _GuestTab(title: _tabs[i].$3)
                else
                  _pages[i] ?? const SizedBox.shrink(),
            ],
          );
        },
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: RidiColors.grayLight)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 72,
            child: Row(
              children: [
                for (var i = 0; i < _tabs.length; i++)
                  Expanded(
                    child: InkWell(
                      onTap: () => select(i),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          i == 3
                              ? UnreadNotificationBadge(
                                  child: Icon(
                                    i == _index ? _tabs[i].$2 : _tabs[i].$1,
                                    size: 28,
                                    color: i == _index
                                        ? RidiColors.ink
                                        : RidiColors.gray,
                                  ),
                                )
                              : Icon(
                                  i == _index ? _tabs[i].$2 : _tabs[i].$1,
                                  size: 28,
                                  color: i == _index
                                      ? RidiColors.ink
                                      : RidiColors.gray,
                                ),
                          const SizedBox(height: 6),
                          Text(
                            _tabs[i].$3,
                            style: i == _index ? RidiText.navOn : RidiText.nav,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------- 게스트(로그인 전) 탭 화면 ----------------
/// 내 서재 · AI 친구 · 알림 — 가운데 "로그인이 필요한 서비스입니다." + [로그인] (누르면 가운데 로그인 창)
class _GuestTab extends StatelessWidget {
  const _GuestTab({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
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
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
            ),
            child: const Text('로그인'),
          ),
        ],
      ),
    ),
  );
}

/// 마이 — 게스트: 위에 "로그인이 필요합니다." + 오른쪽 [로그인] 버튼만 (리디 MY 처럼)
class _GuestMy extends StatelessWidget {
  const _GuestMy();

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: RidiColors.panel,
    appBar: AppBar(title: const Text('마이')),
    body: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  '로그인이 필요합니다.',
                  style: TextStyle(
                    fontFamily: RidiText.f,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: RidiColors.ink,
                  ),
                ),
              ),
              FilledButton(
                onPressed: () => showLoginDialog(context),
                style: FilledButton.styleFrom(
                  backgroundColor: RidiColors.blue,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                child: const Text('로그인'),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
