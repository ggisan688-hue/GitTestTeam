import 'dart:ui';

/// 펜 획 하나. 좌표는 앵커 문장 박스 기준 정규화 값 (x: 0~1 = 박스 너비, y: 0~1 = 박스 높이, 넘어갈 수 있음)
class InkStroke {
  const InkStroke({
    required this.lineNo,
    required this.color,
    required this.width,
    required this.points,
  });

  final int lineNo;
  final int color; // ARGB
  final double width;
  final List<InkPoint> points;

  Map<String, dynamic> toJson() => {
    'lineNo': lineNo,
    'color': '#${color.toRadixString(16).padLeft(8, '0')}',
    'width': width,
    'points': [
      for (final p in points) [_r(p.x), _r(p.y), _r(p.pressure)],
    ],
  };

  static InkStroke? fromJson(int defaultLineNo, Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final raw = json['points'];
    if (raw is! List || raw.isEmpty) return null;
    final pts = <InkPoint>[];
    for (final e in raw) {
      if (e is List && e.length >= 2) {
        pts.add(
          InkPoint(
            (e[0] as num).toDouble(),
            (e[1] as num).toDouble(),
            e.length > 2 ? (e[2] as num).toDouble() : 0.5,
          ),
        );
      }
    }
    final c = json['color'];
    int color = 0xFFB4652A;
    if (c is String && c.startsWith('#')) {
      final hex = c.substring(1);
      color =
          int.tryParse(hex.length == 6 ? 'FF$hex' : hex, radix: 16) ?? color;
    }
    return InkStroke(
      lineNo: (json['lineNo'] as num?)?.toInt() ?? defaultLineNo,
      color: color,
      width: (json['width'] as num?)?.toDouble() ?? 2.5,
      points: pts,
    );
  }

  static double _r(double v) => (v * 1000).round() / 1000;
}

/// 손글씨 메모 = 한 번의 펜 세션에 그린 획 묶음 (댓글이 달리는 단위)
class InkMemo {
  const InkMemo(this.strokes);

  final List<InkStroke> strokes;

  Map<String, dynamic> toJson() => {
    'strokes': [for (final s in strokes) s.toJson()],
  };

  /// 서버 JSON: {strokes:[...]} (신형) 또는 {points:[...]} (구형 1획)
  static InkMemo? fromJson(int lineNo, Object? json) {
    if (json is! Map<String, dynamic>) return null;
    if (json['strokes'] is List) {
      final list = (json['strokes'] as List)
          .map((e) => InkStroke.fromJson(lineNo, e))
          .whereType<InkStroke>()
          .toList();
      return list.isEmpty ? null : InkMemo(list);
    }
    final single = InkStroke.fromJson(lineNo, json);
    return single == null ? null : InkMemo([single]);
  }
}

class InkPoint {
  const InkPoint(this.x, this.y, this.pressure);

  final double x;
  final double y;
  final double pressure;

  Offset get offset => Offset(x, y);
}
