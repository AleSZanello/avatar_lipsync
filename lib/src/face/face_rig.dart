// Private fields cannot be named parameters, so the private constructor
// assigns them from public-named ones.
// ignore_for_file: prefer_initializing_formals

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:avatar_lipsync/src/avatar_motion.dart';
import 'package:avatar_lipsync/src/face/delaunay.dart';
import 'package:avatar_lipsync/src/face/face_landmarks.dart';
import 'package:avatar_lipsync/src/face/rig_overlay.dart';
import 'package:avatar_lipsync/src/lip_sync_analyzer.dart';

/// A photo turned into a deformable mesh, driven by mouth frames and poses.
///
/// Built once per image: the landmarks plus a sparse grid over the rest of
/// the picture are triangulated, and every vertex gets a weight for each
/// control (jaw, upper lip, mouth corners, each eyelid, each brow, each iris).
/// A frame is then a weighted sum of a few displacement vectors per vertex,
/// so posing costs a few thousand multiplications.
///
/// The weights are smooth fields in a face-local frame (origin at the mouth,
/// x along the mouth corners, unit = half the mouth width), so any frontal
/// photo rigs the same way without per-image tuning.
class FaceRig {
  FaceRig._({
    required this.imageSize,
    required this.rest,
    required this.indices,
    required this.faceCenter,
    required this.faceHeight,
    required this.landmarkCount,
    required Offset axisX,
    required Offset axisY,
    required double mouthHalfWidth,
    required double noseToChin,
    required double smile,
    required _Weights weights,
    required List<_EyeRig> eyes,
  }) : _axisX = axisX,
       _axisY = axisY,
       _halfWidth = mouthHalfWidth,
       _noseToChin = noseToChin,
       _smile = smile,
       _w = weights,
       _eyes = eyes,
       _posed = Float32List.fromList(rest),
       _restGap =
           (Offset(
                     rest[FaceMeshIndex.lowerInnerLipMid * 2],
                     rest[FaceMeshIndex.lowerInnerLipMid * 2 + 1],
                   ) -
                   Offset(
                     rest[FaceMeshIndex.upperInnerLipMid * 2],
                     rest[FaceMeshIndex.upperInnerLipMid * 2 + 1],
                   ))
               .dot(axisY),
       _cavity = List.filled(_cavityOrder.length, Offset.zero);

