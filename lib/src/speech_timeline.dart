import 'dart:math' as math;
import 'dart:typed_data';

import 'package:avatar_lipsync/src/lip_sync_source.dart';

/// What the voice is doing during one 25 ms window, centred at [time].
class SpeechFeatures {
  /// Creates the features of one window.
  const SpeechFeatures({
    required this.time,
    required this.db,
    required this.openness,
    required this.spread,
    required this.hiss,
    required this.nasal,
    required this.flux,
  });

  /// Centre of the window on the audio clock (seconds).
  final double time;

  /// RMS level in dBFS.
  final double db;

  /// First-formant estimate (Hz): how open the jaw is. 0 when unvoiced.
  final double openness;

  /// Second-formant estimate (Hz): the centre of the 600 Hz–3.2 kHz energy
  /// away from F1. High for spread lips (e, i), low for rounded ones (o, u).
  /// 0 when unvoiced.
  final double spread;

  /// Energy above 4 kHz over the voiced band: high for s, f, ch.
  final double hiss;

  /// Energy under 400 Hz over 400 Hz–4 kHz: high for m and n.
  final double nasal;

  /// Rise of the 2–8 kHz energy since the previous window: plosive bursts.
  final double flux;
}

/// Speech features along the audio clock, computed as chunks are scheduled.
///
/// Every 10 ms a 25 ms Hann window goes through a 1024-point FFT. Chunks that
/// follow each other on the clock are analysed as one stream, so windows
/// straddle chunk boundaries; a chunk after a gap starts a new stream. Frames
/// a flush cancels are dropped, and old ones are pruned.
class SpeechTimeline {
  /// Creates an empty timeline.
  SpeechTimeline({this.hopSeconds = 0.01, this.windowSeconds = 0.025});

  /// Time between frames.
  final double hopSeconds;

  /// Analysis window length.
  final double windowSeconds;

  /// A minute of frames at most.
  static const _maxFrames = 6000;

  final List<SpeechFeatures> _frames = [];
  Float32List _pending = Float32List(0);
  double _pendingStart = 0;
  int _rate = 0;
  Float64List? _previousHigh;
  int _fftSize = 1024;
  Float64List _re = Float64List(1024);
  Float64List _im = Float64List(1024);
  Float64List _window = Float64List(0);

  /// Every frame still held, in time order.
  List<SpeechFeatures> get frames => _frames;

  /// Analyses [chunk] and appends its frames.
  void add(SpeechChunk chunk) {
    if (chunk.samples.isEmpty) return;
    final pendingEnd = _rate == 0
        ? double.nan
        : _pendingStart + _pending.length / _rate;
    final contiguous =
        chunk.sampleRate == _rate &&
        (chunk.startTime - pendingEnd).abs() < 0.002;
    if (!contiguous) {
      _rate = chunk.sampleRate;
      _pending = Float32List(0);
      _pendingStart = chunk.startTime;
      _previousHigh = null;
      _window = _hann((windowSeconds * _rate).round());
      // The FFT holds the whole window, zero-padded: ~23 Hz bins at 24 kHz.
      _fftSize = 1024;
      while (_fftSize < _window.length) {
        _fftSize *= 2;
      }
      if (_re.length != _fftSize) {
        _re = Float64List(_fftSize);
        _im = Float64List(_fftSize);
      }
    }
    // A chunk scheduled earlier than the last frame (a reset clock) replaces
    // the frames it overlaps.
    _dropFrom(chunk.startTime);
    _pending = Float32List(_pending.length + chunk.samples.length)
      ..setAll(0, _pending)
      ..setAll(_pending.length, chunk.samples);
    _analysePending();
    // Whoever reads the timeline prunes it as it plays; this bounds it when
    // nobody does (a hidden avatar, a stopped clock).
    if (_frames.length > _maxFrames) {
      _frames.removeRange(0, _frames.length - _maxFrames);
    }
  }

  /// Drops every frame after [time] (playback was cut there).
  void flush(double time) {
    _dropFrom(time);
    _pending = Float32List(0);
    _rate = 0;
    _previousHigh = null;
  }

  /// Drops frames older than [time].
  void prune(double time) {
    var keepFrom = 0;
    while (keepFrom < _frames.length && _frames[keepFrom].time < time) {
      keepFrom++;
    }
    if (keepFrom > 0) _frames.removeRange(0, keepFrom);
  }

  /// The frame nearest [time], or `null` when no frame lies within one hop
  /// (nothing is playing then).
  SpeechFeatures? at(double time) {
    final i = _indexAtOrAfter(time);
    SpeechFeatures? best;
    for (final j in [i - 1, i]) {
      if (j < 0 || j >= _frames.length) continue;
      final f = _frames[j];
      if (best == null || (f.time - time).abs() < (best.time - time).abs()) {
        best = f;
      }
    }
    if (best == null || (best.time - time).abs() > hopSeconds) return null;
    return best;
  }

  /// Frames with `from <= time <= to`.
  Iterable<SpeechFeatures> range(double from, double to) sync* {
    for (var i = _indexAtOrAfter(from); i < _frames.length; i++) {
      final f = _frames[i];
      if (f.time > to) break;
      yield f;
    }
  }

  int _indexAtOrAfter(double time) {
    var lo = 0;
    var hi = _frames.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_frames[mid].time < time) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  void _dropFrom(double time) {
    final i = _indexAtOrAfter(time);
    if (i < _frames.length) _frames.removeRange(i, _frames.length);
  }

