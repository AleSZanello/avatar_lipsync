import 'dart:typed_data';
import 'dart:ui';

import 'package:avatar_lipsync/avatar_lipsync.dart';
import 'package:flutter/painting.dart' show HSLColor;
import 'package:flutter_test/flutter_test.dart';

import '../photo_helpers.dart';

ByteData _solid(int width, int height, Color color) {
  final bytes = Uint8List(width * height * 4);
  for (var i = 0; i < bytes.length; i += 4) {
    bytes
      ..[i] = (color.r * 255).round()
      ..[i + 1] = (color.g * 255).round()
      ..[i + 2] = (color.b * 255).round()
      ..[i + 3] = 255;
  }
  return ByteData.sublistView(bytes);
}

void main() {
  group(MouthPalette, () {
    test('a dark, red cavity and light warm teeth from the photo', () {
      final palette = MouthPalette.fromColors(
        lip: const Color(0xFFB07A80),
        sclera: const Color(0xFFD8D4D0),
      );
      final deep = HSLColor.fromColor(palette.deep);
      final cavity = HSLColor.fromColor(palette.cavity);
      final teeth = HSLColor.fromColor(palette.teeth);
      expect(deep.lightness, closeTo(0.10, 0.02));
      expect(cavity.lightness, greaterThan(deep.lightness));
      expect(deep.saturation, greaterThanOrEqualTo(0.44));
      expect(teeth.lightness, inInclusiveRange(0.6, 0.83));
      expect(
        palette.tongue.computeLuminance(),
        greaterThan(palette.cavity.computeLuminance()),
      );
    });

    test('samples the lip and eye white at the landmarks', () {
      final landmarks = fixtureLandmarks();
      final palette = MouthPalette.sample(
        _solid(768, 768, const Color(0xFF9A5A60)),
        768,
        landmarks,
      );
      expect(palette, isNot(same(MouthPalette.fallback)));
      expect(palette.deep, isNot(palette.teeth));
    });

    test('falls back without iris points', () {
      final points = fixtureLandmarks().points.take(468).toList();
      final palette = MouthPalette.sample(
        _solid(768, 768, const Color(0xFF9A5A60)),
        768,
        FaceLandmarks(points, const Size(768, 768)),
      );
      expect(palette, same(MouthPalette.fallback));
    });
  });
}
