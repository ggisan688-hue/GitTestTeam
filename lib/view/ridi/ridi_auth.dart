import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'ridi_store.dart';
import 'ridi_theme.dart';
import 'ridi_widgets.dart';
import '../../widgets/screen_tag.dart';

/// 로그인 전 화면들 — RIDI_LOGIN_01 로그인 · RIDI_SIGNUP_01 회원가입 · RIDI_PW_01 비밀번호 찾기 (UC-01, UC-02)
///
/// 지금은 서버 인증 없이: 더미 계정 5개(김기산·서성민·손지유·윤강은·박성필, 비밀번호 1234)는 그 사람으로,
/// 그 밖의 값(빈칸 포함)은 기본 계정(박성필)으로 통과. 회원가입은 형식만 검사하고 새 사람으로 바로 로그인.
/// 서버 연결 시: 로그인 = POST /api/members/login, 가입 = POST /api/members/signup (+ 이메일·아이디 중복 확인),
/// 비밀번호 찾기 = POST /api/members/password-reset.

/// 로그인 창 — 화면 가운데 팝업 (리디처럼). 게스트가 로그인 버튼을 누르면 어디서든 이 창이 뜬다.
/// 로그인에 성공하면 창이 닫히고, 보던 화면이 로그인 상태로 바뀐다.
Future<void> showLoginDialog(BuildContext context) => showDialog<void>(
      context: context,
      builder: (_) => const _LoginDialog(),
    );

class _LoginDialog extends StatelessWidget {
  const _LoginDialog();

  @override
  Widget build(BuildContext context) => ScreenTag(
        'RIDI_LOGIN_01',
        child: Dialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          insetPadding: const EdgeInsets.all(24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // 머리: 가운데 "로그인" + 오른쪽 닫기
              SizedBox(
                height: 56,
                width: double.infinity,
                child: Stack(alignment: Alignment.center, children: [
                  const Text('로그인', style: TextStyle(fontFamily: RidiText.f, fontSize: 17, fontWeight: FontWeight.w700, color: RidiColors.ink)),
                  Positioned(
                    right: 4,
                    child: IconButton(
                      tooltip: '닫기',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ]),
              ),
              const Divider(height: 1, color: RidiColors.grayLight),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
                  child: const _LoginForm(compact: true),
                ),
              ),
            ]),
          ),
        ),
      );
}

/// 로그인 화면(전체 화면) — 로그아웃 직후 등 화면 전체가 필요할 때. 내용은 팝업과 같은 _LoginForm.
/// 맨 아래 "made by 2page" (팀 이름 = RidiBrand.teamName).
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) => ScreenTag(
        'RIDI_LOGIN_01',
        child: Scaffold(
          body: SafeArea(
            child: Column(children: [
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: const _RiseIn(child: _LoginForm(compact: false)),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ),
      );
}

/// 앱 로고·이름 + 아이디/비밀번호 + 로그인 · 회원가입 · 비밀번호 찾기 + "made by 2page".
/// compact = 팝업용(로고·글자를 조금 작게).
class _LoginForm extends StatefulWidget {
  const _LoginForm({required this.compact});

  final bool compact;

  @override
  State<_LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<_LoginForm> {
  final _id = TextEditingController();
  final _pw = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _id.dispose();
    _pw.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await context.read<RidiStore>().login(_id.text, _pw.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
    // 팝업이든 전체 화면이든, 성공하면 닫고 보던 화면으로 돌아간다.
    if (error == null && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.compact;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Center(child: Image.asset(RidiBrand.logo, width: c ? 56 : 88, height: c ? 56 : 88)),
        SizedBox(height: c ? 12 : 18),
        Text(RidiBrand.appName, textAlign: TextAlign.center, style: TextStyle(fontFamily: RidiText.f, fontSize: c ? 26 : 34, fontWeight: FontWeight.w800, color: RidiColors.ink)),
        const SizedBox(height: 8),
        const Text(RidiBrand.tagline, textAlign: TextAlign.center, style: RidiText.sub),
        SizedBox(height: c ? 28 : 40),
        // "아이디"도 허용하므로 이메일 전용 키보드를 강제하지 않는다.
        // Android 한글 IME가 일반 텍스트 입력 연결을 사용해 조합 상태를 유지할 수 있다.
        RidiInput(controller: _id, hint: '이메일 또는 아이디'),
        const SizedBox(height: 12),
        RidiInput(controller: _pw, hint: '비밀번호', obscure: true, onSubmitted: (_) => _submit()),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, textAlign: TextAlign.center, style: RidiText.sub.copyWith(color: RidiColors.red)),
        ],
        const SizedBox(height: 20),
        RidiButton('로그인', onTap: _submit, expand: true),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Text('아직 계정이 없나요?', style: RidiText.sub),
          TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SignupScreen())),
            child: const Text('회원가입', style: TextStyle(fontFamily: RidiText.f, fontSize: 14, fontWeight: FontWeight.w700, color: RidiColors.ink)),
          ),
        ]),
        Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PasswordResetScreen())),
            child: const Text('비밀번호 찾기', style: TextStyle(fontFamily: RidiText.f, fontSize: 14, color: RidiColors.gray)),
          ),
        ),
        // 팀 이름은 전체 화면 로그인에만 (가운데 팝업에서는 뺌)
        if (!c) ...[
          const SizedBox(height: 32),
          Text('made by ${RidiBrand.teamName}', textAlign: TextAlign.center, style: RidiText.sub),
        ],
      ],
    );
  }
}

