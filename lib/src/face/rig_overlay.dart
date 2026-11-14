import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:avatar_lipsync/src/face/face_landmarks.dart';
import 'package:avatar_lipsync/src/face/face_rig.dart';
import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/painting.dart';

/// What a [RigOverlay] heat map shows.
enum RigRegion {
  /// How far each point of the photo moves right now (live).
  motion,

  /// Where the jaw pulls the face when the mouth opens.
  jaw,

  /// The lips: upper and lower lip bodies and the ring around them.
  lips,

  /// The mouth corners (spreading and rounding).
  corners,

  /// The eyelids (blinks).
  eyelids,

  /// The brows (raises).
  brows,

  /// The irises (gaze).
  irises,

  /// What moves with the head (nods and sway); the background does not.
  head,
}

/// Draws how the photo rig works on top of a `PhotoLipSyncAvatar`: the
/// triangle mesh, the face landmarks and a heat map.
///
/// Meant for demos, debugging and tuning: it shows which points of the
/// photo the mouth, eyes and head move, and how much.
@immutable
class RigOverlay {
  /// Creates an overlay. Everything is off by default.
  const RigOverlay({
    this.mesh = false,
    this.landmarks = false,
    this.heat,
    this.heatOpacity = 0.6,
  });

  /// No overlay.
  static const none = RigOverlay();

  /// Draws the triangle mesh the photo is deformed with.
  final bool mesh;

  /// Draws the 478 face landmarks MediaPipe found.
  final bool landmarks;

  /// Paints a heat map of this region, or none.
  final RigRegion? heat;

  /// Opacity of the hottest part of the heat map, 0..1.
  final double heatOpacity;

  /// Whether nothing is drawn.
  bool get isEmpty => !mesh && !landmarks && heat == null;

  @override
  bool operator ==(Object other) =>
      other is RigOverlay &&
      other.mesh == mesh &&
      other.landmarks == landmarks &&
      other.heat == heat &&
      other.heatOpacity == heatOpacity;

  @override
  int get hashCode => Object.hash(mesh, landmarks, heat, heatOpacity);
}

/// Paints [overlay] for [rig] posed at [positions], in image coordinates
/// ([scale] is the image-to-screen scale, to keep strokes a constant size).
void paintRigOverlay(
  Canvas canvas,
  FaceRig rig,
  Float32List positions,
  RigOverlay overlay,
  double scale,
) {
  final heat = overlay.heat;
  if (heat != null) {
    final values = heat == RigRegion.motion
        ? _motion(rig, positions)
        : rig.weights(heat);
    final colors = Int32List(values.length);
    for (var i = 0; i < values.length; i++) {
      colors[i] = _heatColor(values[i], overlay.heatOpacity);
    }
    final vertices = ui.Vertices.raw(
      VertexMode.triangles,
      positions,
      colors: colors,
      indices: rig.indices,
    );
    // dst: the vertex colors as they are (the paint has no color of its own).
    canvas.drawVertices(vertices, BlendMode.dst, Paint());
    vertices.dispose();
  }
  if (overlay.mesh) {
    final indices = rig.indices;
    final lines = Float32List(indices.length * 4);
    var o = 0;
    for (var t = 0; t < indices.length; t += 3) {
      for (final (a, b) in [(0, 1), (1, 2), (2, 0)]) {
        final i = indices[t + a] * 2;
        final j = indices[t + b] * 2;
        lines
          ..[o++] = positions[i]
          ..[o++] = positions[i + 1]
          ..[o++] = positions[j]
          ..[o++] = positions[j + 1];
      }
    }
    canvas.drawRawPoints(
      ui.PointMode.lines,
      lines,
      Paint()
        ..color = const Color(0x40FFFFFF)
        ..strokeWidth = 0.6 / scale,
    );
  }
  if (overlay.landmarks) {
    final points = Float32List.sublistView(positions, 0, rig.landmarkCount * 2);
    canvas.drawRawPoints(
      ui.PointMode.points,
      points,
      Paint()
        ..color = const Color(0xE600E5FF)
        ..strokeWidth = 2.6 / scale
        ..strokeCap = StrokeCap.round,
    );
  }
}

/// How far each vertex moves on its own, 0..1 (1 = 5% of the face height,
/// a wide-open jaw). The head's own motion (sway, nods, tilt) is taken out,
/// so the map shows the mouth, lids and brows working, not the whole face
/// drifting.
Float32List _motion(FaceRig rig, Float32List positions) {
  final rest = rig.rest;
  final head = rig.weights(RigRegion.head);
  // The nose tip and the top of the forehead move only with the head: the
  // similarity (turn, scale, shift) that takes one pair to the other is the
  // head's motion, as a complex number z: p' = a' + z (p - a).
  Offset at(Float32List xy, int i) => Offset(xy[i * 2], xy[i * 2 + 1]);
  final a0 = at(rest, FaceMeshIndex.noseTip);
  final a1 = at(positions, FaceMeshIndex.noseTip);
  final v0 = at(rest, _foreheadTop) - a0;
  final v1 = at(positions, _foreheadTop) - a1;
  final len = v0.distanceSquared;
  final zr = (v1.dx * v0.dx + v1.dy * v0.dy) / len;
  final zi = (v1.dy * v0.dx - v1.dx * v0.dy) / len;

  final full = rig.faceHeight * 0.05;
  final out = Float32List(rig.vertexCount);
  for (var i = 0; i < out.length; i++) {
    final px = rest[i * 2] - a0.dx;
    final py = rest[i * 2 + 1] - a0.dy;
    final headX = a1.dx + zr * px - zi * py - rest[i * 2];
    final headY = a1.dy + zi * px + zr * py - rest[i * 2 + 1];
    final dx = positions[i * 2] - rest[i * 2] - headX * head[i];
    final dy = positions[i * 2 + 1] - rest[i * 2 + 1] - headY * head[i];
    out[i] = math.min(1, math.sqrt(dx * dx + dy * dy) / full);
  }
  return out;
}

/// MediaPipe's landmark at the top of the forehead.
const _foreheadTop = 10;

/// Transparent → blue → green → yellow → red, more opaque as it heats up.
int _heatColor(double t, double opacity) {
  final v = t.clamp(0.0, 1.0);
  // Below ~6% it is noise (the residue of head turns): fully transparent.
  if (v < 0.06) return 0;
  const stops = [
    (0.0, 0x2B6CFF),
    (0.35, 0x00D68F),
    (0.65, 0xFFD400),
    (1.0, 0xFF3B30),
  ];
  var k = 0;
  while (k < stops.length - 2 && v > stops[k + 1].$1) {
    k++;
  }
  final (t0, c0) = stops[k];
  final (t1, c1) = stops[k + 1];
  final f = ((v - t0) / (t1 - t0)).clamp(0.0, 1.0);
  int mix(int shift) {
    final a = (c0 >> shift) & 0xFF;
    final b = (c1 >> shift) & 0xFF;
    return (a + (b - a) * f).round();
  }

  final fade = ((v - 0.06) / 0.24).clamp(0.0, 1.0);
  final alpha = (255 * opacity * fade).round().clamp(0, 255);
  return (alpha << 24) | (mix(16) << 16) | (mix(8) << 8) | mix(0);
}
