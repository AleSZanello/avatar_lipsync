import 'dart:math' as math;
import 'dart:ui';

/// Delaunay triangulation of [points] (Bowyer–Watson).
///
/// Returns triangle vertex indices into [points], three per triangle, wound
/// counter-clockwise. O(n²) is fine here: it runs once per face, on ~500
/// points. Duplicate points are tolerated (they end up in no triangle).
List<int> delaunay(List<Offset> points) {
  if (points.length < 3) return const [];

  var minX = double.infinity;
  var minY = double.infinity;
  var maxX = -double.infinity;
  var maxY = -double.infinity;
  for (final p in points) {
    minX = math.min(minX, p.dx);
    minY = math.min(minY, p.dy);
    maxX = math.max(maxX, p.dx);
    maxY = math.max(maxY, p.dy);
  }
  // Far enough that no hull edge ends up connected to it.
  final span = math.max(maxX - minX, maxY - minY) * 1e4 + 1;
  final midX = (minX + maxX) / 2;
  final midY = (minY + maxY) / 2;

  // The super-triangle's corners sit after the real points.
  final all = [
    ...points,
    Offset(midX - span, midY - span),
    Offset(midX, midY + span),
    Offset(midX + span, midY - span),
  ];
  final n = points.length;
  var triangles = <_Triangle>[_Triangle(n, n + 1, n + 2, all)];

  for (var i = 0; i < n; i++) {
    final p = all[i];
    final bad = <_Triangle>[];
    final keep = <_Triangle>[];
    for (final t in triangles) {
      (t.containsInCircumcircle(p) ? bad : keep).add(t);
    }
    // The hole's boundary: edges that belong to exactly one bad triangle.
    final edgeCount = <int, int>{};
    for (final t in bad) {
      for (final e in t.edges) {
        edgeCount[e] = (edgeCount[e] ?? 0) + 1;
      }
    }
    for (final t in bad) {
      for (final e in t.edges) {
        if (edgeCount[e] != 1) continue;
        final a = e ~/ _stride;
        final b = e % _stride;
        keep.add(_Triangle(a, b, i, all));
      }
    }
    triangles = keep;
  }

  final out = <int>[];
  for (final t in triangles) {
    if (t.a >= n || t.b >= n || t.c >= n) continue;
    out.addAll(t.counterClockwise(all));
  }
  return out;
}

const int _stride = 1 << 20;

class _Triangle {
  _Triangle(this.a, this.b, this.c, List<Offset> pts) {
    final pa = pts[a];
    final pb = pts[b];
    final pc = pts[c];
    final d =
        2 *
        (pa.dx * (pb.dy - pc.dy) +
            pb.dx * (pc.dy - pa.dy) +
            pc.dx * (pa.dy - pb.dy));
    if (d.abs() < 1e-12) {
      // Degenerate (collinear) triangle: an infinite circumcircle.
      _cx = 0;
      _cy = 0;
      _r2 = double.infinity;
      return;
    }
    final a2 = pa.dx * pa.dx + pa.dy * pa.dy;
    final b2 = pb.dx * pb.dx + pb.dy * pb.dy;
    final c2 = pc.dx * pc.dx + pc.dy * pc.dy;
    _cx =
        (a2 * (pb.dy - pc.dy) + b2 * (pc.dy - pa.dy) + c2 * (pa.dy - pb.dy)) /
        d;
    _cy =
        (a2 * (pc.dx - pb.dx) + b2 * (pa.dx - pc.dx) + c2 * (pb.dx - pa.dx)) /
        d;
    final dx = pa.dx - _cx;
    final dy = pa.dy - _cy;
    _r2 = dx * dx + dy * dy;
  }

  final int a;
  final int b;
  final int c;
  late final double _cx;
  late final double _cy;
  late final double _r2;

  bool containsInCircumcircle(Offset p) {
    final dx = p.dx - _cx;
    final dy = p.dy - _cy;
    return dx * dx + dy * dy <= _r2 * (1 + 1e-12);
  }

  Iterable<int> get edges sync* {
    yield _edge(a, b);
    yield _edge(b, c);
    yield _edge(c, a);
  }

  static int _edge(int i, int j) => i < j ? i * _stride + j : j * _stride + i;

  List<int> counterClockwise(List<Offset> pts) {
    final pa = pts[a];
    final pb = pts[b];
    final pc = pts[c];
    final cross =
        (pb.dx - pa.dx) * (pc.dy - pa.dy) - (pb.dy - pa.dy) * (pc.dx - pa.dx);
    return cross >= 0 ? [a, b, c] : [a, c, b];
  }
}
