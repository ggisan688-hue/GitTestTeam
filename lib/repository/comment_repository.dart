import 'dart:typed_data';

import '../core/api_client.dart';
import '../model/friend.dart';

/// 메모 댓글 + 사진 업로드
class CommentRepository {
  CommentRepository(this._api);

  final ApiClient _api;

  List<Comment> _parse(Object? j) => (j as List)
      .map((e) => Comment.fromJson(e as Map<String, dynamic>))
      .toList();

  Future<List<Comment>> list(int memoId) async =>
      (await _api.get<List<Comment>>(
        '/api/memos/$memoId/comments',
        parse: _parse,
      )).data ??
      const [];

  /// 등록 후 그 메모의 댓글 전체 (AI 답글 포함)
  Future<List<Comment>> add(
    int memoId, {
    String? text,
    String? imageUrl,
  }) async =>
      (await _api.post<List<Comment>>(
        '/api/memos/$memoId/comments',
        body: {'text': text, 'imageUrl': imageUrl},
        parse: _parse,
      )).data ??
      const [];

  Future<void> delete(int memoId, int commentId) =>
      _api.delete('/api/memos/$memoId/comments/$commentId');

  /// 사진 업로드 → "/uploads/xxx.jpg"
  Future<String> upload(Uint8List bytes, String filename) async {
    final res = await _api.uploadFile<String>(
      '/api/uploads',
      bytes: bytes,
      filename: filename,
      parse: (j) => (j as Map<String, dynamic>)['url'] as String,
    );
    return res.data!;
  }
}
