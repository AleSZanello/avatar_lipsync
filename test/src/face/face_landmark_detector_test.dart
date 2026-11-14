import 'package:avatar_lipsync/avatar_lipsync.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group(FaceLandmarkDetector, () {
    test('finds no face off the web, so the avatar falls back', () async {
      expect(await FaceLandmarkDetector().detectAsset('face.jpg'), isNull);
    });
  });
}
