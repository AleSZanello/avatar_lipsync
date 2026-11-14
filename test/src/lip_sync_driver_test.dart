import 'package:avatar_lipsync/avatar_lipsync.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  group(LipSyncDriver, () {
    test('analyses scheduled speech and follows the audible clock', () async {
      final source = FakeSource();
      final driver = LipSyncDriver(source);
      source.schedule(vowel(Viseme.a, seconds: 0.6), start: 10);
      expect(driver.timeline.frames, isNotEmpty);
      var frame = LipSyncFrame.rest;
      for (var t = 10.0; t < 10.3; t += 1 / 60) {
        source.audibleTime = t;
        frame = driver.tick(1 / 60);
      }
      expect(frame.gap, greaterThan(0.1));
      expect(driver.analysisMs, greaterThanOrEqualTo(0));
      expect(driver.tickMs, greaterThanOrEqualTo(0));
      await driver.dispose();
    });

    test('a flush silences what was scheduled after it', () async {
      final source = FakeSource();
      final driver = LipSyncDriver(source);
      source
        ..schedule(vowel(Viseme.a, seconds: 1))
        ..flush(0.3);
      var frame = LipSyncFrame.rest;
      for (var t = 0.0; t < 0.6; t += 1 / 60) {
        source.audibleTime = t;
        frame = driver.tick(1 / 60);
      }
      expect(frame.gap, lessThan(0.01));
      await driver.dispose();
    });

    test('keeps the mouth closed without a clock', () async {
      final source = FakeSource();
      final driver = LipSyncDriver(source);
      expect(driver.tick(1 / 60).viseme, Viseme.rest);
      await driver.dispose();
    });
  });
}