  /// Rigs [landmarks]. Returns `null` when the landmarks are incomplete.
  static FaceRig? build(FaceLandmarks landmarks, {int gridSteps = 14}) {
    if (!landmarks.isComplete) return null;
    final size = landmarks.imageSize;
    final lm = landmarks.points;

    final cornerL = lm[FaceMeshIndex.mouthCornerLeft];
    final cornerR = lm[FaceMeshIndex.mouthCornerRight];
    final mouth =
        (lm[FaceMeshIndex.upperInnerLipMid] +
            lm[FaceMeshIndex.lowerInnerLipMid]) /
        2;
    final across = cornerR - cornerL;
    final halfWidth = across.distance / 2;
    if (halfWidth < 2) return null;
    final ax = across / across.distance;
    final ay = Offset(-ax.dy, ax.dx);

    final points = <Offset>[...lm];
    // A sparse grid elsewhere in the picture lets the neck and cheeks bend
    // smoothly instead of stretching one long triangle to the border.
    final spacing = size.shortestSide / gridSteps;
    for (var gy = 0; gy <= gridSteps; gy++) {
      for (var gx = 0; gx <= gridSteps; gx++) {
        final p = Offset(
          gx * size.width / gridSteps,
          gy * size.height / gridSteps,
        );
        final onBorder =
            gx == 0 || gy == 0 || gx == gridSteps || gy == gridSteps;
        if (!onBorder && _near(p, lm, spacing * 0.6)) continue;
        points.add(p);
      }
    }

    final eyes = [
      _EyeRig.from(
        lm,
        FaceMeshIndex.firstEyeCorners,
        FaceMeshIndex.firstEyeLids,
        FaceMeshIndex.firstIris,
        FaceMeshIndex.firstBrow,
        FaceMeshIndex.firstUpperLid,
        FaceMeshIndex.firstLowerLid,
        ax,
        ay,
      ),
      _EyeRig.from(
        lm,
        FaceMeshIndex.secondEyeCorners,
        FaceMeshIndex.secondEyeLids,
        FaceMeshIndex.secondIris,
        FaceMeshIndex.secondBrow,
        FaceMeshIndex.secondUpperLid,
        FaceMeshIndex.secondLowerLid,
        ax,
        ay,
      ),
    ];

    final chinV = (lm[FaceMeshIndex.chin] - mouth).dot(ay) / halfWidth;
    final lipBottomV =
        (lm[FaceMeshIndex.lowerLipBottom] - mouth).dot(ay) / halfWidth;
    final weights = _Weights(points.length);
    final upperInner = FaceMeshIndex.upperInnerLip.toSet();
    final lowerInner = FaceMeshIndex.lowerInnerLip.toSet();
    final innerCorners = upperInner.intersection(lowerInner);
    final outerCorners = {
      FaceMeshIndex.mouthCornerLeft,
      FaceMeshIndex.mouthCornerRight,
    };
    final top = math.min(eyes[0].center.dy, eyes[1].center.dy);

    for (var i = 0; i < points.length; i++) {
      final d = points[i] - mouth;
      final u = d.dot(ax) / halfWidth;
      final v = d.dot(ay) / halfWidth;
      final au = u.abs();
      final isCorner = innerCorners.contains(i) || outerCorners.contains(i);

      // Jaw: everything under the mouth slit drops, sharply between the lips
      // and smoothly out on the cheeks, fading out below the chin.
      // Toward the corners the split closes: the upper and lower lip edges
      // meet at the corner's own share (0.45), so the lips' seam near the
      // corner never tears open beyond the painted mouth.
      final toCorner = _smoothstep(0.45, 0.95, au);
      double sharp;
      if (isCorner) {
        sharp = 0.45;
      } else if (upperInner.contains(i)) {
        sharp = 0.45 * toCorner;
      } else if (lowerInner.contains(i)) {
        sharp = 1 - 0.55 * toCorner;
      } else {
        // Only right at the lips: a little above or below the seam the
        // split is the plain one again (above stays, below drops), or the
        // whole column up to the eyes would follow the jaw.
        final atLips = math.exp(-math.pow(v / 0.3, 2));
        sharp = v > 0 ? 1 - 0.55 * toCorner * atLips : 0.45 * toCorner * atLips;
      }
      final smooth = _smoothstep(-0.6, 0.9, v);
      // Past the corners the split between "drops with the jaw" and "stays"
      // must be soft: a hard one tears the seam's continuation (or a smile
      // crease) into a dark line on the cheek when the jaw drops.
      final blend = isCorner ? 0.0 : _smoothstep(0.7, 1.05, au);
      final vertical = sharp + (smooth - sharp) * blend;
      final horizontal = 1 - _smoothstep(1.5, 2.9, au);
      final neck = v <= chinV ? 1.0 : 1 - _smoothstep(chinV, chinV + 1.1, v);
      weights.jaw[i] = vertical * horizontal * neck;

      // Upper lip: lifts a little, only right at the lip.
      if (!lowerInner.contains(i) || isCorner) {
        final near = v <= 0.15 || upperInner.contains(i);
        weights.upperLip[i] = near
            ? math.exp(-math.pow(v / 0.55, 2)) *
                  (1 - _smoothstep(0.6, 1.25, au)) *
                  (isCorner ? 0.3 : 1)
            : 0;
      }

      // Lower lip: travels further than the jaw when the lips part wide.
      if (!upperInner.contains(i) || isCorner) {
        final below = v > -0.05 || lowerInner.contains(i);
        final across = 1 - _smoothstep(0.85, 1.25, au);
        final depth = v <= lipBottomV
            ? 1.0
            : 1 - _smoothstep(lipBottomV, lipBottomV + 0.55, v);
        weights.lowerLip[i] = below ? across * depth * (isCorner ? 0.4 : 1) : 0;
      }

      // Lip ring: rounding pushes the lips out a little, all around.
      weights.lipRing[i] = math.exp(-(u * u + v * v * 2.5) / 1.2);

      // Corners: the lips stretch or purse sideways.
      final fall = math.exp(-math.pow(v / 0.6, 2));
      weights.corners[i] = au <= 1
          ? u * fall
          : u.sign * math.exp(-math.pow((au - 1) / 0.6, 2)) * fall;

      // Smile relaxation: full at the corner, fading over ~0.6 half-widths
      // into the lips and ~0.9 out over the cheek, more slowly upward (where
      // the crease runs) than downward.
      final outward = au - 1;
      final across2 = outward >= 0
          ? math.pow(outward / 0.9, 2)
          : math.pow(outward / 0.6, 2);
      final up2 = math.pow(v / (v < 0 ? 0.8 : 0.55), 2);
      weights.relax[i] = math.exp(-(across2 + up2));

      for (var e = 0; e < eyes.length; e++) {
        final eye = eyes[e];
        final (lid, brow) = eye.weightsAt(points[i]);
        weights.blink[e][i] = lid;
        weights.brow[e][i] = brow;
        weights.iris[e][i] = eye.iris.contains(i) ? 1 : 0;
      }

      // Nothing above the eyes or beyond the head moves with the mouth.
      if (points[i].dy < top) {
        weights.jaw[i] = 0;
        weights.upperLip[i] = 0;
        weights.lowerLip[i] = 0;
        weights.lipRing[i] = 0;
        weights.corners[i] = 0;
        weights.relax[i] = 0;
      }
    }

    // The head (face and hair) moves; the background and the shoulders stay
    // where the camera saw them. A soft ellipse around the face, a little
    // wider than tall, fading out over about half a face.
    final faceTop = lm[10];
    final faceHeight = (lm[FaceMeshIndex.chin] - faceTop).distance;
    final faceCenter = (faceTop + lm[FaceMeshIndex.chin]) / 2;
    for (var i = 0; i < points.length; i++) {
      final d = points[i] - faceCenter;
      final r = math.sqrt(
        math.pow(d.dx / (faceHeight * 0.75), 2) +
            math.pow(d.dy / (faceHeight * 0.85), 2),
      );
      weights.head[i] = 1 - _smoothstep(0.75, 1.45, r);
    }

    final rest = Float32List(points.length * 2);
    for (var i = 0; i < points.length; i++) {
      rest[i * 2] = points[i].dx;
      rest[i * 2 + 1] = points[i].dy;
    }
    return FaceRig._(
      imageSize: size,
      rest: rest,
      indices: Uint16List.fromList(delaunay(points)),
      faceCenter: faceCenter,
      faceHeight: faceHeight,
      landmarkCount: lm.length,
      axisX: ax,
      axisY: ay,
      mouthHalfWidth: halfWidth,
      noseToChin: (lm[FaceMeshIndex.chin] - lm[FaceMeshIndex.noseTip]).distance,
      smile: math.max(0, -((cornerL + cornerR) / 2 - mouth).dot(ay)),
      weights: weights,
      eyes: eyes,
    );
  }

