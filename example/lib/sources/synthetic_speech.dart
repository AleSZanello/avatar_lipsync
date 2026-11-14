import 'dart:math' as math;
import 'dart:typed_data';

/// Sample rate of the synthetic speech.
const syntheticSampleRate = 24000;

/// A few seconds of speech-like sound with no audio file: syllables made of
/// vowels (harmonics shaped by formants), lip closures (m, b, p) and hisses
/// (s), with a falling intonation. Enough to see every mouth shape.
Float32List syntheticSpeech() {
  // (consonant, vowel) pairs; a space is a short pause.
  const phrase = 'ma ri po sa  a zul  be so  mu cho  pi ta';
  final parts = <Float32List>[];
  final syllables = phrase.split(' ');
  for (var i = 0; i < syllables.length; i++) {
    final s = syllables[i];
    if (s.isEmpty) {
      parts.add(_silence(0.18));
      continue;
    }
    // Intonation: the pitch falls slowly across the phrase.
    final f0 = 230 - 60 * i / syllables.length;
    for (final c in s.split('')) {
      switch (c) {
        case 'm' || 'b' || 'p':
          parts.add(_silence(0.07)); // lips closed
        case 's' || 'z' || 'c' || 'h':
          parts.add(_hiss());
        case 't' || 'l' || 'r':
          parts.add(_silence(0.03));
        case 'a' || 'e' || 'i' || 'o' || 'u':
          parts.add(_vowel(c, f0: f0));
      }
    }
  }
  parts.add(_silence(0.3));
  return _join(parts);
}

const _formants = <String, (double, double, double)>{
  'a': (850, 1600, 2800),
  'e': (500, 2200, 2900),
  'i': (330, 2700, 3200),
  'o': (520, 950, 2800),
  'u': (350, 850, 2700),
};

Float32List _vowel(String v, {required double f0, double seconds = 0.16}) {
  final (f1, f2, f3) = _formants[v]!;
  double resonance(double hz, double centre, double width) =>
      1 / (1 + math.pow((hz - centre) / (width / 2), 2));
  final harmonics = [
    for (var h = 1; h * f0 < 6000; h++)
      (
        h * f0,
        (resonance(h * f0, f1, 110) +
                0.7 * resonance(h * f0, f2, 140) +
                0.35 * resonance(h * f0, f3, 200) +
                0.01) /
            h,
      ),
  ];
  final n = (seconds * syntheticSampleRate).round();
  final out = Float32List(n);
  var peak = 1e-9;
  for (var i = 0; i < n; i++) {
    var x = 0.0;
    for (final (hz, gain) in harmonics) {
      x += gain * math.sin(2 * math.pi * hz * i / syntheticSampleRate);
    }
    out[i] = x;
    peak = math.max(peak, x.abs());
  }
  // Normalise and fade in and out over 15 ms so there are no clicks.
  final fade = (0.015 * syntheticSampleRate).round();
  for (var i = 0; i < n; i++) {
    final edge = math.min(1, math.min(i, n - 1 - i) / fade);
    out[i] = out[i] / peak * 0.3 * edge;
  }
  return out;
}

Float32List _hiss({double seconds = 0.11}) {
  final random = math.Random(7);
  final n = (seconds * syntheticSampleRate).round();
  final out = Float32List(n);
  var a = 0.0;
  var b = 0.0;
  for (var i = 0; i < n; i++) {
    final w = random.nextDouble() * 2 - 1;
    final d1 = w - a; // two first differences push the energy up high
    a = w;
    out[i] = (d1 - b) * 0.03;
    b = d1;
  }
  return out;
}

Float32List _silence(double seconds) =>
    Float32List((seconds * syntheticSampleRate).round());

Float32List _join(List<Float32List> parts) {
  final out = Float32List(parts.fold(0, (n, p) => n + p.length));
  var at = 0;
  for (final p in parts) {
    out.setAll(at, p);
    at += p.length;
  }
  return out;
}
