import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:avatar_lipsync/avatar_lipsync.dart';

/// A common streaming TTS output rate.
const speechRate = 24000;

/// Formants (Hz) of the five vowels for an adult female voice.
const Map<Viseme, (double, double, double)> vowelFormants = {
  Viseme.a: (850.0, 1600.0, 2800.0),
  Viseme.e: (500.0, 2200.0, 2900.0),
  Viseme.i: (330.0, 2700.0, 3200.0),
  Viseme.o: (520.0, 950.0, 2800.0),
  Viseme.u: (350.0, 850.0, 2700.0),
};

/// A vowel: harmonics of [f0] shaped by three formant resonances, with the
/// natural -6 dB/octave tilt of a voice, at peak [amplitude].
Float32List vowel(
  Viseme v, {
  double seconds = 0.2,
  double f0 = 210,
  double amplitude = 0.3,
}) {
  final (f1, f2, f3) = vowelFormants[v]!;
  double resonance(double hz, double centre, double bandwidth) =>
      1 / (1 + math.pow((hz - centre) / (bandwidth / 2), 2));
  final harmonics = <(double, double)>[];
  for (var h = 1; h * f0 < 6000; h++) {
    final hz = h * f0;
    final gain =
        (resonance(hz, f1, 110) +
            0.7 * resonance(hz, f2, 140) +
            0.35 * resonance(hz, f3, 200) +
            0.01) /
        h;
    harmonics.add((hz, gain));
  }
  final n = (seconds * speechRate).round();
  final out = Float32List(n);
  var peak = 0.0;
  for (var i = 0; i < n; i++) {
    var x = 0.0;
    for (final (hz, gain) in harmonics) {
      x += gain * math.sin(2 * math.pi * hz * i / speechRate);
    }
    out[i] = x;
    peak = math.max(peak, x.abs());
  }
  for (var i = 0; i < n; i++) {
    out[i] = out[i] / peak * amplitude;
  }
  return out;
}

/// A sibilant: white noise pushed above ~4 kHz.
Float32List hiss({double seconds = 0.12, double amplitude = 0.12}) {
  final random = math.Random(5);
  final n = (seconds * speechRate).round();
  final out = Float32List(n);
  var a = 0.0;
  var b = 0.0;
  for (var i = 0; i < n; i++) {
    final w = random.nextDouble() * 2 - 1;
    // Two first differences: +12 dB/octave, so the energy sits up high.
    final d1 = w - a;
    a = w;
    out[i] = (d1 - b) * amplitude / 4;
    b = d1;
  }
  return out;
}

/// Silence.
Float32List silence(double seconds) =>
    Float32List((seconds * speechRate).round());

/// Joins pieces of signal.
Float32List join(List<Float32List> parts) {
  final out = Float32List(parts.fold(0, (n, p) => n + p.length));
  var at = 0;
  for (final p in parts) {
    out.setAll(at, p);
    at += p.length;
  }
  return out;
}

/// Splits [samples] into streaming-sized chunks (40 ms) starting at [start].
List<SpeechChunk> chunked(Float32List samples, {double start = 0}) {
  const size = 960;
  return [
    for (var i = 0; i < samples.length; i += size)
      SpeechChunk(
        samples: Float32List.sublistView(
          samples,
          i,
          math.min(i + size, samples.length),
        ),
        startTime: start + i / speechRate,
        sampleRate: speechRate,
      ),
  ];
}

/// A timeline of [samples] scheduled at [start].
SpeechTimeline timelineOf(Float32List samples, {double start = 0}) {
  final timeline = SpeechTimeline();
  chunked(samples, start: start).forEach(timeline.add);
  return timeline;
}

/// Runs [analyzer] over [timeline] from [from] to [to] at 60 fps and returns
/// every frame.
List<(double, LipSyncFrame)> play(
  LipSyncAnalyzer analyzer,
  SpeechTimeline timeline,
  double from,
  double to,
) => [
  for (var t = from; t < to; t += 1 / 60)
    (t, analyzer.update(timeline, t, 1 / 60)),
];

/// A source the test drives by hand.
class FakeSource implements LipSyncSource {
  final _chunks = StreamController<SpeechChunk>.broadcast(sync: true);
  final _flushes = StreamController<double>.broadcast(sync: true);

  @override
  double? audibleTime;

  @override
  Stream<SpeechChunk> get chunks => _chunks.stream;

  @override
  Stream<double> get flushes => _flushes.stream;

  void schedule(Float32List samples, {double start = 0}) {
    chunked(samples, start: start).forEach(_chunks.add);
  }

  void flush(double time) => _flushes.add(time);
}
