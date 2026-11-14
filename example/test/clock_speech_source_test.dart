import 'package:avatar_lipsync/avatar_lipsync.dart';
import 'package:avatar_lipsync_example/sources/clock_speech_source.dart';
import 'package:avatar_lipsync_example/sources/synthetic_speech.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the mouth opens while the synthetic speech plays', () async {
    final source = ClockSpeechSource();
    final driver = LipSyncDriver(source);
    source.speak(syntheticSpeech(), syntheticSampleRate);

    var widest = 0.0;
    final end = DateTime.now().add(const Duration(milliseconds: 1500));
    while (DateTime.now().isBefore(end)) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
      final frame = driver.tick(1 / 60);
      if (frame.mouthOpen > widest) widest = frame.mouthOpen;
    }
    expect(widest, greaterThan(0.3));

    source.stop();
    await driver.dispose();
    await source.dispose();
  });
}
