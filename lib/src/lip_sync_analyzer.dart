import 'dart:math' as math;

import 'package:avatar_lipsync/src/speech_timeline.dart';
import 'package:avatar_lipsync/src/viseme.dart';

/// One animation frame of the mouth, already smoothed.
///
/// Geometry is in face units so any photo or character can use it: lip
/// openings and widths as fractions of the neutral mouth width (W), jaw drop
/// as a fraction of the nose-to-chin distance (H).
class LipSyncFrame {
  /// Creates a frame.
  const LipSyncFrame({
    required this.level,
    required this.gap,
    required this.jaw,
    required this.width,
    required this.round,
    required this.press,
    required this.viseme,
    this.speaking = false,
  });

  /// The closed, silent mouth.
  static const rest = LipSyncFrame(
    level: 0,
    gap: 0,
    jaw: 0,
    width: 0,
    round: 0,
    press: 0,
    viseme: Viseme.rest,
  );

  /// Loudness of the voice, 0..1, relative to this speaker.
  final double level;

  /// Distance between the lips, in mouth widths (W).
  final double gap;

  /// Chin drop, in nose-to-chin distances (H).
  final double jaw;

  /// Change of mouth width, in mouth widths (positive spreads).
  final double width;

  /// Lip rounding, 0..1.
  final double round;

  /// Lips pressed together (m, b, p), 0..1.
  final double press;

  /// The dominant mouth shape. Feeds a Rive `viseme` input.
  final Viseme viseme;

  /// Whether the voice is in a phrase (short pauses included).
  final bool speaking;

  /// How open the mouth is, 0..1 (a wide-open "a" is 1).
  double get mouthOpen => (gap / Viseme.a.gap).clamp(0.0, 1.0);

  @override
  String toString() =>
      'LipSyncFrame(${viseme.name}, gap ${gap.toStringAsFixed(3)}, '
      'jaw ${jaw.toStringAsFixed(3)}, press ${press.toStringAsFixed(2)})';
}

/// Turns the speech timeline into mouth frames.
///
/// It reads the timeline a little ahead of what is heard ([lead]), because
/// a mouth that moves just before the sound looks in sync and one that moves
/// after it does not (ITU-R BT.1359: sound late is noticed at 125 ms, sound
/// early already at 45 ms).
///
/// Following JALI (Edwards et al. 2016), the jaw follows loudness while the
/// lip shape follows articulation, so rounding and spreading stay visible in
/// quiet speech:
/// - loudness is relative to the speaker's typical level (any voice, any
///   gain), compressed as `((dB - floor) / 28)^0.7`;
/// - the vowel is a soft blend: the first formant marks the open a, the
///   second formant says front or back (spread or rounded lips) and how far
///   (i and u are the extremes), both compared with the speaker's running
///   average; energy above 4 kHz blends in the fricative shape;
/// - each shape weight rises and falls at its own pace (Cohen–Massaro style
///   coarticulation: rounding lingers, fricatives barely show);
/// - a sharp dip inside a phrase (a stop), or nasal murmur, closes the
///   mouth: the lips press, and since the timeline is known ahead, they
///   close before the sound does;
/// - the gap and the jaw move as slightly underdamped springs;
/// - in a pause longer than 400 ms the lips part a little to breathe.
class LipSyncAnalyzer {
  /// Creates an analyzer.
  LipSyncAnalyzer({this.lead = 0.03});

  /// How far ahead of the heard sound the mouth runs (seconds).
  final double lead;

  final _openness = _RunningStat(9.1, deviation: 0.45);
  final _spread = _RunningStat(10.8, deviation: 0.5);
  final _nasal = _RunningStat(3, deviation: 2);
  double _typicalDb = -22;
  double _lastStatTime = double.negativeInfinity;

  final _weights = <Viseme, double>{
    for (final v in Viseme.values)
      if (v != Viseme.rest) v: 0,
  };
  final _gap = _Spring(omega: 55, damping: 0.8);
  final _jaw = _Spring(omega: 45, damping: 0.8);
  double _press = 0;
  double _level = 0;
  double _lastVoiced = double.negativeInfinity;
  double _silenceStart = double.negativeInfinity;
  double _breathUntil = double.negativeInfinity;
  bool _breathTaken = false;
  double _lastHeard = double.negativeInfinity;
  LipSyncFrame _frame = LipSyncFrame.rest;

  /// The last frame produced.
  LipSyncFrame get frame => _frame;

  /// Advances [dt] seconds with nothing playing: the mouth settles to rest.
  LipSyncFrame idle(double dt) {
    final step = dt.clamp(0.0, 0.1);
    _blendWeights(const {}, step);
    _press += -_press * (1 - math.exp(-step / 0.04));
    _level += -_level * (1 - math.exp(-step / 0.03));
    final g = _gap.step(0, step);
    final j = _jaw.step(0, step);
    return _frame = LipSyncFrame(
      level: _level,
      gap: math.max(0, g),
      jaw: math.max(0, j),
      width: 0,
      round: 0,
      press: _press,
      viseme: Viseme.rest,
    );
  }

