import 'dart:typed_data';
import 'dart:ui';

import 'package:avatar_lipsync/src/face/face_landmarks.dart';
import 'package:flutter/painting.dart' show HSLColor;

/// Colors for the inside of the mouth, taken from the photo itself so the
/// cavity and teeth match its lighting, white balance and skin tone.
class MouthPalette {
  /// Creates a palette.
  const MouthPalette({
    required this.deep,
    required this.cavity,
    required this.teeth,
    required this.teethShade,
    required this.tongue,
    required this.tongueShade,
  });

  /// Derives the palette from the lip and eye-white colors of a photo.
  ///
  /// The cavity is the lip hue pulled toward red (the inside of a mouth is
  /// redder than its lips) at 10–24% lightness, never black since a mouth is
  /// lit from the front. The teeth are a warm ivory carrying the photo's
  /// white balance (its eye white), 15% darker than that white. The tongue
  /// is the cavity hue, lighter.
  factory MouthPalette.fromColors({required Color lip, required Color sclera}) {
    final hsl = HSLColor.fromColor(lip);
    // Shortest way round the hue circle toward red (355°).
    var delta = (355 - hsl.hue) % 360;
    if (delta > 180) delta -= 360;
    final hue = (hsl.hue + delta * 0.5) % 360;
    final saturation = hsl.saturation.clamp(0.45, 0.65);
    Color tone(double lightness, {double sat = 1}) =>
        HSLColor.fromAHSL(1, hue, saturation * sat, lightness).toColor();
    final white = HSLColor.fromColor(
      Color.lerp(const Color(0xFFE8DECD), sclera, 0.35)!,
    );
    final teeth = white
        .withLightness((white.lightness * 0.85).clamp(0.62, 0.82))
        .withSaturation(white.saturation.clamp(0.12, 0.3))
        .toColor();
    return MouthPalette(
      deep: tone(0.10),
      cavity: tone(0.24),
      teeth: teeth,
      teethShade: Color.lerp(teeth, tone(0.3), 0.45)!,
      tongue: tone(0.40, sat: 1.1),
      tongueShade: tone(0.28, sat: 1.1),
    );
  }

  /// Samples the lip and eye-white colors of [rgba] (the photo's raw RGBA
  /// bytes, [width] pixels wide) at the face [landmarks].
  factory MouthPalette.sample(
    ByteData rgba,
    int width,
    FaceLandmarks landmarks,
  ) {
    final height = rgba.lengthInBytes ~/ (width * 4);
    Color average(Offset at, int radius) {
      var r = 0;
      var g = 0;
      var b = 0;
      var n = 0;
      for (var dy = -radius; dy <= radius; dy++) {
        for (var dx = -radius; dx <= radius; dx++) {
          final x = (at.dx.round() + dx).clamp(0, width - 1);
          final y = (at.dy.round() + dy).clamp(0, height - 1);
          final i = (y * width + x) * 4;
          r += rgba.getUint8(i);
          g += rgba.getUint8(i + 1);
          b += rgba.getUint8(i + 2);
          n++;
        }
      }
      return Color.fromARGB(255, r ~/ n, g ~/ n, b ~/ n);
    }

    final lm = landmarks.points;
    // The body of the lower lip, between its inner edge and its bottom.
    final lip = average(
      Offset.lerp(
        lm[FaceMeshIndex.lowerInnerLipMid],
        lm[FaceMeshIndex.lowerLipBottom],
        0.45,
      )!,
      2,
    );
    // The eye white between each iris and the inner corner; the brighter
    // one (the other may be in shadow).
    final whites = [
      for (final (iris, inner) in [
        (FaceMeshIndex.firstIris.first, FaceMeshIndex.firstEyeCorners.$2),
        (FaceMeshIndex.secondIris.first, FaceMeshIndex.secondEyeCorners.$1),
      ])
        if (lm.length > iris)
          average(Offset.lerp(lm[iris], lm[inner], 0.62)!, 1),
    ];
    if (whites.isEmpty) return fallback;
    whites.sort((a, b) => b.computeLuminance().compareTo(a.computeLuminance()));
    return MouthPalette.fromColors(lip: lip, sclera: whites.first);
  }

  /// Used before the photo is sampled.
  static const fallback = MouthPalette(
    deep: Color(0xFF1C0809),
    cavity: Color(0xFF4A1A1C),
    teeth: Color(0xFFE0D6C8),
    teethShade: Color(0xFFB4A694),
    tongue: Color(0xFFA0484D),
    tongueShade: Color(0xFF702C31),
  );

  /// The far back of the mouth.
  final Color deep;

  /// The cavity just behind the lips.
  final Color cavity;

  /// Lit teeth.
  final Color teeth;

  /// Teeth in shadow (their lower edge, the sides).
  final Color teethShade;

  /// The tongue's top.
  final Color tongue;

  /// The tongue's sides.
  final Color tongueShade;
}
