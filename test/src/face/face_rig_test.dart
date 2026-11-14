import 'dart:typed_data';
import 'dart:ui';

import 'package:avatar_lipsync/avatar_lipsync.dart';
import 'package:flutter_test/flutter_test.dart';

import '../photo_helpers.dart';

Offset _at(Float32List positions, int i) =>
    Offset(positions[i * 2], positions[i * 2 + 1]);

const _open = LipSyncFrame(
  level: 0.9,
  gap: 0.4,
  jaw: 0.11,
  width: 0.05,
  round: 0,
  press: 0,
  viseme: Viseme.a,
);

void main() {
  group(FaceRig, () {
    late FaceLandmarks landmarks;
    late FaceRig rig;

    setUp(() {
      landmarks = fixtureLandmarks();
      rig = FaceRig.build(landmarks)!;
    });

    test('refuses incomplete landmarks', () {
      expect(
        FaceRig.build(const FaceLandmarks([Offset.zero], Size(10, 10))),
        isNull,
      );
    });

    test('refuses a face whose mouth corners coincide', () {
      final points = [...landmarks.points];
      points[FaceMeshIndex.mouthCornerRight] =
          points[FaceMeshIndex.mouthCornerLeft];
      expect(FaceRig.build(FaceLandmarks(points, landmarks.imageSize)), isNull);
    });

    test('rests exactly on the photo', () {
      final positions = rig.pose(LipSyncFrame.rest, const AvatarPose());
      expect(positions, rig.rest);
      expect(rig.mouthGap, 0);
      expect(rig.vertexCount, greaterThan(FaceMeshIndex.faceMeshCount));
      expect(rig.indices.length % 3, 0);
    });

    test('opening drops the jaw and parts the lips', () {
      final rest = Float32List.fromList(rig.rest);
      final open = rig.pose(_open, const AvatarPose());
      final chinDrop =
          _at(open, FaceMeshIndex.chin).dy - _at(rest, FaceMeshIndex.chin).dy;
      final lowerLip =
          _at(open, FaceMeshIndex.lowerInnerLipMid).dy -
          _at(rest, FaceMeshIndex.lowerInnerLipMid).dy;
      final upperLip =
          _at(open, FaceMeshIndex.upperInnerLipMid).dy -
          _at(rest, FaceMeshIndex.upperInnerLipMid).dy;
      final nose =
          _at(open, FaceMeshIndex.noseTip) - _at(rest, FaceMeshIndex.noseTip);
      expect(chinDrop, greaterThan(5));
      expect(lowerLip, greaterThan(chinDrop * 0.8));
      expect(upperLip, lessThan(0));
      expect(nose.distance, lessThan(0.5));
      // The lips part by the asked 0.4 mouth widths.
      final mouthWidth =
          (landmarks.points[FaceMeshIndex.mouthCornerLeft] -
                  landmarks.points[FaceMeshIndex.mouthCornerRight])
              .distance;
      expect(rig.mouthGap, closeTo(0.4 * mouthWidth, mouthWidth * 0.05));
      expect(rig.mouthOutline, hasLength(20));
    });

    test('opening and rounding the mouth leave the eyes and nose alone', () {
      for (final frame in [
        _open,
        const LipSyncFrame(
          level: 0.8,
          gap: 0.25,
          jaw: 0.12,
          width: -0.3,
          round: 0.7,
          press: 0,
          viseme: Viseme.o,
        ),
      ]) {
        final posed = rig.pose(frame, const AvatarPose());
        for (final i in [33, 133, 159, 145, 362, 263, 386, 374, 6, 168]) {
          final moved = (_at(posed, i) - _at(rig.rest, i)).distance;
          expect(moved, lessThan(0.5), reason: 'landmark $i moved $moved');
        }
      }
      // Nothing between the mouth and the eyes follows the jaw.
      final jaw = rig.weights(RigRegion.jaw);
      for (final i in [129, 358, 203, 423, 36, 266]) {
        expect(jaw[i], lessThan(0.05), reason: 'jaw weight at $i');
      }
    });

    test('rounding pulls the mouth corners in, spreading pushes them out', () {
      final rest = _at(rig.rest, FaceMeshIndex.mouthCornerRight).dx;
      final round = rig.pose(
        const LipSyncFrame(
          level: 0.5,
          gap: 0.08,
          jaw: 0.03,
          width: -0.3,
          round: 1,
          press: 0,
          viseme: Viseme.u,
        ),
        const AvatarPose(),
      );
      expect(_at(round, FaceMeshIndex.mouthCornerRight).dx, lessThan(rest));
      final spread = rig.pose(
        const LipSyncFrame(
          level: 0.5,
          gap: 0.11,
          jaw: 0.03,
          width: 0.18,
          round: 0,
          press: 0,
          viseme: Viseme.i,
        ),
        const AvatarPose(),
      );
      expect(_at(spread, FaceMeshIndex.mouthCornerRight).dx, greaterThan(rest));
    });

    test('pressed lips squeeze together', () {
      final pressed = rig.pose(
        const LipSyncFrame(
          level: 0.6,
          gap: 0,
          jaw: 0,
          width: -0.03,
          round: 0,
          press: 1,
          viseme: Viseme.rest,
        ),
        const AvatarPose(),
      );
      final upper =
          _at(pressed, FaceMeshIndex.upperInnerLipMid).dy -
          _at(rig.rest, FaceMeshIndex.upperInnerLipMid).dy;
      final lower =
          _at(pressed, FaceMeshIndex.lowerInnerLipMid).dy -
          _at(rig.rest, FaceMeshIndex.lowerInnerLipMid).dy;
      expect(upper, greaterThan(0.5));
      expect(lower, lessThan(-0.5));
    });

    test('a blink brings each upper lid down to its lower lid', () {
      final closed = rig.pose(LipSyncFrame.rest, const AvatarPose(blink: 1));
      for (final (upper, lower) in [
        FaceMeshIndex.firstEyeLids,
        FaceMeshIndex.secondEyeLids,
      ]) {
        final gap = _at(closed, lower).dy - _at(closed, upper).dy;
        final restGap = _at(rig.rest, lower).dy - _at(rig.rest, upper).dy;
        expect(gap, lessThan(restGap * 0.2));
      }
    });

    test('a blink closes the whole eye, not just its middle', () {
      final closed = rig.pose(LipSyncFrame.rest, const AvatarPose(blink: 1));
      for (final (upper, lower) in [
        (FaceMeshIndex.firstUpperLid, FaceMeshIndex.firstLowerLid),
        (FaceMeshIndex.secondUpperLid, FaceMeshIndex.secondLowerLid),
      ]) {
        // Skip the corners (shared by both edges).
        for (var k = 2; k < upper.length - 2; k++) {
          final open =
              (_at(rig.rest, lower[k]) - _at(rig.rest, upper[k])).distance;
          final shut = (_at(closed, lower[k]) - _at(closed, upper[k])).distance;
          expect(shut, lessThan(open * 0.3), reason: 'lid ${upper[k]}');
        }
      }
      // The brows stay where they are.
      for (final i in [
        ...FaceMeshIndex.firstBrow,
        ...FaceMeshIndex.secondBrow,
      ]) {
        expect((_at(closed, i) - _at(rig.rest, i)).distance, lessThan(0.5));
      }
    });

    test('the head moves while the background stays put', () {
      final posed = rig.pose(
        LipSyncFrame.rest,
        const AvatarPose(roll: 0.02, dy: 0.02),
      );
      final nose =
          _at(posed, FaceMeshIndex.noseTip) -
          _at(rig.rest, FaceMeshIndex.noseTip);
      expect(nose.distance, greaterThan(3));
      // The image corners are mesh vertices too; they must not move.
      final last = rig.vertexCount - 1;
      expect(_at(posed, last), _at(rig.rest, last));
    });

    test('exposes the landmarks and a weight field per region', () {
      expect(rig.landmarkCount, landmarks.points.length);
      for (final region in RigRegion.values) {
        final w = rig.weights(region);
        expect(w, hasLength(rig.vertexCount), reason: region.name);
        expect(w.every((v) => v >= 0 && v <= 1), isTrue, reason: region.name);
        expect(identical(rig.weights(region), w), isTrue, reason: 'cached');
      }
      expect(rig.weights(RigRegion.motion).every((v) => v == 0), isTrue);
      // The jaw pulls the chin, not the forehead.
      final jaw = rig.weights(RigRegion.jaw);
      expect(jaw[FaceMeshIndex.chin], greaterThan(0.5));
      expect(jaw[10], 0);
      expect(rig.weights(RigRegion.lips)[FaceMeshIndex.lowerInnerLipMid], 1);
    });

    test('brows rise and irises follow the gaze', () {
      final posed = rig.pose(
        LipSyncFrame.rest,
        const AvatarPose(brow: 1, gazeX: 1),
      );
      const browPoint = 105;
      expect(_at(posed, browPoint).dy, lessThan(_at(rig.rest, browPoint).dy));
      final iris = FaceMeshIndex.firstIris.first;
      expect(_at(posed, iris).dx, greaterThan(_at(rig.rest, iris).dx));
    });
  });
}
