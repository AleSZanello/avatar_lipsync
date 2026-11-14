import 'dart:typed_data';

import 'package:avatar_lipsync/avatar_lipsync.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// A few seconds of varied speech so the analyzer learns the voice.
final Float32List _warmUp = join([
  for (var round = 0; round < 6; round++)
    for (final v in [Viseme.a, Viseme.e, Viseme.i, Viseme.o, Viseme.u])
      vowel(v, seconds: 0.18),
]);

void main() {
  group(LipSyncAnalyzer, () {
    test('opens with the voice and closes in silence', () {
      final timeline = timelineOf(
        join([silence(0.3), vowel(Viseme.a, seconds: 0.4), silence(0.5)]),
      );
      final frames = play(LipSyncAnalyzer(), timeline, 0, 1.2);
      final during = frames.where((f) => f.$1 > 0.45 && f.$1 < 0.65);
      final after = frames.where((f) => f.$1 > 0.8 && f.$1 < 1.05);
      expect(during.every((f) => f.$2.gap > 0.15), isTrue);
      expect(during.every((f) => f.$2.jaw > 0.03), isTrue);
      expect(during.every((f) => f.$2.speaking), isTrue);
      expect(after.every((f) => f.$2.gap < 0.01), isTrue);
      expect(after.last.$2.viseme, Viseme.rest);
    });

    test('moves just before the sound, never after it', () {
      final timeline = timelineOf(
        join([silence(0.5), vowel(Viseme.a, seconds: 0.3)]),
      );
      final frames = play(LipSyncAnalyzer(), timeline, 0, 0.8);
      final firstOpen = frames.firstWhere((f) => f.$2.gap > 0.02).$1;
      expect(firstOpen, lessThan(0.5));
      expect(firstOpen, greaterThan(0.44));
    });

    test('tells the five vowels apart once it knows the voice', () {
      for (final v in [Viseme.a, Viseme.e, Viseme.i, Viseme.o, Viseme.u]) {
        final timeline = timelineOf(join([_warmUp, vowel(v, seconds: 0.3)]));
        final start = _warmUp.length / speechRate;
        final frames = play(LipSyncAnalyzer(), timeline, 0, start + 0.25);
        expect(frames.last.$2.viseme, v, reason: '${v.name} vowel');
      }
    });

    test('rounds for o and u and spreads for e and i', () {
      LipSyncFrame endOf(Viseme v) {
        final timeline = timelineOf(join([_warmUp, vowel(v, seconds: 0.3)]));
        final start = _warmUp.length / speechRate;
        return play(LipSyncAnalyzer(), timeline, 0, start + 0.25).last.$2;
      }

      expect(endOf(Viseme.u).round, greaterThan(0.6));
      expect(endOf(Viseme.u).width, lessThan(-0.15));
      expect(endOf(Viseme.i).width, greaterThan(0.06));
      expect(endOf(Viseme.a).gap, greaterThan(endOf(Viseme.i).gap * 2));
    });

    test('presses the lips for a closure inside a phrase, early', () {
      // "a-ba": the second formant falls into the closure and rises out.
      final timeline = timelineOf(
        join([
          vowel(Viseme.a, seconds: 0.36),
          vowel(Viseme.u, seconds: 0.04),
          silence(0.07),
          vowel(Viseme.u, seconds: 0.04),
          vowel(Viseme.a, seconds: 0.36),
        ]),
      );
      final frames = play(LipSyncAnalyzer(), timeline, 0, 0.9);
      final closed = frames.where((f) => f.$2.press > 0.4).map((f) => f.$1);
      expect(closed, isNotEmpty);
      // The lips are already pressing before the sound stops at 0.4 s.
      expect(closed.first, lessThan(0.4));
      final inDip = frames.where((f) => f.$1 > 0.405 && f.$1 < 0.43);
      expect(inDip.every((f) => f.$2.gap < 0.08), isTrue);
      expect(inDip.every((f) => f.$2.speaking), isTrue);
    });

    test('barely presses for a tongue closure (a-ta)', () {
      final timeline = timelineOf(
        join([
          vowel(Viseme.a, seconds: 0.4),
          silence(0.06),
          hiss(seconds: 0.03, amplitude: 0.2),
          vowel(Viseme.a, seconds: 0.4),
        ]),
      );
      final frames = play(LipSyncAnalyzer(), timeline, 0, 0.9);
      expect(frames.every((f) => f.$2.press < 0.2), isTrue);
    });

    test('does not press at the end of a phrase', () {
      final timeline = timelineOf(
        join([vowel(Viseme.a, seconds: 0.4), silence(0.6)]),
      );
      final frames = play(LipSyncAnalyzer(), timeline, 0, 1);
      expect(frames.every((f) => f.$2.press < 0.3), isTrue);
    });

    test('shows the fricative shape for hiss', () {
      final timeline = timelineOf(
        join([_warmUp, hiss(seconds: 0.2), vowel(Viseme.a)]),
      );
      final at = _warmUp.length / speechRate + 0.15;
      final frames = play(LipSyncAnalyzer(), timeline, 0, at);
      expect(frames.last.$2.viseme, Viseme.fricative);
    });

    test('takes a breath in a long pause', () {
      final timeline = timelineOf(
        join([vowel(Viseme.a, seconds: 0.4), silence(1.2)]),
      );
      final frames = play(LipSyncAnalyzer(), timeline, 0, 1.5);
      final pause = frames.where((f) => f.$1 > 0.85 && f.$1 < 1.2);
      expect(pause.any((f) => f.$2.gap > 0.02), isTrue);
      expect(frames.last.$2.gap, lessThan(0.005));
    });

    test('settles to rest with no clock', () {
      final analyzer = LipSyncAnalyzer();
      play(analyzer, timelineOf(vowel(Viseme.a, seconds: 0.4)), 0, 0.3);
      var frame = analyzer.frame;
      for (var i = 0; i < 30; i++) {
        frame = analyzer.idle(1 / 60);
      }
      expect(frame.gap, lessThan(0.005));
      expect(frame.viseme, Viseme.rest);
    });

    test('follows a clock that restarts (a new audio context)', () {
      final analyzer = LipSyncAnalyzer();
      play(analyzer, timelineOf(vowel(Viseme.a, seconds: 2)), 0, 1.5);
      final again = timelineOf(vowel(Viseme.a, seconds: 0.6));
      final frames = play(analyzer, again, 0, 0.4);
      expect(frames.last.$2.gap, greaterThan(0.1));
      expect(frames.last.$2.speaking, isTrue);
    });

    test('reset closes the mouth at once', () {
      final analyzer = LipSyncAnalyzer();
      play(analyzer, timelineOf(vowel(Viseme.a, seconds: 0.4)), 0, 0.3);
      analyzer.reset();
      expect(analyzer.frame.gap, 0);
      expect(analyzer.frame.toString(), contains('rest'));
    });
  });
}
