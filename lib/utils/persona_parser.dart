
class PersonaSection {
  final String title;
  String content;

  PersonaSection({
    required this.title,
    required this.content,
  });
}

class PersonaParser {
  final String header;
  final List<PersonaSection> sections;

  PersonaParser({
    required this.header,
    required this.sections,
  });

  // 저장된 페르소나를 ## 제목 기준으로 분리
  factory PersonaParser.parse(String persona) {
    final text = persona.replaceAll('\r\n', '\n');

    final regex = RegExp(
      r'^##[ \t]+(.+?)[ \t]*$',
      multiLine: true,
    );

    final matches = regex.allMatches(text).toList();
    final sections = <PersonaSection>[];

    if (matches.isEmpty) {
      return PersonaParser(
        header: text,
        sections: sections,
      );
    }

    for (var i = 0; i < matches.length; i++) {
      final match = matches[i];

      final start = match.end;
      final end = i + 1 < matches.length
          ? matches[i + 1].start
          : text.length;

      sections.add(
        PersonaSection(
          title: match.group(1)!.trim(),
          content: text.substring(start, end).trim(),
        ),
      );
    }

    return PersonaParser(
      header: text.substring(0, matches.first.start).trim(),
      sections: sections,
    );
  }

  // 수정한 내용을 다시 하나의 문자열로 합치기
  String toPersonaText() {
    final result = <String>[];

    if (header.isNotEmpty) {
      result.add(header);
    }

    for (final section in sections) {
      result.add(
        '## ${section.title}\n\n${section.content.trim()}',
      );
    }

    return result.join('\n\n');
  }
}
