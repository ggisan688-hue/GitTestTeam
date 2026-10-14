import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../repository/user_profile_repository.dart';
import 'ridi_rooms.dart';
import 'ridi_store.dart';
import 'ridi_widgets.dart';

/// MY 탭은 RidiStore의 단일 프로필 상태를 구독한다.
class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<RidiStore>();
    final nickname = store.nickname.isEmpty ? '사용자' : store.nickname;
    return Scaffold(
      appBar: AppBar(title: const Text('마이')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: RidiProfileImage(imageUrl: store.profileImageUrl, size: 72),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              nickname,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          if (store.username.isNotEmpty)
            Center(child: Text('@${store.username}')),
          if (store.bio.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(store.bio, textAlign: TextAlign.center),
            ),
          const Divider(height: 40),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('프로필 수정'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const ProfileScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('로그아웃'),
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('로그아웃'),
                  content: const Text('로그아웃하시겠어요?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('취소'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: const Text('로그아웃'),
                    ),
                  ],
                ),
              );
              if (ok == true && context.mounted) {
                await context.read<RidiStore>().logout();
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.person_remove_outlined),
            title: const Text('회원 탈퇴'),
            textColor: Colors.red,
            iconColor: Colors.red,
            onTap: store.username.isEmpty
                ? null
                : () => _deleteAccount(context),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final repository = UserProfileRepository(
      ApiClient(tokenProvider: () => context.read<RidiStore>().accessToken),
    );
    final deleted = await showDialog<bool>(
      context: context,
      builder: (_) => _DeleteAccountDialog(repository: repository),
    );
    if (deleted != true || !context.mounted) return;
    await context.read<RidiStore>().logout();
  }
}

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog({required this.repository});
  final UserProfileRepository repository;
  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _password = TextEditingController();
  bool _deleting = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_deleting) return;
    // Password whitespace is significant: never trim it before verification.
    final password = _password.text;
    if (password.isEmpty) {
      setState(() => _error = '비밀번호를 입력해주세요.');
      return;
    }
    setState(() { _deleting = true; _error = null; });
    try {
      await widget.repository.delete(password);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (exception) {
      if (mounted) setState(() { _deleting = false; _error = exception.message; });
    } catch (_) {
      if (mounted) setState(() {
        _deleting = false;
        _error = '회원 탈퇴를 처리하지 못했습니다. 잠시 후 다시 시도해주세요.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_deleting,
    child: AlertDialog(
      title: const Text('회원 탈퇴'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('탈퇴 후에는 되돌릴 수 없습니다. 계속하려면 현재 비밀번호를 입력해주세요.'),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          enabled: !_deleting,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(labelText: '비밀번호'),
          onSubmitted: (_) => _submit(),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
      ]),
      actions: [
        TextButton(onPressed: _deleting ? null : () => Navigator.of(context).pop(false),
            child: const Text('취소')),
        FilledButton(
          onPressed: _deleting ? null : _submit,
          child: _deleting
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('탈퇴하기'),
        ),
      ],
    ),
  );
}
