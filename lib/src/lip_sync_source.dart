import 'dart:typed_data';

/// A chunk of speech and when it will be heard.
class SpeechChunk {
  /// Creates a chunk.
  const SpeechChunk({
    required this.samples,
    required this.startTime,
    required this.sampleRate,
  });

  /// Mono samples in -1..1.
  final Float32List samples;

  /// When the first sample is heard, on the source's audio clock (seconds).
  final double startTime;

  /// Samples per second.
  final int sampleRate;
}

/// The speech the avatar lip-syncs to.
///
/// Lip sync works ahead of the sound: [chunks] arrive when the playback
/// schedules them (before they are heard), and [audibleTime] says which
/// moment of them reaches the listener right now. Implement it over your own
/// audio player, so this package does not depend on any audio API.
abstract interface class LipSyncSource {
  /// Every chunk as soon as it is scheduled.
  Stream<SpeechChunk> get chunks;

  /// Audio-clock times at which playback was cut (barge-in): nothing after
  /// them will be heard.
  Stream<double> get flushes;

  /// The audio-clock time being heard right now, or `null` while unknown.
  double? get audibleTime;
}
