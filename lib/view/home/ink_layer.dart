import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../model/ink.dart';
import '../../model/memo.dart';

/// 문장별 박스 위치 (본문 콘텐츠 좌표계). 각 문장 위젯이 레이아웃 후 보고한다.
class LineRects extends ChangeNotifier {
  final Map<int, Rect> _rects = {};

  Rect? operator [](int lineNo) => _rects[lineNo];
  Map<int, Rect> get all => _rects;

  void report(int lineNo, Rect rect) {
    if (_rects[lineNo] == rect) return;
    _rects[lineNo] = rect;
    notifyListeners();
  }

  /// 획의 중심 y 에 가장 가까운 문장
  int? nearest(Offset p) {
    int? best;
    double bestD = double.infinity;
    for (final e in _rects.entries) {
      final r = e.value;
      final d = p.dy < r.top ? r.top - p.dy : p.dy > r.bottom ? p.dy - r.bottom : 0.0;
      if (d < bestD) {
        bestD = d;
        best = e.key;
      }
    }
    return best;
  }

  /// 콘텐츠 좌표 → 문장 박스 기준 정규화
  InkPoint normalize(int lineNo, Offset p, double pressure) {
    final r = _rects[lineNo]!;
    return InkPoint((p.dx - r.left) / r.width, (p.dy - r.top) / r.height, pressure);
  }

  /// 정규화 → 콘텐츠 좌표. 문장 박스가 아직 없으면 null
  Offset? denormalize(int lineNo, InkPoint p) {
    final r = _rects[lineNo];
    if (r == null) return null;
    return Offset(r.left + p.x * r.width, r.top + p.y * r.height);
  }
}

/// 자식(문장)의 위치를 [ancestor] 기준으로 재서 [rects] 에 보고
class LineRectReporter extends StatefulWidget {
  const LineRectReporter({super.key, required this.lineNo, required this.rects, required this.ancestorKey, required this.child});

  final int lineNo;
  final LineRects rects;
  final GlobalKey ancestorKey;
  final Widget child;

  @override
  State<LineRectReporter> createState() => _LineRectReporterState();
}

class _LineRectReporterState extends State<LineRectReporter> {
  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _report());
    return widget.child;
  }

  void _report() {
    if (!mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    final ancestor = widget.ancestorKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || ancestor == null || !box.hasSize || !ancestor.hasSize) return;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: ancestor);
    widget.rects.report(widget.lineNo, topLeft & box.size);
  }
}

/// 본문 위에 얹는 드로잉 레이어. 저장된 획을 그리고, 펜 입력을 받아 새 획을 만든다.
class InkCanvas extends StatefulWidget {
  const InkCanvas({
    super.key,
    required this.rects,
    required this.strokes,
    required this.session,
    required this.penMode,
    required this.eraser,
    required this.color,
    required this.width,
    required this.onStroke,
    required this.onErase,
  });

  final LineRects rects;
  final List<Memo> strokes; // 저장된 ink 메모 (mine / shared), 각각 획 여러 개
  final List<InkStroke> session; // 아직 저장 안 된 이번 세션 획
  final bool penMode; // true: 손가락·마우스도 그림. false: 스타일러스만
  final bool eraser;
  final int color;
  final double width;
  final ValueChanged<InkStroke> onStroke;
  final ValueChanged<int> onErase; // memoId

  @override
  State<InkCanvas> createState() => _InkCanvasState();
}

class _InkCanvasState extends State<InkCanvas> {
  static const _tapSlop = 8.0; // 이 거리 안이면 획이 아니라 탭

  final List<Offset> _live = [];
  final List<double> _pressure = [];
  int? _pointer;
  Offset? _downAt;

  bool _accepts(PointerEvent e) => e.kind == PointerDeviceKind.stylus || widget.penMode;

  void _down(PointerDownEvent e) {
    if (!_accepts(e) || _pointer != null) return;
    if (widget.eraser) {
      _eraseAt(e.localPosition);
      return;
    }
    _pointer = e.pointer;
    _downAt = e.localPosition;
    _live
      ..clear()
      ..add(e.localPosition);
    _pressure
      ..clear()
      ..add(_p(e));
    setState(() {});
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    if (widget.eraser) {
      _eraseAt(e.localPosition);
      return;
    }
    _live.add(e.localPosition);
    _pressure.add(_p(e));
    setState(() {});
  }

  void _up(PointerEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    final moved = _downAt == null ? 0.0 : _live.fold(0.0, (m, p) => (p - _downAt!).distance > m ? (p - _downAt!).distance : m);
    // 거의 안 움직였으면 획이 아니라 탭. 탭은 이 레이어가 처리하지 않는다 —
    // 레이어가 히트를 통과시키므로(아래 _InkPainter.hitTest) 문장 InkWell 이 받는다. 여기서도 처리하면 두 번 선택돼 토글로 풀린다.
    if (moved > _tapSlop && _live.length >= 2) {
      _commit();
    }
    _downAt = null;
    _live.clear();
    _pressure.clear();
    setState(() {});
  }

  double _p(PointerEvent e) {
    // 마우스/에뮬레이터는 pressure 가 0 또는 1 로 고정 → 중간값
    final p = e.pressure;
    return (p <= 0 || p >= 1) ? 0.5 : p;
  }

