import 'dart:math' as math;

import 'package:avatar_lipsync/src/lip_sync_analyzer.dart';

/// Everything about the face that is not the mouth, for one frame.
class AvatarPose {
  /// Creates a pose.
  const AvatarPose({
    this.blink = 0,
    this.roll = 0,
    this.dx = 0,
    this.dy = 0,
    this.scale = 1,
    this.brow = 0,
    this.gazeX = 0,
    this.gazeY = 0,
  });

  /// Eyelid closure, 0 (open) .. 1 (closed).
  final double blink;

  /// Head roll in radians (positive tilts clockwise).
  final double roll;

  /// Head offset as a fraction of the face height.
  final double dx;

  /// Head offset as a fraction of the face height (positive is down: a nod).
  final double dy;

  /// Breathing scale around 1.
  final double scale;

  /// Brow raise, 0..1.
  final double brow;

  /// Gaze, -1..1 of the small range the irises move (about 10°).
  final double gazeX;

  /// Gaze, -1..1 (positive looks down).
  final double gazeY;
}

/// The living part of the avatar, from conversation research:
/// - blinks: about 26 a minute while talking and 17 at rest, intervals drawn
///   from a log-normal distribution, more likely right after a phrase ends;
///   70 ms to close, 150 ms to open; some half and double blinks;
/// - head: slow layered sway under 1°, breathing at 14 a minute, and a small
///   nod (2–3°) on stressed syllables;
/// - brows: a short raise on a stressed syllable, at most every 1.5 s;
/// - gaze: the speaker looks away (up or aside) for 0.5–2 s at the start of
///   about half the phrases and holds eye contact otherwise, with tiny
///   saccades; a listener holds it longer.
///
/// Pure Dart and deterministic for a given `seed`, so tests can step it.
class AvatarMotion {
  /// Creates the motion. [reduced] keeps only blinks and the mouth.
  AvatarMotion({int seed = 7, this.reduced = false})
    : _random = math.Random(seed) {
    _nextBlink = _blinkInterval(talking: false);
  }

  /// Respect the platform's reduced-motion setting.
  bool reduced;

  final math.Random _random;
  double _time = 0;
  double _nextBlink = 3;
  double _blinkAt = -1;
  double _blinkDepth = 1;
  bool _doubleBlink = false;
  bool _wasSpeaking = false;
  double _silence = 0;
  double _lastLevel = 0;
  double _nod = 0;
  double _nodVelocity = 0;
  double _nodCooldown = 0;
  double _brow = 0;
  double _browCooldown = 0;
  double _gazeX = 0;
  double _gazeY = 0;
  double _gazeTargetX = 0;
  double _gazeTargetY = 0;
  double _gazeHold = 0;
  double _nextSaccade = 1;

  /// Advances [dt] seconds, reacting to the mouth `frame`.
  AvatarPose update(double dt, LipSyncFrame frame) {
    final step = dt.clamp(0.0, 0.1);
    _time += step;
    final speaking = frame.speaking;
    final phraseStart = speaking && !_wasSpeaking && _silence > 0.4;
    final phraseEnd = !speaking && _wasSpeaking;
    _silence = speaking ? 0 : _silence + step;
    _wasSpeaking = speaking;

    final blink = _blinkAmount(step, talking: speaking, phraseEnd: phraseEnd);
    if (reduced) return AvatarPose(blink: blink);

    // A stressed syllable is a fast rise in loudness.
    final rise = (frame.level - _lastLevel) / math.max(step, 1e-3);
    _lastLevel = frame.level;
    _nodCooldown -= step;
    _browCooldown -= step;
    if (rise > 5 && frame.level > 0.45) {
      if (_nodCooldown <= 0) {
        _nodVelocity += 16;
        _nodCooldown = 0.6;
      }
      if (_browCooldown <= 0 && _random.nextDouble() < 0.5) {
        _brow = 1;
        _browCooldown = 1.5;
      }
    }
    // The nod is a damped spring kicked by stress: down, then back. Small
    // fixed sub-steps keep it stable when frames come slowly.
    for (var left = step; left > 1e-6; left -= 0.004) {
      final h = math.min(left, 0.004);
      _nodVelocity += (-_nod * 120 - _nodVelocity * 14) * h;
      _nod += _nodVelocity * h;
    }
    _brow *= math.exp(-step / 0.3);

    _updateGaze(step, speaking: speaking, phraseStart: phraseStart);
    final t = _time;
    return AvatarPose(
      blink: blink,
      roll:
          0.008 * math.sin(t * 0.43) +
          0.005 * math.sin(t * 1.17 + 1) +
          0.002 * math.sin(t * 2.3 + 2),
      dx: 0.003 * math.sin(t * 0.31 + 2) + 0.0015 * math.sin(t * 0.87),
      dy:
          0.003 * math.sin(t * 0.52) +
          0.0015 * math.sin(t * 1.4 + 0.5) +
          0.02 * _nod.clamp(-1.0, 1.0),
      scale: 1 + 0.004 * math.sin(t * 2 * math.pi / 4.3),
      brow: _brow,
      gazeX: _gazeX,
      gazeY: _gazeY,
    );
  }