  /// How many of the first vertices are the face landmarks (the rest is a
  /// grid over the picture).
  final int landmarkCount;

  /// How strongly each vertex follows [region], 0..1, in vertex order (see
  /// [rest]). The two eyes are combined. [RigRegion.motion] depends on the
  /// pose, so it is all zeros here (see `RigOverlay`). Computed once per
  /// region and shared: do not modify the list.
  Float32List weights(RigRegion region) =>
      _weightCache[region] ??= _computeWeights(region);

  final _weightCache = <RigRegion, Float32List>{};

  Float32List _computeWeights(RigRegion region) {
    Float32List maxOf(List<Float32List> fields) {
      final out = Float32List(vertexCount);
      for (final f in fields) {
        for (var i = 0; i < out.length; i++) {
          out[i] = math.max(out[i], f[i]);
        }
      }
      return out;
    }

    return switch (region) {
      RigRegion.motion => Float32List(vertexCount),
      RigRegion.jaw => maxOf([_w.jaw]),
      RigRegion.lips => maxOf([_w.upperLip, _w.lowerLip, _w.lipRing]),
      RigRegion.corners => maxOf([
        Float32List.fromList([for (final c in _w.corners) c.abs()]),
        _w.relax,
      ]),
      RigRegion.eyelids => maxOf(_w.blink),
      RigRegion.brows => maxOf(_w.brow),
      RigRegion.irises => maxOf(_w.iris),
      RigRegion.head => maxOf([_w.head]),
    };
  }

  /// Size of the rigged image.
  final Size imageSize;

  /// Vertex positions at rest (x, y pairs in image pixels). They are also the
  /// texture coordinates.
  final Float32List rest;

  /// Triangle vertex indices.
  final Uint16List indices;

  /// Middle of the face (forehead to chin), the head's pivot.
  final Offset faceCenter;

  /// Forehead-to-chin distance in pixels.
  final double faceHeight;

  final Offset _axisX;
  final Offset _axisY;
  final double _halfWidth;
  final double _noseToChin;

