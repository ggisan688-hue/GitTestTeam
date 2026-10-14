
import 'package:flutter/material.dart';
import '../../utils/persona_parser.dart';

class PersonaDetailDialog extends StatelessWidget {
  final String persona;

  const PersonaDetailDialog({
    super.key,
    required this.persona,
  });

  @override
  Widget build(BuildContext context) {
    final parser = PersonaParser.parse(persona);

    return AlertDialog(
      title: const Text('AI 친구 상세 보기'),
      content: SizedBox(
        width: 550,
        height: 500,
        child: parser.sections.isEmpty
            ? SingleChildScrollView(
          child: SelectableText(
            persona.trim().isEmpty
                ? '표시할 페르소나 내용이 없습니다.'
                : persona,
          ),
        )
            : ListView.separated(
          itemCount: parser.sections.length,
          separatorBuilder: (_, _) =>
          const SizedBox(height: 20),
          itemBuilder: (context, index) {
            final section = parser.sections[index];

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  section.title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Colors.black26,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    section.content.isEmpty
                        ? '내용이 없습니다.'
                        : section.content,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.6,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('닫기'),
        ),
      ],
    );
  }
}
