import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../model/signup_request.dart';
import '../../theme/app_theme.dart';
import '../../viewmodel/auth_viewmodel.dart';
import 'auth_scaffold.dart';
import 'signup_success_screen.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _name = TextEditingController();

  @override
  void dispose() {
    for (final c in [_email, _username, _password, _confirm, _name]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthViewModel>();
    final ok = await auth.signup(SignupRequest(
      email: _email.text.trim(),
      username: _username.text.trim(),
      password: _password.text,
      name: _name.text.trim(),
    ));
    if (!mounted || !ok) return;
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const SignupSuccessScreen()), (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthViewModel>();

    return AuthScaffold(
      tag: 'S02',
      title: '회원가입',
      subtitle: '친구와 함께 읽고 메모를 나눠보세요',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _email,
              decoration: const InputDecoration(labelText: '이메일'),
              keyboardType: TextInputType.emailAddress,
              validator: (v) => v == null || !v.contains('@') ? '이메일 형식이 올바르지 않습니다' : null,
            ),
            const SizedBox(height: AppSpace.md),
            TextFormField(
              controller: _username,
              decoration: const InputDecoration(labelText: '아이디', helperText: '영문, 숫자, _ 4~30자'),
              validator: (v) => v == null || v.trim().length < 4 ? '아이디는 4자 이상이어야 합니다' : null,
            ),
            const SizedBox(height: AppSpace.md),
            TextFormField(
              controller: _password,
              decoration: const InputDecoration(labelText: '비밀번호', helperText: '8자 이상'),
              obscureText: true,
              validator: (v) => v == null || v.length < 8 ? '비밀번호는 8자 이상이어야 합니다' : null,
            ),
            const SizedBox(height: AppSpace.md),
            TextFormField(
              controller: _confirm,
              decoration: const InputDecoration(labelText: '비밀번호 확인'),
              obscureText: true,
              validator: (v) => v != _password.text ? '비밀번호가 일치하지 않습니다' : null,
            ),
            const SizedBox(height: AppSpace.md),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: '이름'),
              validator: (v) => v == null || v.trim().isEmpty ? '이름을 입력해주세요' : null,
            ),
            const SizedBox(height: AppSpace.lg),
            if (auth.errorMessage != null) ...[
              Text(auth.errorMessage!, style: AppText.error, textAlign: TextAlign.center),
              const SizedBox(height: AppSpace.md),
            ],
            FilledButton(
              onPressed: auth.isLoading ? null : _submit,
              child: auth.isLoading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('가입하기'),
            ),
            const SizedBox(height: AppSpace.sm),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('이미 계정이 있어요'),
            ),
          ],
        ),
      ),
    );
  }
}