  /// How far the mouth corners sit above the lip seam in the photo (pixels,
  /// 0 for a neutral or downturned mouth): a smile to relax when the mouth
  /// articulates.
  final double _smile;
  final double _restGap;
  final _Weights _w;
  final List<_EyeRig> _eyes;
  final Float32List _posed;
  final List<Offset> _cavity;

  /// Number of mesh vertices.
  int get vertexCount => rest.length ~/ 2;

  /// The inner-lip outline after the last [pose], in image pixels.
  List<Offset> get mouthOutline => _cavity;

  /// How far apart the lips are after the last [pose], in pixels.
  double get mouthGap => _gap;
  double _gap = 0;

  /// Mouth width after the last [pose], in pixels.
  double get mouthWidth => _mouthWidth;
  double _mouthWidth = 0;

  /// Moves every vertex for [frame] and [pose]; returns the positions (x, y
  /// pairs in image pixels). The list is reused between calls.
  Float32List pose(LipSyncFrame frame, AvatarPose pose) {
    final mouthWidth = _halfWidth * 2;
    final gap = frame.gap.clamp(0.0, 0.6) * mouthWidth;
    final jaw = frame.jaw.clamp(0.0, 0.2) * _noseToChin;
    // The upper lip takes ~28% of the opening, the lower lip the rest: with
    // the jaw, plus its own travel when the lips part wider than it drops.
    final lift = gap * 0.28;
    final lowerExtra = math.max(0, gap * 0.72 - jaw);
    // Pressed lips (m, b, p) squeeze toward the seam.
    final press = frame.press.clamp(0.0, 1.0) * 0.02 * mouthWidth;
    final spread = frame.width * _halfWidth;
    final round = frame.round.clamp(0.0, 1.0);
    final ring = round * 0.02;
    // Measured on photos of one face saying a, e, o, u and m: a smiling
    // mouth's corners relax back toward the seam as it opens, rounds or
    // presses (most for o and u, least for e), and rounding pulls them a
    // little further down as the lips gather.
    final relax =
        (frame.gap.clamp(0.0, 0.6) / 0.4 * 0.7 +
                round +
                frame.press.clamp(0.0, 1.0) * 0.6)
            .clamp(0.0, 1.0);
    final cornerDrop = _smile * relax + round * 0.12 * _halfWidth;
    final blinks = [
      for (final eye in _eyes)
        (pose.blink + pose.gazeY * 0.3).clamp(-0.25, 1.0) * eye.gap,
    ];
    final brows = [for (final eye in _eyes) pose.brow * eye.halfWidth * 0.14];
    final gaze = [
      for (final eye in _eyes)
        _axisX * (pose.gazeX * eye.halfWidth * 0.1) +
            _axisY * (pose.gazeY * eye.halfWidth * 0.06),
    ];
    final mouth = _mouthCentre;
    // The head turns about the neck, a quarter face below the chin.
    final pivot = faceCenter + Offset(0, faceHeight * 0.75);
    final cosR = math.cos(pose.roll);
    final sinR = math.sin(pose.roll);
    final shiftX = pose.dx * faceHeight;
    final shiftY = pose.dy * faceHeight;

    final w = _w;
    for (var i = 0; i < vertexCount; i++) {
      var along =
          jaw * w.jaw[i] +
          lowerExtra * w.lowerLip[i] -
          lift * w.upperLip[i] +
          press * (w.upperLip[i] - w.lowerLip[i]);
      var dx = 0.0;
      var dy = 0.0;
      for (var e = 0; e < _eyes.length; e++) {
        along += blinks[e] * w.blink[e][i] - brows[e] * w.brow[e][i];
        final iris = w.iris[e][i];
        if (iris != 0) {
          dx += gaze[e].dx * iris;
          dy += gaze[e].dy * iris;
        }
      }
      final x = rest[i * 2];
      final y = rest[i * 2 + 1];
      final r = ring * w.lipRing[i];
      if (r != 0) {
        dx += (x - mouth.dx) * r;
        dy += (y - mouth.dy) * r;
      }
      // Faces are not symmetric: one corner moves a little less.
      final c = w.corners[i];
      along += cornerDrop * w.relax[i];
      final side = spread * c * (c > 0 ? 0.92 : 1.0);
      var px = x + _axisY.dx * along + _axisX.dx * side + dx;
      var py = y + _axisY.dy * along + _axisX.dy * side + dy;
      // Head motion about the neck, faded out toward the background.
      final h = w.head[i];
      if (h > 0) {
        final rx = px - pivot.dx;
        final ry = py - pivot.dy;
        final hx = pivot.dx + (rx * cosR - ry * sinR) * pose.scale + shiftX;
        final hy = pivot.dy + (rx * sinR + ry * cosR) * pose.scale + shiftY;
        px += (hx - px) * h;
        py += (hy - py) * h;
      }
      _posed[i * 2] = px;
      _posed[i * 2 + 1] = py;
    }

    for (var k = 0; k < _cavityOrder.length; k++) {
      final i = _cavityOrder[k];
      _cavity[k] = Offset(_posed[i * 2], _posed[i * 2 + 1]);
    }
    // The opening reaches almost to the outer corners, as a real one does:
    // ending it at the inner corners leaves the short seam between them
    // showing as a dark tick beside the open mouth (a "Z" on a smile).
    Offset at(int i) => Offset(_posed[i * 2], _posed[i * 2 + 1]);
    const reach = 0.8;
    final last = FaceMeshIndex.upperInnerLip.length - 1;
    _cavity[0] = Offset.lerp(
      _cavity[0],
      at(FaceMeshIndex.mouthCornerLeft),
      reach,
    )!;
    _cavity[last] = Offset.lerp(
      _cavity[last],
      at(FaceMeshIndex.mouthCornerRight),
      reach,
    )!;
    final upper = _cavity[_upperMidInOutline];
    final lower = _cavity[_lowerMidInOutline];
    _gap = math.max(0, (lower - upper).dot(_axisY) - _restGap);
    _mouthWidth = mouthWidth + spread * 1.92;
    return _posed;
  }

