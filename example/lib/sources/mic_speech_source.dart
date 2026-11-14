import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:avatar_lipsync/avatar_lipsync.dart';
import 'package:web/web.dart' as web;

/// A [LipSyncSource] over the microphone: the avatar mirrors whoever talks.
///
/// An AudioWorklet copies the microphone's samples in 20 ms chunks; nothing
/// is played back, so there is no echo. Each chunk is stamped with the time
/// it was captured on the audio clock, and [audibleTime] trails that clock
/// by [delay], enough for a chunk to arrive and be analysed before the
/// mouth reaches it.
class MicSpeechSource implements LipSyncSource {
  /// Creates the source. Call [start] from a user gesture.
  MicSpeechSource({this.delay = 0.08});

  /// How far the mouth trails the voice, in seconds.
  final double delay;

  final _chunks = StreamController<SpeechChunk>.broadcast();
  final _flushes = StreamController<double>.broadcast();
  web.AudioContext? _context;
  web.MediaStream? _stream;
  web.AudioWorkletNode? _tap;

  /// Whether the microphone is on.
  bool get isListening => _context != null;

  @override
  Stream<SpeechChunk> get chunks => _chunks.stream;

  @override
  Stream<double> get flushes => _flushes.stream;

  @override
  double? get audibleTime {
    final context = _context;
    if (context == null || context.state != 'running') return null;
    return context.currentTime - delay;
  }

  /// Asks for the microphone and starts listening. Throws if the browser or
  /// the person refuses.
  Future<void> start() async {
    if (isListening) return;
    // Create and resume the audio context first, while the click that
    // called start() still counts as a user gesture: after the permission
    // prompt it may not, and resume() would wait forever.
    final context = web.AudioContext();
    final resumed = context.resume().toDart;
    final web.MediaStream stream;
    try {
      stream = await web.window.navigator.mediaDevices
          .getUserMedia(
            web.MediaStreamConstraints(
              audio: {
                'echoCancellation': true,
                'noiseSuppression': true,
                'autoGainControl': true,
              }.jsify()!,
            ),
          )
          .toDart;
      await resumed;
      final module = web.URL.createObjectURL(
        web.Blob(
          [_worklet.toJS].toJS,
          web.BlobPropertyBag(type: 'text/javascript'),
        ),
      );
      try {
        await context.audioWorklet.addModule(module).toDart;
      } finally {
        web.URL.revokeObjectURL(module);
      }
    } catch (_) {
      await context.close().toDart;
      rethrow;
    }
    final tap = web.AudioWorkletNode(context, 'lipsync-tap');
    final sampleRate = context.sampleRate.round();
    tap.port.onmessage = (web.MessageEvent event) {
      final data = event.data! as JSObject;
      final samples = (data['samples']! as JSFloat32Array).toDart;
      final end = (data['end']! as JSNumber).toDartDouble;
      _chunks.add(
        SpeechChunk(
          samples: samples,
          startTime: end - samples.length / sampleRate,
          sampleRate: sampleRate,
        ),
      );
    }.toJS;
    context.createMediaStreamSource(stream).connect(tap);
    // The tap outputs silence; it is connected only so the graph pulls it.
    tap.connect(context.destination);
    _context = context;
    _stream = stream;
    _tap = tap;
  }

  /// Turns the microphone off; the mouth closes.
  Future<void> stop() async {
    final context = _context;
    if (context == null) return;
    _flushes.add(context.currentTime);
    _tap?.disconnect();
    final tracks = _stream?.getTracks().toDart ?? const [];
    for (final track in tracks) {
      track.stop();
    }
    _context = null;
    _stream = null;
    _tap = null;
    await context.close().toDart;
  }

  /// Stops listening and closes the streams.
  Future<void> dispose() async {
    await stop();
    await _chunks.close();
    await _flushes.close();
  }
}

/// Copies the input in 20 ms chunks (at the context's rate) and posts each
/// one with the audio-clock time of its last sample.
const _worklet = '''
class LipSyncTap extends AudioWorkletProcessor {
  constructor() {
    super();
    this.size = Math.round(sampleRate * 0.02);
    this.buffer = new Float32Array(this.size);
    this.filled = 0;
  }
  process(inputs) {
    const channel = inputs[0] && inputs[0][0];
    if (!channel) return true;
    for (let i = 0; i < channel.length; i++) {
      this.buffer[this.filled++] = channel[i];
      if (this.filled === this.size) {
        const end = currentTime + (i + 1) / sampleRate;
        this.port.postMessage({ samples: this.buffer, end }, [this.buffer.buffer]);
        this.buffer = new Float32Array(this.size);
        this.filled = 0;
      }
    }
    return true;
  }
}
registerProcessor('lipsync-tap', LipSyncTap);
''';
