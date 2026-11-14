import 'dart:math' as math;

import 'package:avatar_lipsync/avatar_lipsync.dart';
import 'package:flutter_test/flutter_test.dart';

const _loud = LipSyncFrame(
  level: 0.9,
  gap: 0.35,
  jaw: 0.1,
  width: 0.05,
  round: 0,
  press: 0,
  viseme: Viseme.a,
  speaking: true,
);

const _quiet = LipSyncFrame(
  level: 0.2,
  gap: 0.05,
  jaw: 0.01,
  width: 0,
  round: 0,
  press: 0,
  viseme: Viseme.e,
  speaking: true,
);

void main() {
  group(AvatarMotion, () {
    List<AvatarPose> run(
      AvatarMotion motion,
      double seconds, [
      LipSyncFrame frame = LipSyncFrame.rest,
    ]) => [
      for (var t = 0.0; t < seconds; t += 1 / 60) motion.update(1 / 60, frame),
    ];

    test('blinks every few seconds, fully and briefly', () {
      final poses = run(AvatarMotion(), 20);
      final closed = poses.where((p) => p.blink > 0.95).length;
      final blinks = [
        for (var i = 1; i < poses.length; i++)
          if (poses[i].blink > 0.5 && poses[i - 1].blink <= 0.5) i,
      ];
      // About 17 a minute at rest: 3 to 9 in 20 s.
      expect(blinks.length, inInclusiveRange(3, 10));
      // Each blink holds closed for only a couple of frames.
      expect(closed, lessThan(blinks.length * 5));
    });

    test('moves the head a little, never a lot', () {
      final poses = run(AvatarMotion(), 10);
      for (final p in poses) {
        expect(p.roll.abs(), lessThan(0.03));
        expect(p.dx.abs(), lessThan(0.01));
        expect(p.dy.abs(), lessThan(0.03));
        expect((p.scale - 1).abs(), lessThan(0.01));
      }
      expect(poses.map((p) => p.roll).toSet().length, greaterThan(100));
    });

    test('raises the brows on a stressed syllable, then settles', () {
      // Over many stressed syllables the brows rise now and then and the
      // head nods, each settling between them.
      final motion = AvatarMotion();
      final poses = <AvatarPose>[];
      for (var i = 0; i < 12; i++) {
        poses
          ..addAll(run(motion, 0.3, _quiet))
          ..addAll(run(motion, 0.2, _loud));
      }
      expect(poses.any((p) => p.brow > 0.5), isTrue);
      expect(poses.map((p) => p.dy).reduce(math.max), greaterThan(0.008));
      expect(run(motion, 3).last.brow, lessThan(0.05));
    });

    test('looks away at the start of some phrases', () {
      final motion = AvatarMotion(seed: 11);
      final poses = <AvatarPose>[];
      for (var i = 0; i < 10; i++) {
        poses
          ..addAll(run(motion, 0.8))
          ..addAll(run(motion, 1.5, _quiet));
      }
      expect(poses.any((p) => p.gazeX.abs() > 0.3 && p.gazeY < -0.2), isTrue);
    });

    test('holds eye contact while listening, with tiny saccades', () {
      final poses = run(AvatarMotion(seed: 4), 20);
      expect(poses.every((p) => p.gazeX.abs() < 0.07), isTrue);
      expect(poses.map((p) => p.gazeX).toSet().length, greaterThan(10));
    });

    test('keeps only blinks with reduced motion', () {
      final poses = run(AvatarMotion(reduced: true), 10, _loud);
      expect(
        poses.every((p) => p.roll == 0 && p.dy == 0 && p.brow == 0),
        isTrue,
      );
      expect(poses.any((p) => p.blink > 0.9), isTrue);
    });
  });
}
