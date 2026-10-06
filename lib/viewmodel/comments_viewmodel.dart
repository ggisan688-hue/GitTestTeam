import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../model/friend.dart';
import '../repository/comment_repository.dart';

/// 메모 하나의 댓글 스레드 (댓글 시트마다 새로 만듦)
class CommentsViewModel extends ChangeNotifier {
  CommentsViewModel(this._repo, this.memoId, {this.aiMemo = false});

  final CommentRepository _repo;
  final int memoId;
  final bool aiMemo; // AI 캐릭터 메모면 댓글 뒤 답글을 폴링으로 받는다

  List<Comment> comments = [];
  bool isLoading = false;
  bool isSending = false;
  bool awaitingReply = false; // AI 답글 기다리는 중
  String? errorMessage;
  Timer? _replyTimer;
  int _replyPolls = 0;
  Uint8List? pendingImage; // 첨부 대기 중인 사진
  String? pendingImageName;

  Future<void> load() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      comments = await _repo.list(memoId);
    } on ApiException catch (e) {
      errorMessage = e.message;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  void attachImage(Uint8List bytes, String name) {
    pendingImage = bytes;
    pendingImageName = name;
    notifyListeners();
  }

  void clearImage() {
    pendingImage = null;
    pendingImageName = null;
    notifyListeners();
  }

  /// 사진이 있으면 먼저 업로드 → 댓글 등록. AI 메모면 답글은 서버가 비동기로 달아 주므로 잠시 폴링
  Future<bool> send(String text) async {
    if (text.trim().isEmpty && pendingImage == null) return false;
    isSending = true;
    errorMessage = null;
    notifyListeners();
    try {
      String? url;
      if (pendingImage != null) {
        url = await _repo.upload(
          pendingImage!,
          pendingImageName ?? 'photo.jpg',
        );
      }
      final hasText = text.trim().isNotEmpty;
      comments = await _repo.add(
        memoId,
        text: hasText ? text.trim() : null,
        imageUrl: url,
      );
      clearImage();
      if (aiMemo && hasText) _startReplyPolling(comments.length);
      return true;
    } on ApiException catch (e) {
      errorMessage = e.message;
      return false;
    } finally {
      isSending = false;
      notifyListeners();
    }
  }

  // AI 답글이 붙을 때까지 3초 간격으로 최대 5번 다시 읽는다
  void _startReplyPolling(int countBefore) {
    _replyTimer?.cancel();
    _replyPolls = 0;
    awaitingReply = true;
    _replyTimer = Timer.periodic(const Duration(seconds: 3), (t) async {
      _replyPolls++;
      try {
        final latest = await _repo.list(memoId);
        if (latest.length > countBefore || _replyPolls >= 5) {
          comments = latest;
          _stopReplyPolling();
        }
      } on ApiException {
        _stopReplyPolling();
      }
      notifyListeners();
    });
  }

  void _stopReplyPolling() {
    _replyTimer?.cancel();
    _replyTimer = null;
    awaitingReply = false;
  }

  @override
  void dispose() {
    _replyTimer?.cancel();
    super.dispose();
  }

  Future<void> delete(int commentId) async {
    try {
      await _repo.delete(memoId, commentId);
      comments = comments.where((c) => c.id != commentId).toList();
    } on ApiException catch (e) {
      errorMessage = e.message;
    }
    notifyListeners();
  }
}