  /// Advances [dt] seconds to the moment [heard] (audio clock) is heard.
  LipSyncFrame update(SpeechTimeline timeline, double heard, double dt) {
    final step = dt.clamp(0.0, 0.1);
    final t = heard + lead;
    // A new audio context restarts its clock: forget the old times.
    if (t < _lastHeard - 0.5) _resetClock();
    _lastHeard = t;
    _learn(timeline, t);

    final now = timeline.at(t);
    final voiced = now != null && _isVoiced(now);
    if (voiced) _lastVoiced = t;
    final speaking = t - _lastVoiced < 0.35;

    // Pauses: note when silence began; breathe once if it lasts.
    if (!voiced && _silenceStart < _lastVoiced) {
      _silenceStart = t;
      _breathTaken = false;
    }
    if (!voiced &&
        !_breathTaken &&
        _lastVoiced.isFinite &&
        t - _silenceStart > 0.4) {
      _breathTaken = true;
      _breathUntil = t + 0.35;
    }

    final loud = voiced ? _loudness(now.db) : 0.0;
    _level += (loud - _level) * (1 - math.exp(-step / 0.03));
    final targets = voiced ? _shapeWeights(now) : const <Viseme, double>{};
    _blendWeights(targets, step);

    final press = voiced || speaking ? _closure(timeline, t) : 0.0;
    final pressTau = press > _press ? 0.025 : 0.04;
    _press += (press - _press) * (1 - math.exp(-step / pressTau));

    var gap = 0.0;
    var jaw = 0.0;
    var width = 0.0;
    var round = 0.0;
    for (final MapEntry(key: v, value: w) in _weights.entries) {
      gap += w * v.gap;
      jaw += w * v.jaw;
      width += w * v.widthChange;
      round += w * v.round;
    }
    final articulation = 0.35 + 0.65 * loud;
    gap *= voiced ? articulation * (1 - _press) : 0;
    jaw *= voiced ? (0.3 + 0.7 * loud) * (1 - 0.7 * _press) : 0;
    width -= 0.03 * _press;
    if (t < _breathUntil) gap = math.max(gap, 0.035);

    final g = _gap.step(gap, step);
    final j = _jaw.step(jaw, step);
    return _frame = LipSyncFrame(
      level: _level,
      gap: math.max(0, g),
      jaw: math.max(0, j),
      width: width,
      round: round.clamp(0, 1),
      press: _press,
      viseme: _dominant(g),
      speaking: speaking,
    );
  }

  void _resetClock() {
    _lastStatTime = double.negativeInfinity;
    _lastVoiced = double.negativeInfinity;
    _silenceStart = double.negativeInfinity;
    _breathUntil = double.negativeInfinity;
    _breathTaken = false;
  }

  /// Closes the mouth at once and forgets the clock (not the voice).
  void reset() {
    _resetClock();
    _lastHeard = double.negativeInfinity;
    for (final v in _weights.keys) {
      _weights[v] = 0;
    }
    _gap.reset();
    _jaw.reset();
    _press = 0;
    _level = 0;
    _frame = LipSyncFrame.rest;
  }

  bool _isVoiced(SpeechFeatures f) => f.db > math.max(-55, _typicalDb - 30);

  double _loudness(double db) {
    final x = ((db - (_typicalDb - 24)) / 28).clamp(0.0, 1.0);
    return math.pow(x, 0.7).toDouble();
  }

  /// Updates the speaker statistics with frames up to [t], once each.
  void _learn(SpeechTimeline timeline, double t) {
    for (final f in timeline.range(_lastStatTime + 1e-6, t)) {
      _lastStatTime = f.time;
      if (!_isVoiced(f)) continue;
      _typicalDb += (f.db - _typicalDb) * 0.01;
      if (f.openness > 0 && f.spread > 0 && f.hiss < 1) {
        _openness.add(math.log(f.openness) / math.ln2);
        _spread.add(math.log(f.spread) / math.ln2);
        _nasal.add(_log2(f.nasal));
      }
    }
  }

