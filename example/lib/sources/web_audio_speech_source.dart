import 'dart:async';
import 'dart:js_interop';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:avatar_lipsync/avatar_lipsync.dart';
import 'package:web/web.dart' as web;

/// A [LipSyncSource] over Web Audio: it plays speech out loud and tells the
/// avatar what is being heard.
///
/// The pattern works for any player, including streamed speech (TTS, voice
/// agents):
/// 1. When a chunk is **scheduled** (before it sounds), emit it on [chunks]
///    with the time it will start, on the player's clock.
/// 2. [audibleTime] is that same clock now, minus the output latency.
/// 3. When playback is cut (the user interrupts), emit the cut time on
///    [flushes].
class WebAudioSpeechSource implements LipSyncSource {
  final _context = web.AudioContext();
  final _chunks = StreamController<SpeechChunk>.broadcast();
  final _flushes = StreamController<double>.broadcast();
  final _playing = <web.AudioBufferSourceNode>[];
  double _queueEnd = 0;

  @override
  Stream<SpeechChunk> get chunks => _chunks.stream;

  @override
  Stream<double> get flushes => _flushes.stream;

  @override
  double? get audibleTime {
    if (_context.state != 'running') return null;
    return _context.currentTime - _context.outputLatency;
  }

  /// Queues mono [samples] after whatever is already playing, in 40 ms
  /// chunks, as a stream would deliver them.
  Future<void> play(Float32List samples, int sampleRate) async {
    // Browsers start audio only after a user gesture.
    await _context.resume().toDart;
    var at = math.max(_queueEnd, _context.currentTime + 0.1);
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

  /// Decodes an audio file (WAV, MP3, OGG…) and plays its first channel.
  Future<void> playFile(Uint8List bytes) async {
    await _context.resume().toDart;
    final buffer = await _context.decodeAudioData(bytes.buffer.toJS).toDart;
    await play(buffer.getChannelData(0).toDart, buffer.sampleRate.round());
  }

  /// Cuts playback now; the mouth closes.
  void stop() {
    for (final node in _playing) {
      node.stop();
    }
    _playing.clear();
    _queueEnd = 0;
    _flushes.add(_context.currentTime);
  }

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
      ..connect(_context.destination)
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
