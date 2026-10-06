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
                : () => _deleteAccount(context, store.username),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteAccount(BuildContext context, String username) async {
    final confirmation = TextEditingController();
    final repository = UserProfileRepository(
      ApiClient(tokenProvider: () => context.read<RidiStore>().accessToken),
    );
    try {
      final deleted = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          var deleting = false;
          String? error;
          return StatefulBuilder(
            builder: (dialogContext, setDialogState) => PopScope(
              canPop: !deleting,
              child: AlertDialog(
                title: const Text('회원 탈퇴'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('탈퇴 후에는 되돌릴 수 없습니다. 계속하려면 아이디를 입력해주세요.'),
                    TextField(
                      controller: confirmation,
                      enabled: !deleting,
                      decoration: InputDecoration(labelText: username),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(dialogContext).colorScheme.error,
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
                    onPressed: deleting
                        ? null
                        : () async {
                            final value = confirmation.text.trim();
                            if (value.isEmpty) {
                              setDialogState(() => error = '아이디를 입력해주세요.');
                              return;
                            }
                            setDialogState(() {
                              deleting = true;
                              error = null;
                            });
                            try {
                              await repository.delete(value);
                              if (dialogContext.mounted) {
                                Navigator.of(dialogContext).pop(true);
                              }
                            } on ApiException catch (exception) {
                              if (dialogContext.mounted) {
                                setDialogState(() {
                                  deleting = false;
                                  error = exception.message;
                                });
                              }
                            } catch (_) {
                              if (dialogContext.mounted) {
                                setDialogState(() {
                                  deleting = false;
                                  error = '회원 탈퇴를 처리하지 못했습니다. 잠시 후 다시 시도해주세요.';
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
                        : const Text('탈퇴하기'),
                  ),
                ],
              ),
            ),
          );
        },
      );
      if (deleted != true || !context.mounted) return;
      // RidiGate observes loggedIn. Its replacement of RidiShell removes every
      // authenticated tab from the tree, so there is no protected route to pop back to.
      await context.read<RidiStore>().logout();
    } finally {
      confirmation.dispose();
    }
  }
}
