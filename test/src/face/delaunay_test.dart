import 'dart:math' as math;

import 'package:avatar_lipsync/src/face/delaunay.dart';
import 'package:flutter_test/flutter_test.dart';

double _area(List<Offset> p, List<int> t, int k) {
  final a = p[t[k]];
  final b = p[t[k + 1]];
  final c = p[t[k + 2]];
  return ((b.dx - a.dx) * (c.dy - a.dy) - (b.dy - a.dy) * (c.dx - a.dx)) / 2;
}

void main() {
  group('delaunay', () {
    test('returns nothing for fewer than three points', () {
      expect(delaunay(const [Offset.zero, Offset(1, 1)]), isEmpty);
    });

    test('splits a square into two counter-clockwise triangles', () {
      const square = [Offset.zero, Offset(1, 0), Offset(1, 1), Offset(0, 1)];
      final triangles = delaunay(square);
      expect(triangles, hasLength(6));
      for (var k = 0; k < triangles.length; k += 3) {
        expect(_area(square, triangles, k), greaterThan(0));
      }
    });

    test('covers the convex hull of random points exactly', () {
      final random = math.Random(3);
      final points = [
        Offset.zero,
        const Offset(100, 0),
        const Offset(100, 100),
        const Offset(0, 100),
        for (var i = 0; i < 200; i++)
          Offset(random.nextDouble() * 100, random.nextDouble() * 100),
      ];
      final triangles = delaunay(points);
      var area = 0.0;
      for (var k = 0; k < triangles.length; k += 3) {
        area += _area(points, triangles, k);
      }
      expect(area, closeTo(100 * 100, 1e-6));
    });

    test('tolerates duplicate and collinear points', () {
      const points = [
        Offset.zero,
        Offset(1, 0),
        Offset(2, 0),
        Offset(1, 0),
        Offset(1, 1),
      ];
      final triangles = delaunay(points);
      expect(triangles.length % 3, 0);
      expect(triangles, isNotEmpty);
    });
  });
}
