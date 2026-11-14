import 'dart:math' as math;
import 'dart:typed_data';

import 'package:avatar_lipsync/avatar_lipsync.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  group(SpeechTimeline, () {
    test('makes a frame every 10 ms across chunk boundaries', () {
      final timeline = timelineOf(vowel(Viseme.a, seconds: 0.5), start: 2);
      final times = timeline.frames.map((f) => f.time).toList();
      expect(times.length, inInclusiveRange(46, 49));
      for (var i = 1; i < times.length; i++) {
        expect(times[i] - times[i - 1], closeTo(0.01, 1e-6));
      }
      expect(times.first, closeTo(2.0125, 1e-3));
    });

    test('measures the first formant and the lip spread', () {
      SpeechFeatures mid(Viseme v) {
        final timeline = timelineOf(vowel(v));
        return timeline.at(0.1)!;
      }

      expect(mid(Viseme.a).openness, closeTo(850, 120));
      expect(mid(Viseme.i).openness, lessThan(450));
      expect(mid(Viseme.i).spread, greaterThan(mid(Viseme.u).spread + 2));
      expect(mid(Viseme.e).spread, greaterThan(mid(Viseme.o).spread + 2));
      expect(mid(Viseme.a).db, closeTo(-13.5, 3));
    });

    test('hears hiss in sibilants', () {
      final s = timelineOf(hiss()).at(0.06)!;
      expect(s.hiss, greaterThan(1.2));
      expect(timelineOf(vowel(Viseme.a)).at(0.1)!.hiss, lessThan(0.2));
    });

    test('hears nasal murmur when all the energy is low', () {
      final hum = Float32List.fromList([
        for (var i = 0; i < 4800; i++)
          0.2 * math.sin(2 * math.pi * 210 * i / speechRate),
      ]);
      expect(timelineOf(hum).at(0.1)!.nasal, greaterThan(12));
    });

    test('has no frame where nothing plays', () {
      final timeline = timelineOf(vowel(Viseme.a))
        ..add(
          SpeechChunk(
            samples: vowel(Viseme.a),
            startTime: 1,
            sampleRate: speechRate,
          ),
        );
      expect(timeline.at(0.5), isNull);
      expect(timeline.at(1.1), isNotNull);
      expect(timeline.range(0.1, 0.15), hasLength(5));
    });

    test('flush drops what will not be heard; prune drops the past', () {
      final timeline = timelineOf(vowel(Viseme.a, seconds: 1))..flush(0.5);
      expect(timeline.frames.last.time, lessThan(0.5));
      timeline.prune(0.3);
      expect(timeline.frames.first.time, greaterThanOrEqualTo(0.3));
      // After a flush the next chunk starts a fresh stream.
      timeline.add(
        SpeechChunk(
          samples: vowel(Viseme.o),
          startTime: 0.6,
          sampleRate: speechRate,
        ),
      );
      expect(timeline.at(0.7), isNotNull);
    });

    test('ignores empty chunks', () {
      final timeline = SpeechTimeline()
        ..add(
          SpeechChunk(
            samples: Float32List(0),
            startTime: 0,
            sampleRate: speechRate,
          ),
        );
      expect(timeline.frames, isEmpty);
    });
  });
}
