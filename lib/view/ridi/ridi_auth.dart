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

/// 앱 로고·이름 + 아이디/비밀번호 + 로그인 · 회원가입 · 비밀번호 찾기.
/// 맨 아래 "made by 이팀" 엠블렘은 스플래시에서 날아와 앉는 자리(Hero 태그 RidiBrand.emblemHero).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
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

  // 더미 계정이면 그 사람으로, 아니면 기본 계정으로 → 메인(홈 탭). 더미 계정 비밀번호가 틀리면 오류 문구
  /* void _submit() {
    FocusScope.of(context).unfocus();
    final ok = context.read<RidiStore>().login(_id.text, _pw.text);
    setState(() => _error = ok ? null : '비밀번호가 맞지 않아요');
  }

  */
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
  }

  @override
  Widget build(BuildContext context) => ScreenTag('RIDI_LOGIN_01', child: _screen(context));

  Widget _screen(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: _RiseIn(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(child: Image.asset(RidiBrand.logo, width: 88, height: 88)),
                          const SizedBox(height: 18),
                          const Text(RidiBrand.appName, textAlign: TextAlign.center, style: TextStyle(fontFamily: RidiText.f, fontSize: 34, fontWeight: FontWeight.w800, color: RidiColors.ink)),
                          const SizedBox(height: 10),
                          const Text(RidiBrand.tagline, textAlign: TextAlign.center, style: RidiText.sub),
                          const SizedBox(height: 40),
                          // "아이디"도 허용하므로 이메일 전용 키보드를 강제하지
                          // 않는다. Android 한글 IME가 일반 텍스트 입력 연결을
                          // 사용해 조합 상태를 유지할 수 있다.
                          RidiInput(controller: _id, hint: '이메일 또는 아이디'),
                          const SizedBox(height: 16),
                          RidiInput(controller: _pw, hint: '비밀번호', obscure: true, onSubmitted: (_) => _submit()),
                          if (_error != null) ...[
                            const SizedBox(height: 10),
                            Text(_error!, textAlign: TextAlign.center, style: RidiText.sub.copyWith(color: RidiColors.red)),
                          ],
                          const SizedBox(height: 24),
                          RidiButton('로그인', onTap: _submit, expand: true),
                          const SizedBox(height: 24),
                          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            const Text('아직 계정이 없나요?', style: RidiText.sub),
                            TextButton(
                              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SignupScreen())),
                              child: const Text('회원가입', style: TextStyle(fontFamily: RidiText.f, fontSize: 14, fontWeight: FontWeight.w700, color: RidiColors.ink)),
                            ),
                          ]),
                          const Divider(height: 40),
                          Center(
                            child: TextButton(
                              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PasswordResetScreen())),
                              child: const Text('비밀번호 찾기', style: TextStyle(fontFamily: RidiText.f, fontSize: 14, color: RidiColors.gray)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // 스플래시의 팀 엠블렘이 날아와 앉는 자리
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Hero(tag: RidiBrand.emblemHero, child: Image(image: AssetImage(RidiBrand.teamEmblem), width: 40, height: 40)),
                const SizedBox(width: 10),
                Text('made by ${RidiBrand.teamName}', style: RidiText.sub),
              ]),
            ),
          ],
        ),
      ),
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