  /// Soft membership of each shape for one frame.
  Map<Viseme, double> _shapeWeights(SpeechFeatures f) {
    final fricative = _sigmoid((f.hiss - 1.2) / 0.3);
    if (f.openness <= 0 || f.spread <= 0) {
      return {Viseme.fricative: math.max(fricative, 0.5)};
    }
    final z1 = _openness.z(math.log(f.openness) / math.ln2);
    final z2 = _spread.z(math.log(f.spread) / math.ln2);
    // F1 decides how open: with a high voice's sparse harmonics it cannot
    // tell e from i or o from u, but it clearly marks the open a. F2 does
    // the rest: front (spread) or back (rounded), and how far.
    final open = _sigmoid((z1 - 0.6) / 0.25);
    final front = _sigmoid((z2 + 0.35) / 0.3);
    // u is rarer than i in Spanish and English: ask more of it.
    final extreme = z2 >= 0
        ? _sigmoid((z2 - 1.0) / 0.2)
        : _sigmoid((-z2 - 1.25) / 0.2);
    final vowel = 1 - fricative;
    final rest = 1 - open;
    return {
      Viseme.a: open * vowel,
      Viseme.e: rest * front * (1 - extreme) * vowel,
      Viseme.i: rest * front * extreme * vowel,
      Viseme.o: rest * (1 - front) * (1 - extreme) * vowel,
      Viseme.u: rest * (1 - front) * extreme * vowel,
      Viseme.fricative: fricative,
    };
  }

  void _blendWeights(Map<Viseme, double> targets, double dt) {
    for (final v in _weights.keys) {
      final target = targets[v] ?? 0;
      final current = _weights[v]!;
      final tau = target > current ? v.attack : v.release;
      _weights[v] = current + (target - current) * (1 - math.exp(-dt / tau));
    }
  }

  /// How strongly the lips should be pressed at [t], looking up to 50 ms
  /// ahead so they close before the sound does.
  ///
  /// A dip in level inside a phrase is a stop closure: the sound falls 10 dB
  /// or more below the vowels on both sides. A stop released with a hiss
  /// (t, d) is a tongue closure and presses only lightly. Telling p from t
  /// or k by ear needs more than these features (measured on a labelled
  /// consonant corpus: F2 transitions did not separate them), so every stop
  /// brings the lips together and the press is kept moderate.
  double _closure(SpeechTimeline timeline, double t) {
    var best = 0.0;
    final gate = math.max(-55, _typicalDb - 30);
    for (final f in timeline.range(t - 0.01, t + 0.05)) {
      // A sibilant is a dip in level too, but with hiss: not a closure. (In
      // the near-silence of a real closure the ratio means nothing.)
      if (f.hiss > 0.8 && f.db > gate) continue;
      final before = timeline.range(f.time - 0.09, f.time - 0.005).toList();
      final after = timeline.range(f.time + 0.005, f.time + 0.09).toList();
      final leftPeak = _peak(before);
      final rightPeak = _peak(after);
      if (leftPeak <= gate || rightPeak <= gate) continue;
      final dip = math.min(leftPeak, rightPeak) - f.db;
      var c = ((dip - 10) / 8).clamp(0.0, 1.0);
      if (c == 0) continue;
      final release = after.where((x) => x.db > f.db + 8).firstOrNull;
      if (release != null && release.hiss > 0.15) c *= 0.3;
      best = math.max(best, c * 0.6);
    }
    return best;
  }

  static double _peak(Iterable<SpeechFeatures> frames) =>
      frames.fold(double.negativeInfinity, (m, f) => math.max(m, f.db));

  Viseme _dominant(double gap) {
    if (_press > 0.5 || gap < 0.01) return Viseme.rest;
    var best = Viseme.rest;
    var weight = 0.15;
    for (final MapEntry(key: v, value: w) in _weights.entries) {
      if (w > weight) {
        best = v;
        weight = w;
      }
    }
    return best;
  }

  static double _sigmoid(double x) => 1 / (1 + math.exp(-x));

  static double _log2(double x) => math.log(math.max(x, 1e-4)) / math.ln2;
}

/// A spring towards a target: quick, slightly underdamped, so the jaw
/// settles like a jaw instead of sliding exponentially.
class _Spring {
  _Spring({required this.omega, required this.damping});

  final double omega;
  final double damping;
  double _x = 0;
  double _v = 0;

  double step(double target, double dt) {
    // Small fixed sub-steps keep the integration stable at any frame rate.
    var left = dt;
    while (left > 1e-6) {
      final h = math.min(left, 0.004);
      final a = omega * omega * (target - _x) - 2 * damping * omega * _v;
      _v += a * h;
      _x += _v * h;
      left -= h;
    }
    return _x;
  }

  void reset() {
    _x = 0;
    _v = 0;
  }
}

/// A running mean and deviation that starts from a prior and then follows
/// the speaker: a plain average for the first samples, then an exponential
/// one over the last few hundred frames (a few seconds of speech).
class _RunningStat {
  _RunningStat(this._mean, {required double deviation})
    : _variance = deviation * deviation;

  static const _priorWeight = 5;
  static const _memory = 400;
  static const _minDeviation = 0.12;

  double _mean;
  double _variance;
  int _count = 0;

  void add(double x) {
    _count++;
    final alpha = math.max(1 / (_count + _priorWeight), 1 / _memory);
    final delta = x - _mean;
    _mean += alpha * delta;
    _variance = (1 - alpha) * (_variance + alpha * delta * delta);
  }

  double z(double x) =>
      (x - _mean) / math.max(math.sqrt(_variance), _minDeviation);
}
