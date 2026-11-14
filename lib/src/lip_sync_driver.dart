import 'dart:async';

import 'package:avatar_lipsync/src/lip_sync_analyzer.dart';
import 'package:avatar_lipsync/src/lip_sync_source.dart';
import 'package:avatar_lipsync/src/speech_timeline.dart';

/// Connects a [LipSyncSource] to a [LipSyncAnalyzer].
///
/// Scheduled chunks are analysed into a [SpeechTimeline] as they arrive
/// (ahead of playback), flushes cut it, and every [tick] asks the analyzer
/// for the mouth at the moment being heard. Both avatars drive it from their
/// own `Ticker`.
class LipSyncDriver {
  /// Starts listening to [source].
  LipSyncDriver(this.source, {LipSyncAnalyzer? analyzer})
    : analyzer = analyzer ?? LipSyncAnalyzer() {
    _subscriptions = [
      source.chunks.listen(_onChunk),
      source.flushes.listen(_onFlush),
    ];
  }

  /// Where the speech comes from.
  final LipSyncSource source;

  /// Turns the timeline into mouth frames.
  final LipSyncAnalyzer analyzer;

  /// The analysed speech.
  final timeline = SpeechTimeline();

  late final List<StreamSubscription<Object>> _subscriptions;
  double _analysisMs = 0;
  double _tickMs = 0;

  /// Average time spent analysing one scheduled chunk, in milliseconds.
  double get analysisMs => _analysisMs;

  /// Average time one [tick] takes, in milliseconds.
  double get tickMs => _tickMs;

  void _onChunk(SpeechChunk chunk) {
    final started = DateTime.now().microsecondsSinceEpoch;
    timeline.add(chunk);
    final spent = (DateTime.now().microsecondsSinceEpoch - started) / 1000;
    _analysisMs = _analysisMs * 0.9 + spent * 0.1;
  }

  // The playback fades the cut audio out over ~12 ms; the mouth closes on
  // its own springs once the timeline has nothing left to say.
  void _onFlush(double time) => timeline.flush(time);

  /// Advances [dt] seconds and returns the mouth for this frame.
  LipSyncFrame tick(double dt) {
    final started = DateTime.now().microsecondsSinceEpoch;
    final heard = source.audibleTime;
    final LipSyncFrame frame;
    if (heard == null || !heard.isFinite) {
      // No clock (playback not started or stopped): settle to rest.
      frame = analyzer.idle(dt);
    } else {
      frame = analyzer.update(timeline, heard, dt);
      timeline.prune(heard - 1);
    }
    final spent = (DateTime.now().microsecondsSinceEpoch - started) / 1000;
    _tickMs = _tickMs * 0.9 + spent * 0.1;
    return frame;
  }

  /// Stops listening to the source.
  Future<void> dispose() async {
    for (final s in _subscriptions) {
      await s.cancel();
    }
  }
}