/// 로그인 폼이 아래에서 살짝 올라오며 나타남
class _RiseIn extends StatelessWidget {
  const _RiseIn({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, 24 * (1 - v)), child: child),
      ),
    );
  }
}

/// 이메일 · 아이디 · 비밀번호 · 확인 · 이름 + 약관 동의. 검사를 통과하면 로그인 상태로 홈.
class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _email = TextEditingController();
  final _id = TextEditingController();
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();
  final _name = TextEditingController();
  bool _agree = false;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_email, _id, _pw, _pw2, _name]) {
      c.dispose();
    }
    super.dispose();
  }

  /// 위에서부터 하나씩 검사해 첫 오류만 보여 준다: 이메일 @ · 아이디 4자 · 비밀번호 8자 · 확인 일치 · 이름 · 약관
  /* void _submit() {
    String? e;
    if (!_email.text.contains('@')) {
      e = '이메일 형식이 올바르지 않습니다';
    } else if (_id.text.trim().length < 4) {
      e = '아이디는 4자 이상이어야 합니다';
    } else if (_pw.text.length < 8) {
      e = '비밀번호는 8자 이상이어야 합니다';
    } else if (_pw.text != _pw2.text) {
      e = '비밀번호가 일치하지 않습니다';
    } else if (_name.text.trim().isEmpty) {
      e = '이름을 입력해주세요';
    } else if (!_agree) {
      e = '약관에 동의해주세요';
    }
    setState(() => _error = e);
    if (e != null) return;
    context.read<RidiStore>().signup(_name.text);
    Navigator.of(context).pop(); // 게이트가 셸로 바꿔 준다
  }

  */
  Future<void> _submit() async {
    if (_busy) return;
    final username = _id.text.trim();
    final nickname = _name.text.trim();
    String? validationError;
    if (!RegExp(r'^[A-Za-z0-9_]{4,20}$').hasMatch(username)) {
      validationError = '아이디는 영문, 숫자, 밑줄 4~20자로 입력해주세요.';
    } else if (_pw.text.length < 8) {
      validationError = '비밀번호는 8자 이상이어야 합니다.';
    } else if (_pw.text != _pw2.text) {
      validationError = '비밀번호 확인이 일치하지 않습니다.';
    } else if (nickname.isEmpty) {
      validationError = '닉네임을 입력해주세요.';
    } else if (!_agree) {
      validationError = '이용약관에 동의해주세요.';
    }
    if (validationError != null) {
      setState(() => _error = validationError);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await context.read<RidiStore>().signup(username: username, password: _pw.text, nickname: nickname);
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    ridiToast(context, '회원가입이 완료되었습니다. 로그인해주세요.');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => ScreenTag('RIDI_SIGNUP_01', child: _screen(context));

  Widget _screen(BuildContext context) {
    return Scaffold(
      appBar: ridiAppBar(context, '회원가입'),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  RidiInput(controller: _email, hint: '이메일', keyboard: TextInputType.emailAddress),
                  const SizedBox(height: 12),
                  RidiInput(controller: _id, hint: '아이디 (영문·숫자·_ 4~30자)'),
                  const SizedBox(height: 12),
                  RidiInput(controller: _pw, hint: '비밀번호 (8자 이상)', obscure: true),
                  const SizedBox(height: 12),
                  RidiInput(controller: _pw2, hint: '비밀번호 확인', obscure: true),
                  const SizedBox(height: 12),
                  RidiInput(controller: _name, hint: '이름', onSubmitted: (_) => _submit()),
                  const SizedBox(height: 20),
                  InkWell(
                    onTap: () => setState(() => _agree = !_agree),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(children: [
                        Icon(_agree ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded, size: 22, color: _agree ? RidiColors.pillBlack : RidiColors.gray),
                        const SizedBox(width: 10),
                        const Expanded(child: Text('이용약관 및 개인정보 처리방침 동의 (필수)', style: RidiText.body)),
                      ]),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, textAlign: TextAlign.center, style: RidiText.sub.copyWith(color: RidiColors.red)),
                  ],
                  const SizedBox(height: 20),
                  RidiButton('가입하기', onTap: _submit, expand: true),
                  const SizedBox(height: 12),
                  Center(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('이미 계정이 있어요', style: TextStyle(fontFamily: RidiText.f, fontSize: 14, color: RidiColors.gray)),
                    ),
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

/// RIDI_PW_01 비밀번호 찾기 — 이메일로 재설정 링크 (서버: 메일 발송)
class PasswordResetScreen extends StatefulWidget {
  const PasswordResetScreen({super.key});

  @override
  State<PasswordResetScreen> createState() => _PasswordResetScreenState();
}

class _PasswordResetScreenState extends State<PasswordResetScreen> {
  final _email = TextEditingController();
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  /// 이메일에 @ 가 있으면 "보냈어요" 상태로 바꾼다. 가입 여부는 알려주지 않는다(서버도 항상 같은 응답)
  void _send() {
    final e = _email.text.trim();
    if (!e.contains('@') || e.startsWith('@') || e.endsWith('@')) {
      setState(() => _error = '이메일 형식을 확인해주세요');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _error = null;
      _sent = true;
    });
  }

  @override
  Widget build(BuildContext context) => ScreenTag('RIDI_PW_01', child: _screen(context));

  Widget _screen(BuildContext context) {
    return Scaffold(
      appBar: ridiAppBar(context, '비밀번호 찾기'),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: _sent
                  ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      const Icon(Icons.mark_email_read_outlined, size: 56, color: RidiColors.ink),
                      const SizedBox(height: 16),
                      const Text('메일을 보냈어요', textAlign: TextAlign.center, style: TextStyle(fontFamily: RidiText.f, fontSize: 22, fontWeight: FontWeight.w800, color: RidiColors.ink)),
                      const SizedBox(height: 10),
                      Text('${_email.text.trim()} 로 보낸 링크를 열어 새 비밀번호를 정해주세요.\n메일이 안 오면 스팸함도 확인해주세요.', textAlign: TextAlign.center, style: RidiText.sub.copyWith(fontSize: 14)),
                      const SizedBox(height: 32),
                      RidiButton('로그인으로 돌아가기', expand: true, onTap: () => Navigator.of(context).pop()),
                      const SizedBox(height: 8),
                      Center(
                        child: TextButton(
                          onPressed: () => ridiToast(context, '메일을 다시 보냈어요'),
                          child: const Text('메일 다시 보내기', style: TextStyle(fontFamily: RidiText.f, fontSize: 14, color: RidiColors.gray)),
                        ),
                      ),
                    ])
                  : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      const Text('가입한 이메일을 적어주세요', style: TextStyle(fontFamily: RidiText.f, fontSize: 22, fontWeight: FontWeight.w800, color: RidiColors.ink)),
                      const SizedBox(height: 8),
                      const Text('비밀번호를 다시 정할 수 있는 링크를 보내드려요', style: RidiText.sub),
                      const SizedBox(height: 32),
                      RidiInput(controller: _email, hint: '이메일', keyboard: TextInputType.emailAddress, autofocus: true, onSubmitted: (_) => _send()),
                      if (_error != null) ...[
                        const SizedBox(height: 10),
                        Text(_error!, style: RidiText.sub.copyWith(color: RidiColors.red)),
                      ],
                      const SizedBox(height: 24),
                      RidiButton('재설정 메일 보내기', expand: true, onTap: _send),
                    ]),
            ),
          ),
        ),
      ),
    );
  }
}
