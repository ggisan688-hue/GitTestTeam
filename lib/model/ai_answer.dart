/// POST /api/ai/ask 응답 (Spring 의 AiAskResponse 와 동일)
class AiSource {
  const AiSource({
    required this.id,
    required this.content,
    required this.score,
  });

  final int id;
  final String content;
  final double score;

  factory AiSource.fromJson(Map<String, dynamic> json) => AiSource(
    id: json['id'] as int,
    content: json['content'] as String,
    score: (json['score'] as num).toDouble(),
  );
}

class AiAnswer {
  const AiAnswer({required this.answer, required this.sources});

  final String answer;
  final List<AiSource> sources;

  factory AiAnswer.fromJson(Map<String, dynamic> json) => AiAnswer(
    answer: _stripMarkdown(json['answer'] as String),
    sources: (json['sources'] as List<dynamic>? ?? [])
        .map((e) => AiSource.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

/// 모델이 섞어 보내는 굵게(**)·제목(#) 기호만 걷어낸다 (화면은 일반 텍스트로 표시)
String _stripMarkdown(String s) => s
    .replaceAll('**', '')
    .replaceAll(RegExp(r'^#{1,6}\s*', multiLine: true), '')
    .trim();