  void _analysePending() {
    final win = _window.length;
    final hop = math.max(1, (hopSeconds * _rate).round());
    var pos = 0;
    while (pos + win <= _pending.length) {
      _frames.add(_analyse(pos, win));
      pos += hop;
    }
    if (pos > 0) {
      _pendingStart += pos / _rate;
      _pending = Float32List.sublistView(_pending, pos);
    }
  }

  SpeechFeatures _analyse(int pos, int win) {
    var sum = 0.0;
    for (var i = 0; i < _fftSize; i++) {
      if (i < win) {
        final x = _pending[pos + i];
        sum += x * x;
        _re[i] = x * _window[i];
      } else {
        _re[i] = 0;
      }
      _im[i] = 0;
    }
    _fft(_re, _im);
    final rms = math.sqrt(sum / win);
    final db = 20 * math.log(rms + 1e-9) / math.ln10;
    final hzPerBin = _rate / _fftSize;
    final bins = _fftSize ~/ 2;

    var nasalLow = 0.0;
    var mid = 0.0;
    var voiced = 0.0;
    var hiss = 0.0;
    var peak = 0.0;
    var fluxRise = 0.0;
    var fluxBase = 0.0;
    final highBand = Float64List(bins);
    for (var k = 1; k < bins; k++) {
      final hz = k * hzPerBin;
      final p = _re[k] * _re[k] + _im[k] * _im[k];
      if (hz < 400) nasalLow += p;
      if (hz >= 400 && hz < 4000) mid += p;
      if (hz >= 250 && hz <= 3200) voiced += p;
      if (hz >= 4000) hiss += p;
      if (hz >= 250 && hz <= 1000 && p > peak) peak = p;
      if (hz >= 2000 && hz <= 8000) {
        highBand[k] = p;
        final before = _previousHigh?[k] ?? p;
        fluxRise += math.max(0, p - before);
        fluxBase += before;
      }
    }
    _previousHigh = highBand;

    // F1: the lowest local maximum between 250 Hz and 1 kHz that is within
    // 6 dB of the strongest one. With a high voice the harmonics are ~200 Hz
    // apart and two can be nearly as strong; the first formant is the lower.
    var f1 = 0.0;
    for (var k = 1; k < bins - 1; k++) {
      final hz = k * hzPerBin;
      if (hz < 250) continue;
      if (hz > 1000) break;
      final p = _power(k);
      if (peak <= 0) break;
      if (p < peak / 4 || p < _power(k - 1) || p < _power(k + 1)) continue;
      var weight = 0.0;
      var weighted = 0.0;
      for (var j = k - 2; j <= k + 2; j++) {
        final q = _power(j);
        weight += q;
        weighted += q * j * hzPerBin;
      }
      if (weight > 0) f1 = weighted / weight;
      break;
    }
    // F2: the centre of the 600 Hz–3.2 kHz energy away from F1. Front
    // vowels (e, i) put it high, back ones (o, u) low.
    var f2Weight = 0.0;
    var f2Weighted = 0.0;
    for (var k = 1; k < bins; k++) {
      final hz = k * hzPerBin;
      if (hz < 600) continue;
      if (hz > 3200) break;
      if (f1 > 0 && (hz - f1).abs() < 300) continue;
      final p = _power(k);
      f2Weight += p;
      f2Weighted += p * hz;
    }
    final centre = _pendingStart + (pos + win / 2) / _rate;
    return SpeechFeatures(
      time: centre,
      db: db,
      openness: f1,
      spread: f2Weight > 0 ? f2Weighted / f2Weight : 0,
      hiss: voiced > 0 ? hiss / voiced : 0,
      nasal: mid > 0 ? nasalLow / mid : 0,
      flux: fluxBase > 0 ? fluxRise / fluxBase : 0,
    );
  }

  double _power(int k) => _re[k] * _re[k] + _im[k] * _im[k];

  static Float64List _hann(int n) => Float64List.fromList([
    for (var i = 0; i < n; i++) 0.5 - 0.5 * math.cos(2 * math.pi * i / (n - 1)),
  ]);

  static void _fft(Float64List re, Float64List im) {
    final n = re.length;
    for (var i = 1, j = 0; i < n; i++) {
      var bit = n >> 1;
      for (; (j & bit) != 0; bit >>= 1) {
        j ^= bit;
      }
      j ^= bit;
      if (i < j) {
        final tr = re[i];
        re[i] = re[j];
        re[j] = tr;
        final ti = im[i];
        im[i] = im[j];
        im[j] = ti;
      }
    }
    for (var len = 2; len <= n; len <<= 1) {
      final half = len >> 1;
      final angle = -2 * math.pi / len;
      final wr = math.cos(angle);
      final wi = math.sin(angle);
      for (var i = 0; i < n; i += len) {
        var cr = 1.0;
        var ci = 0.0;
        for (var j = 0; j < half; j++) {
          final k = i + j + half;
          final br = re[k] * cr - im[k] * ci;
          final bi = re[k] * ci + im[k] * cr;
          re[k] = re[i + j] - br;
          im[k] = im[i + j] - bi;
          re[i + j] += br;
          im[i + j] += bi;
          final next = cr * wr - ci * wi;
          ci = cr * wi + ci * wr;
          cr = next;
        }
      }
    }
  }
}