  Offset get _mouthCentre => Offset(
    (rest[FaceMeshIndex.upperInnerLipMid * 2] +
            rest[FaceMeshIndex.lowerInnerLipMid * 2]) /
        2,
    (rest[FaceMeshIndex.upperInnerLipMid * 2 + 1] +
            rest[FaceMeshIndex.lowerInnerLipMid * 2 + 1]) /
        2,
  );

  static final int _upperMidInOutline = _cavityOrder.indexOf(
    FaceMeshIndex.upperInnerLipMid,
  );
  static final int _lowerMidInOutline = _cavityOrder.indexOf(
    FaceMeshIndex.lowerInnerLipMid,
  );

  /// Inner-lip outline order: upper lip left to right, lower lip back.
  static final List<int> _cavityOrder = [
    ...FaceMeshIndex.upperInnerLip,
    ...FaceMeshIndex.lowerInnerLip.reversed
        .skip(1)
        .take(FaceMeshIndex.lowerInnerLip.length - 2),
  ];

  static bool _near(Offset p, List<Offset> lm, double radius) {
    final r2 = radius * radius;
    for (final q in lm) {
      final d = p - q;
      if (d.dx * d.dx + d.dy * d.dy < r2) return true;
    }
    return false;
  }
}

double _smoothstep(double edge0, double edge1, double x) {
  final t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

extension on Offset {
  double dot(Offset other) => dx * other.dx + dy * other.dy;
}

class _Weights {
  _Weights(int n)
    : jaw = Float32List(n),
      upperLip = Float32List(n),
      lowerLip = Float32List(n),
      head = Float32List(n),
      lipRing = Float32List(n),
      corners = Float32List(n),
      relax = Float32List(n),
      blink = [Float32List(n), Float32List(n)],
      brow = [Float32List(n), Float32List(n)],
      iris = [Float32List(n), Float32List(n)];

  final Float32List jaw;
  final Float32List upperLip;
  final Float32List lowerLip;
  final Float32List head;
  final Float32List lipRing;
  final Float32List corners;

  /// Where a smile relaxes: a broad, soft patch around each mouth corner
  /// that carries the smile crease and the cheek with the corner, so they
  /// do not stretch into a line.
  final Float32List relax;
  final List<Float32List> blink;
  final List<Float32List> brow;
  final List<Float32List> iris;
}

class _EyeRig {
  _EyeRig({
    required this.center,
    required this.halfWidth,
    required this.gap,
    required this.lidTop,
    required this.lidBottom,
    required this.iris,
    required this.browTop,
    required this.browBottom,
    required this.browLeft,
    required this.browRight,
    required this.upperEdge,
    required this.lowerEdge,
    required this.axisX,
    required this.axisY,
  });

  factory _EyeRig.from(
    List<Offset> lm,
    (int, int) corners,
    (int, int) lids,
    List<int> iris,
    List<int> brow,
    List<int> upperLid,
    List<int> lowerLid,
    Offset ax,
    Offset ay,
  ) {
    final a = lm[corners.$1];
    final b = lm[corners.$2];
    final center = (a + b) / 2;
    final halfWidth = math.max((b - a).distance / 2, 1);
    final upper = lm[lids.$1];
    final lower = lm[lids.$2];
    final browU = [for (final i in brow) (lm[i] - center).dot(ax) / halfWidth];
    final browV = [for (final i in brow) (lm[i] - center).dot(ay) / halfWidth];
    List<(double, double)> edge(List<int> indices) => [
      for (final i in indices)
        (
          (lm[i] - center).dot(ax) / halfWidth,
          (lm[i] - center).dot(ay) / halfWidth,
        ),
    ]..sort((p, q) => p.$1.compareTo(q.$1));
    return _EyeRig(
      center: center,
      halfWidth: halfWidth.toDouble(),
      gap: math.max(0, (lower - upper).dot(ay)),
      lidTop: (upper - center).dot(ay) / halfWidth,
      lidBottom: math.max((lower - center).dot(ay) / halfWidth, 0.05),
      iris: iris.toSet(),
      browTop: browV.reduce(math.min),
      browBottom: browV.reduce(math.max),
      browLeft: browU.reduce(math.min),
      browRight: browU.reduce(math.max),
      upperEdge: edge(upperLid),
      lowerEdge: edge(lowerLid),
      axisX: ax,
      axisY: ay,
    );
  }

  final Offset center;
  final double halfWidth;
  final double gap;
  final double lidTop;
  final double lidBottom;
  final Set<int> iris;

  /// The brow's extent, in eye half-widths from the eye centre (v grows
  /// downward).
  final double browTop;
  final double browBottom;
  final double browLeft;
  final double browRight;

  /// The lid edges as (u, v) points sorted by u, in eye half-widths.
  final List<(double, double)> upperEdge;
  final List<(double, double)> lowerEdge;
  final Offset axisX;
  final Offset axisY;

  /// (eyelid weight, brow weight) of a vertex at [p].
  ///
  /// Measured on a pair of photos (eyes open and closed): the upper lid
  /// travels the whole opening, the lower lid hardly moves, and the skin
  /// above the lid follows only near its edge (about 20% a quarter of an
  /// eye half-width up, nothing from three quarters up), so the brow stays
  /// put while the eye closes.
  (double, double) weightsAt(Offset p) {
    final d = p - center;
    final u = d.dot(axisX) / halfWidth;
    final v = d.dot(axisY) / halfWidth;

    // Each column of the eye closes on its own: the upper edge travels down
    // to the lower edge right below it (a blink of 1 moves the middle of
    // the lid by the middle's opening, so the weight is the local travel
    // over that). The opening between them squeezes onto the lower lid.
    var lid = 0.0;
    final top = _edgeAt(upperEdge, u);
    final bottom = _edgeAt(lowerEdge, u);
    final mid = lidBottom - lidTop;
    if (top != null && bottom != null && bottom > top && mid > 0) {
      if (v <= top) {
        lid = (bottom - top) / mid * math.exp(-math.pow((top - v) / 0.2, 2));
      } else if (v <= bottom) {
        lid = (bottom - v) / mid;
      }
    }

    // The brow band (from its landmarks) moves whole; the forehead above
    // follows part of the way and the skin below stretches down to the lid
    // crease, which stays.
    var brow = 0.0;
    final crease = browBottom + (lidTop - browBottom) * 0.6;
    if (v < crease) {
      final vertical = v < browTop
          ? math.exp(-math.pow((browTop - v) / 0.7, 2))
          : v <= browBottom
          ? 1.0
          : 1 - _smoothstep(browBottom, crease, v);
      final outside = math.max(browLeft - u, u - browRight);
      final horizontal = outside <= 0 ? 1.0 : 1 - _smoothstep(0, 0.45, outside);
      brow = vertical * horizontal;
    }
    return (lid, brow);
  }

  /// The v of a lid edge at u (linear between its points), or null outside.
  static double? _edgeAt(List<(double, double)> edge, double u) {
    if (u < edge.first.$1 || u > edge.last.$1) return null;
    for (var k = 1; k < edge.length; k++) {
      final (u1, v1) = edge[k];
      if (u <= u1) {
        final (u0, v0) = edge[k - 1];
        final t = u1 == u0 ? 0.0 : (u - u0) / (u1 - u0);
        return v0 + (v1 - v0) * t;
      }
    }
    return edge.last.$2;
  }
}
