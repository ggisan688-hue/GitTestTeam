import 'dart:convert';

import 'package:flutter_app/model/ink.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InkMemo JSON', () {
    test('toJson → fromJson 왕복 시 획/좌표/색이 보존된다', () {
      final memo = InkMemo([
        const InkStroke(lineNo: 3, color: 0xFFB4652A, width: 2.5, points: [InkPoint(0.1, 0.2, 0.5), InkPoint(0.4, 1.2, 0.9)]),
        const InkStroke(lineNo: 4, color: 0xFF2A5AB4, width: 4, points: [InkPoint(0, 0, 0.3)]),
      ]);

      final json = jsonDecode(jsonEncode(memo.toJson())) as Map<String, dynamic>;
      final back = InkMemo.fromJson(3, json)!;

      expect(back.strokes, hasLength(2));
      expect(back.strokes[0].lineNo, 3);
      expect(back.strokes[0].color, 0xFFB4652A);
      expect(back.strokes[0].width, 2.5);
      expect(back.strokes[0].points.map((p) => [p.x, p.y, p.pressure]), [
        [0.1, 0.2, 0.5],
        [0.4, 1.2, 0.9],
      ]);
      expect(back.strokes[1].lineNo, 4);
      expect(back.strokes[1].color, 0xFF2A5AB4);
    });

    test('좌표는 소수 셋째 자리로 반올림된다', () {
      final memo = InkMemo([
        const InkStroke(lineNo: 1, color: 0xFF000000, width: 1, points: [InkPoint(0.123456, 0.987654, 0.5555)]),
      ]);
      final pts = (memo.toJson()['strokes'] as List).first['points'] as List;
      expect(pts.first, [0.123, 0.988, 0.556]);
    });

    test('구형 단일 획 JSON({points:[...]}) 도 읽는다', () {
      final back = InkMemo.fromJson(7, {
        'color': '#b4652a',
        'width': 3,
        'points': [
          [0.1, 0.1],
          [0.2, 0.2, 0.7],
        ],
      })!;
      expect(back.strokes, hasLength(1));
      expect(back.strokes.first.lineNo, 7, reason: 'lineNo 없으면 기본값');
      expect(back.strokes.first.color, 0xFFB4652A, reason: '6자리 hex 는 불투명으로');
      expect(back.strokes.first.points.first.pressure, 0.5, reason: '압력 없으면 0.5');
    });

    test('점이 없거나 잘못된 JSON 이면 null', () {
      expect(InkMemo.fromJson(1, {'strokes': []}), isNull);
      expect(InkMemo.fromJson(1, {'strokes': [{'points': []}]}), isNull);
      expect(InkMemo.fromJson(1, 'garbage'), isNull);
      expect(InkMemo.fromJson(1, null), isNull);
    });
  });
}