  /// 획 → 가장 가까운 문장에 앵커해서 정규화 후 저장 요청
  void _commit() {
    final center = _live.fold(Offset.zero, (a, b) => a + b) / _live.length.toDouble();
    final lineNo = widget.rects.nearest(center);
    if (lineNo == null) return;
    final pts = _simplify(_live, 1.2);
    final norm = <InkPoint>[];
    for (var i = 0; i < pts.length; i++) {
      final idx = _live.indexOf(pts[i]);
      norm.add(widget.rects.normalize(lineNo, pts[i], _pressure[idx < 0 ? 0 : idx]));
    }
    widget.onStroke(InkStroke(lineNo: lineNo, color: widget.color, width: widget.width, points: norm));
  }

  /// 지우개: 가장 가까운 내 획 (거리 12px 이내)
  void _eraseAt(Offset p) {
    int? hit;
    double best = 12;
    for (final m in widget.strokes) {
      if (!m.mine || m.ink == null) continue;
      for (final st in m.ink!.strokes) {
        for (final pt in st.points) {
          final o = widget.rects.denormalize(st.lineNo, pt);
          if (o == null) continue;
          final d = (o - p).distance;
          if (d < best) {
            best = d;
            hit = m.id;
          }
        }
      }
    }
    if (hit != null) widget.onErase(hit);
  }

  /// Douglas-Peucker 간략화
  static List<Offset> _simplify(List<Offset> pts, double eps) {
    if (pts.length < 3) return List.of(pts);
    var maxD = 0.0;
    var idx = 0;
    final a = pts.first, b = pts.last;
    for (var i = 1; i < pts.length - 1; i++) {
      final d = _distToSeg(pts[i], a, b);
      if (d > maxD) {
        maxD = d;
        idx = i;
      }
    }
    if (maxD > eps) {
      final left = _simplify(pts.sublist(0, idx + 1), eps);
      final right = _simplify(pts.sublist(idx), eps);
      return [...left.sublist(0, left.length - 1), ...right];
    }
    return [a, b];
  }

  static double _distToSeg(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (len2 == 0) return (p - a).distance;
    final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2).clamp(0.0, 1.0);
    return (p - (a + ab * t)).distance;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _up,
      onPointerCancel: _up,
      child: AnimatedBuilder(
        animation: widget.rects,
        builder: (_, _) => CustomPaint(
          painter: _InkPainter(
            rects: widget.rects,
            strokes: widget.strokes,
            session: widget.session,
            live: _live,
            livePressure: _pressure,
            liveColor: Color(widget.color),
            liveWidth: widget.width,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _InkPainter extends CustomPainter {
  _InkPainter({required this.rects, required this.strokes, required this.session, required this.live, required this.livePressure, required this.liveColor, required this.liveWidth});

  final LineRects rects;
  final List<Memo> strokes;
  final List<InkStroke> session;
  final List<Offset> live;
  final List<double> livePressure;
  final Color liveColor;
  final double liveWidth;

  @override
  void paint(Canvas canvas, Size size) {
    for (final m in strokes) {
      final ink = m.ink;
      if (ink == null) continue;
      for (final st in ink.strokes) {
        _drawNormalized(canvas, st, m.mine ? 0.95 : 0.55);
      }
    }
    for (final st in session) {
      _drawNormalized(canvas, st, 0.95);
    }
    if (live.length >= 2) _drawStroke(canvas, live, livePressure, liveColor, liveWidth);
  }

  void _drawNormalized(Canvas canvas, InkStroke st, double alpha) {
    final pts = <Offset>[];
    final pr = <double>[];
    for (final p in st.points) {
      final o = rects.denormalize(st.lineNo, p);
      if (o == null) return;
      pts.add(o);
      pr.add(p.pressure);
    }
    if (pts.length < 2) return;
    _drawStroke(canvas, pts, pr, Color(st.color).withValues(alpha: alpha), st.width);
  }

  /// 중점 기준 2차 베지어로 부드럽게, 필압으로 굵기 변화
  void _drawStroke(Canvas canvas, List<Offset> pts, List<double> pr, Color color, double width) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (var i = 0; i < pts.length - 1; i++) {
      final p = i < pr.length ? pr[i] : 0.5;
      paint.strokeWidth = width * (0.6 + p * 0.9);
      final path = Path()..moveTo(pts[i].dx, pts[i].dy);
      if (i + 2 < pts.length) {
        final mid = (pts[i + 1] + pts[i + 2]) / 2;
        path.quadraticBezierTo(pts[i + 1].dx, pts[i + 1].dy, mid.dx, mid.dy);
        canvas.drawPath(path, paint);
        i++; // 두 점씩 소비
      } else {
        path.lineTo(pts[i + 1].dx, pts[i + 1].dy);
        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_InkPainter old) => true;

  /// 기본값(null → 맞음)이면 이 레이어가 모든 터치를 삼켜 아래 문장 InkWell 이 탭을 못 받는다.
  /// 그리기는 Listener(translucent)가 포인터를 직접 받으므로 히트 테스트는 항상 통과시킨다.
  @override
  bool hitTest(Offset position) => false;
}

/// 색상 프리셋
const inkColors = [0xFFB4652A, 0xFF2F6F9F, 0xFF3B8A4E, 0xFF1C1B1A];

double inkWidthFor(int step) => [1.8, 2.8, 4.2][step.clamp(0, 2)];

int inkStepFor(double width) => width <= 2.0 ? 0 : width <= 3.2 ? 1 : 2;
