import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:avatar_lipsync/avatar_lipsync.dart';
import 'package:web/web.dart' as web;

/// A [LipSyncSource] over Web Audio: it plays speech out loud and tells the
/// avatar what is being heard.
///
/// The pattern works for any player, including streamed speech (OpenAI
/// Realtime, Gemini Live, any TTS):
/// 1. When a chunk is **scheduled** (before it sounds), emit it on [chunks]
///    with the time it will start, on the player's clock.
/// 2. [audibleTime] is that same clock now, minus the output latency.
/// 3. When playback is cut (the user interrupts), emit the cut time on
///    [flushes].
class WebAudioSpeechSource implements LipSyncSource {
  /// How far ahead of now a chunk that arrives after a gap is scheduled, so
  /// the next ones join it without a hole.
  static const _lead = 0.08;

  /// Fade on [stop], short enough to sound like a cut but without a click.
  static const _fade = 0.012;

  final _context = web.AudioContext();
  final _chunks = StreamController<SpeechChunk>.broadcast();
  final _flushes = StreamController<double>.broadcast();
  final _playing = <web.AudioBufferSourceNode>[];
  web.GainNode? _gain;
  double _queueEnd = 0;

  @override
  Stream<SpeechChunk> get chunks => _chunks.stream;

  @override
  Stream<double> get flushes => _flushes.stream;

  @override
  double? get audibleTime {
    if (_context.state != 'running') return null;
    return _context.currentTime - _latency;
  }

  /// Output latency in seconds. Safari has no `outputLatency`, so read each
  /// part only where the browser has it.
  double get _latency {
    final context = _context as JSObject;
    var latency = 0.0;
    if (context.has('baseLatency')) latency += _context.baseLatency;
    if (context.has('outputLatency')) latency += _context.outputLatency;
    return latency;
  }

  /// Queues mono [samples] right after whatever is already playing.
  ///
  /// Call it once per chunk as a stream delivers them, or once with a whole
  /// clip (it is split into 40 ms chunks).
  Future<void> play(Float32List samples, int sampleRate) async {
    // Browsers start audio only after a user gesture.
    if (_context.state != 'running') await _context.resume().toDart;
    var at = math.max(_queueEnd, _context.currentTime + _lead);
    final size = (sampleRate * 0.04).round();
    for (var i = 0; i < samples.length; i += size) {
      final chunk = Float32List.sublistView(
        samples,
        i,
        math.min(i + size, samples.length),
      );
      _schedule(chunk, sampleRate, at);
      at += chunk.length / sampleRate;
    }
    _queueEnd = at;
  }

  /// Queues little-endian 16-bit PCM, as realtime voice APIs stream it
  /// (base64-decoded first).
  Future<void> playPcm16(Uint8List bytes, int sampleRate) =>
      play(pcm16ToSamples(bytes), sampleRate);

  /// Decodes an audio file (WAV, MP3, OGG…) and plays its first channel.
  Future<void> playFile(Uint8List bytes) async {
    await _context.resume().toDart;
    final buffer = await _context.decodeAudioData(bytes.buffer.toJS).toDart;
    await play(buffer.getChannelData(0).toDart, buffer.sampleRate.round());
  }

  /// Cuts playback now (barge-in): a quick fade, then the mouth closes.
  void stop() {
    final now = _context.currentTime;
    final gain = _gain;
    if (gain != null) {
      gain.gain
        ..cancelScheduledValues(now)
        ..setValueAtTime(gain.gain.value, now)
        ..linearRampToValueAtTime(0, now + _fade);
      // Free the faded node once it is silent.
      // A lambda, not a tear-off: JS interop members cannot be torn off.
      // ignore: unnecessary_lambdas
      Timer(const Duration(milliseconds: 100), () => gain.disconnect());
    }
    for (final node in _playing) {
      node.stop(now + _fade);
    }
    _playing.clear();
    // The next audio gets a fresh gain node, untouched by this fade.
    _gain = null;
    _queueEnd = 0;
    _flushes.add(now);
  }

  web.GainNode get _output =>
      _gain ??= _context.createGain()..connect(_context.destination);

  void _schedule(Float32List samples, int sampleRate, double at) {
    final buffer = _context.createBuffer(1, samples.length, sampleRate)
      ..copyToChannel(samples.toJS, 0);
    final node = _context.createBufferSource();
    _playing.add(node);
    node
      ..buffer = buffer
      ..onended = (web.Event _) {
        _playing.remove(node);
      }.toJS
      ..connect(_output)
      ..start(at);
    // Tell the avatar now, ahead of the sound.
    _chunks.add(
      SpeechChunk(samples: samples, startTime: at, sampleRate: sampleRate),
    );
  }

  /// Releases the audio context.
  Future<void> dispose() async {
    stop();
    await _chunks.close();
    await _flushes.close();
    await _context.close().toDart;
  }
}
