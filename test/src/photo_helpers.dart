import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:avatar_lipsync/avatar_lipsync.dart';

/// The fixture photo (768 × 768) and the landmarks MediaPipe found on it.
const facePhoto = 'test/fixtures/face.jpg';

FaceLandmarks fixtureLandmarks() {
  final json = jsonDecode(
    File('test/fixtures/face_landmarks.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final xy = Float32List.fromList([
    for (final v in json['xy'] as List<dynamic>) (v as num).toDouble(),
  ]);
  return FaceLandmarks.fromNormalized(
    xy,
    ui.Size(
      (json['width'] as num).toDouble(),
      (json['height'] as num).toDouble(),
    ),
  );
}

Future<ui.Image> loadFixtureImage(String path) async {
  final codec = await ui.instantiateImageCodec(File(path).readAsBytesSync());
  return (await codec.getNextFrame()).image;
}

class FixtureDetector implements FaceLandmarkDetector {
  FixtureDetector({this.found = true});

  final bool found;

  @override
  Future<FaceLandmarks?> detectAsset(String assetKey) async =>
      found ? fixtureLandmarks() : null;
}