  /// A log-normal interval with the mean blink gap for the situation.
  double _blinkInterval({required bool talking}) {
    final mean = talking ? 60 / 26 : 60 / 17;
    const sigma = 0.5;
    final normal =
        math.sqrt(-2 * math.log(1 - _random.nextDouble())) *
        math.cos(2 * math.pi * _random.nextDouble());
    return mean * math.exp(sigma * normal - sigma * sigma / 2);
  }

  double _blinkAmount(
    double dt, {
    required bool talking,
    required bool phraseEnd,
  }) {
    _nextBlink -= dt;
    if (phraseEnd && _blinkAt < 0 && _random.nextDouble() < 0.4) {
      _nextBlink = math.min(_nextBlink, 0.1 + _random.nextDouble() * 0.15);
    }
    if (_nextBlink <= 0 && _blinkAt < 0) {
      _blinkAt = 0;
      final kind = _random.nextDouble();
      _blinkDepth = kind < 0.08 ? 0.6 : 1;
      _doubleBlink = kind > 0.92;
      _nextBlink = _blinkInterval(talking: talking);
    }
    if (_blinkAt < 0) return 0;
    _blinkAt += dt;
    const close = 0.07;
    const hold = 0.02;
    const open = 0.15;
    final t = _blinkAt;
    double amount;
    if (t < close) {
      final x = t / close;
      amount = x * x;
    } else if (t < close + hold) {
      amount = 1;
    } else if (t < close + hold + open) {
      final x = 1 - (t - close - hold) / open;
      amount = 1 - (1 - x) * (1 - x);
    } else {
      amount = 0;
      _blinkAt = -1;
      if (_doubleBlink) {
        _doubleBlink = false;
        _nextBlink = 0.08;
      }
    }
    return amount * _blinkDepth;
  }

  void _updateGaze(
    double dt, {
    required bool speaking,
    required bool phraseStart,
  }) {
    _gazeHold -= dt;
    _nextSaccade -= dt;
    if (phraseStart && _random.nextDouble() < 0.5) {
      // Thinking while starting to speak: up or aside, 5–10°.
      final side = _random.nextBool() ? 1 : -1;
      _gazeTargetX = side * (0.4 + _random.nextDouble() * 0.5);
      _gazeTargetY = -(0.3 + _random.nextDouble() * 0.5);
      _gazeHold = 0.5 + _random.nextDouble() * 1.5;
    } else if (_gazeHold <= 0 && _nextSaccade <= 0) {
      // Back to the listener, with a tiny saccade around the eyes.
      final range = speaking ? 0.12 : 0.06;
      _gazeTargetX = (_random.nextDouble() * 2 - 1) * range;
      _gazeTargetY = (_random.nextDouble() * 2 - 1) * range * 0.6;
      _nextSaccade = 0.6 + _random.nextDouble() * 1.6;
    }
    // Saccades land in ~30 ms.
    final alpha = 1 - math.exp(-dt / 0.03);
    _gazeX += (_gazeTargetX - _gazeX) * alpha;
    _gazeY += (_gazeTargetY - _gazeY) * alpha;
  }
}
