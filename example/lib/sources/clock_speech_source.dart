import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:avatar_lipsync/avatar_lipsync.dart';

/// The smallest useful [LipSyncSource]: it plays nothing out loud and keeps
/// time with a [Stopwatch]. Handy for tests, previews and platforms where
/// you do not have the audio samples at hand.
///
/// With a real player, [audibleTime] must come from the player's own clock
/// (see `WebAudioSpeechSource`).
class ClockSpeechSource implements LipSyncSource {
  final _clock = Stopwatch()..start();
  final _chunks = StreamController<SpeechChunk>.broadcast();
  final _flushes = StreamController<double>.broadcast();

  @override
  Stream<SpeechChunk> get chunks => _chunks.stream;

  @override
  Stream<double> get flushes => _flushes.stream;

  @override
  double? get audibleTime => _clock.elapsedMicroseconds / 1e6;

  /// "Plays" [samples] from now on, in 40 ms chunks.
  void speak(Float32List samples, int sampleRate) {
    final start = audibleTime! + 0.05;
    final size = (sampleRate * 0.04).round();
    for (var i = 0; i < samples.length; i += size) {
      _chunks.add(
        SpeechChunk(
          samples: Float32List.sublistView(
            samples,
            i,
            math.min(i + size, samples.length),
          ),
          startTime: start + i / sampleRate,
          sampleRate: sampleRate,
        ),
      );
    }
  }

  /// Cuts the speech now: the mouth closes.
  void stop() => _flushes.add(audibleTime!);

  /// Closes the streams.
  Future<void> dispose() async {
    await _chunks.close();
    await _flushes.close();
  }
}
