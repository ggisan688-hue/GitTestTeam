import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../model/memo.dart';
import '../../repository/comment_repository.dart';
import '../../theme/app_theme.dart';
import '../../viewmodel/comments_viewmodel.dart';
import '../../viewmodel/reading_viewmodel.dart';
import '../../widgets/buttons.dart';
import '../../widgets/screen_tag.dart';

/// 메모의 댓글 스레드 (하단 시트). 사진 첨부 가능. AI 메모면 캐릭터가 답글을 남긴다.
Future<void> showCommentSheet(BuildContext context, Memo memo) async {
  final repo = context.read<CommentRepository>();
  final reading = context.read<ReadingViewModel>();
  final vm = CommentsViewModel(repo, memo.id, aiMemo: memo.ai)..load();
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.panel,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppTheme.radiusCard),
      ),
    ),
    builder: (_) => ChangeNotifierProvider.value(
      value: vm,
      child: _CommentSheet(memo: memo),
    ),
  );
  reading.updateCommentCount(memo.id, vm.comments.length);
  vm.dispose();
}

class _CommentSheet extends StatefulWidget {
  const _CommentSheet({required this.memo});

  final Memo memo;

  @override
  State<_CommentSheet> createState() => _CommentSheetState();
}

class _CommentSheetState extends State<_CommentSheet> {
  final _text = TextEditingController();
  final _picker = ImagePicker();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    final x = await _picker.pickImage(
      source: source,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (x == null || !mounted) return;
    context.read<CommentsViewModel>().attachImage(
      await x.readAsBytes(),
      x.name,
    );
  }

  Future<void> _send() async {
    final vm = context.read<CommentsViewModel>();
    final ok = await vm.send(_text.text);
    if (!mounted) return;
    if (ok) {
      _text.clear();
    } else {
      showToast(context, vm.errorMessage ?? '등록 실패');
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<CommentsViewModel>();
    final api = context.read<ApiClient>();
    final memo = widget.memo;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return ScreenTag(
      'S43',
      alignment: Alignment.topLeft,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.72,
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(
                  top: AppSpace.md,
                  bottom: AppSpace.sm,
                ),
                decoration: BoxDecoration(
                  color: AppColors.line,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // ----- 원본 메모 -----
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.lg,
                  AppSpace.xs,
                  AppSpace.lg,
                  AppSpace.md,
                ),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.md,
                    vertical: AppSpace.md,
                  ),
                  decoration: BoxDecoration(
                    color: memo.ai ? AppColors.accentSoft : AppColors.memoBg,
                    borderRadius: BorderRadius.circular(AppTheme.radiusControl),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${memo.ai ? "🤖 " : ""}${memo.author} · 문장 ${memo.lineNo}',
                        style: AppText.caption.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: AppSpace.xs),
                      Text(
                        memo.isInk ? '(손글씨 메모)' : memo.text,
                        style: AppText.label.copyWith(
                          fontWeight: FontWeight.w400,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              // ----- 댓글 목록 -----
              Expanded(
                child: vm.isLoading && vm.comments.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : vm.comments.isEmpty
                    ? const Center(
                        child: Text('첫 댓글을 남겨보세요', style: AppText.labelMuted),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpace.lg,
                          AppSpace.md,
                          AppSpace.lg,
                          AppSpace.md,
                        ),
                        itemCount: vm.comments.length,
                        itemBuilder: (_, i) {
                          final c = vm.comments[i];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: AppSpace.md),
                            child: Column(
                              crossAxisAlignment: c.mine
                                  ? CrossAxisAlignment.end
                                  : CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${c.ai ? "🤖 " : ""}${c.author}',
                                  style: AppText.caption,
                                ),
                                const SizedBox(height: AppSpace.xs),
                                Container(
                                  constraints: const BoxConstraints(
                                    maxWidth: 420,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpace.md,
                                    vertical: AppSpace.sm + 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: c.mine
                                        ? AppColors.accent
                                        : c.ai
                                        ? AppColors.accentSoft
                                        : AppColors.codeBg,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (c.imageUrl != null)
                                        Padding(
                                          padding: EdgeInsets.only(
                                            bottom: c.text.isEmpty ? 0 : 6,
                                          ),
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            child: Image.network(
                                              api.absolute(c.imageUrl!),
                                              width: 240,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, _, _) =>
                                                  const Text(
                                                    '사진을 불러올 수 없어요',
                                                    style: AppText.micro,
                                                  ),
                                            ),
                                          ),
                                        ),
                                      if (c.text.isNotEmpty)
                                        Text(
                                          c.text,
                                          style: AppText.label.copyWith(
                                            fontWeight: FontWeight.w400,
                                            height: 1.5,
                                            color: c.mine
                                                ? Colors.white
                                                : AppColors.ink,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                if (c.mine)
                                  TextButton(
                                    onPressed: () => vm.delete(c.id),
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: AppSpace.sm,
                                      ),
                                      minimumSize: const Size(0, 36),
                                      foregroundColor: AppColors.muted,
                                    ),
                                    child: const Text(
                                      '삭제',
                                      style: AppText.caption,
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              // ----- 입력 -----
              if ((vm.isSending || vm.awaitingReply) && memo.ai)
                const Padding(
                  padding: EdgeInsets.only(bottom: AppSpace.xs),
                  child: Text('캐릭터가 답글을 쓰는 중…', style: AppText.caption),
                ),
              if (vm.pendingImage != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpace.lg,
                    0,
                    AppSpace.lg,
                    AppSpace.sm,
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.memory(
                          vm.pendingImage!,
                          width: 56,
                          height: 56,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(width: AppSpace.sm),
                      const Expanded(
                        child: Text('사진 첨부됨', style: AppText.caption),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: vm.clearImage,
                      ),
                    ],
                  ),
                ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpace.md,
                    AppSpace.xs,
                    AppSpace.sm,
                    AppSpace.md,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: '갤러리',
                        icon: const Icon(
                          Icons.photo_outlined,
                          color: AppColors.muted,
                        ),
                        onPressed: vm.isSending
                            ? null
                            : () => _pick(ImageSource.gallery),
                      ),
                      IconButton(
                        tooltip: '카메라',
                        icon: const Icon(
                          Icons.photo_camera_outlined,
                          color: AppColors.muted,
                        ),
                        onPressed: vm.isSending
                            ? null
                            : () => _pick(ImageSource.camera),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _text,
                          enabled: !vm.isSending,
                          onSubmitted: (_) => _send(),
                          decoration: const InputDecoration(
                            hintText: '이 메모에 대한 생각을 남겨보세요',
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpace.sm),
                      vm.isSending
                          ? const Padding(
                              padding: EdgeInsets.all(10),
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : IconButton(
                              icon: const Icon(
                                Icons.send,
                                color: AppColors.accent,
                              ),
                              onPressed: _send,
                            ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
