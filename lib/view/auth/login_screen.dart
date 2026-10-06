import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../theme/app_theme.dart';
import '../../viewmodel/auth_viewmodel.dart';
import '../rooms/rooms_screen.dart';
import 'auth_scaffold.dart';
import 'signup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _login = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _login.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final auth = context.read<AuthViewModel>();
    final ok = await auth.login(_login.text, _password.text);
    if (!mounted || !ok) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const RoomsScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthViewModel>();

    return AuthScaffold(
      tag: 'S01',
      title: '로그인',
      subtitle: '읽던 책과 메모가 기다리고 있어요',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _login,
            decoration: const InputDecoration(labelText: '이메일 또는 아이디'),
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: AppSpace.md),
          TextField(
            controller: _password,
            decoration: const InputDecoration(labelText: '비밀번호'),
            obscureText: true,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: AppSpace.lg),
          if (auth.errorMessage != null) ...[
            Text(
              auth.errorMessage!,
              style: AppText.error,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpace.md),
          ],
          FilledButton(
            onPressed: auth.isLoading ? null : _submit,
            child: auth.isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('로그인'),
          ),
          const SizedBox(height: AppSpace.lg),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('아직 계정이 없나요?', style: AppText.labelMuted),
              TextButton(
                onPressed: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const SignupScreen())),
                child: const Text('회원가입'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
