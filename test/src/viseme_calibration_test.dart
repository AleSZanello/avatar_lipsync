// Runs a WAV file (mono PCM16, e.g. 24 kHz) through the lip-sync
// pipeline and prints how often each mouth shape leads, how often the lips
// press, and a CSV trace to plot. A tuning aid, not an assertion:
//   AVATAR_CALIBRATION_WAV=path/to/voice.wav \
//   AVATAR_CALIBRATION_CSV=/tmp/trace.csv \
//     flutter test test/src/viseme_calibration_test.dart
// A CLI-style report for a person tuning thresholds.
// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:avatar_lipsync/avatar_lipsync.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  final wav = Platform.environment['AVATAR_CALIBRATION_WAV'];
  final csv = Platform.environment['AVATAR_CALIBRATION_CSV'];
  final vcv = Platform.environment['AVATAR_VCV_DIR'];

  // A labelled check of lip closures: a directory of `<voice>_<word>.wav`
  // files such as `voice1_aba.wav`. Each voice's words are played once to
  // learn the voice, then again one by one; the report is the strongest
  // press inside each word. m, b and p should press; t, d, k, g, n, s and f
  // should not.
  test(
    'prints how hard each consonant presses the lips',
    skip: vcv == null,
    () {
      final files =
          Directory(vcv!)
              .listSync()
              .whereType<File>()
              .where((f) => f.path.endsWith('.wav'))
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));
      final byVoice = <String, List<File>>{};
      for (final f in files) {
        final name = f.uri.pathSegments.last;
        byVoice.putIfAbsent(name.split('_').first, () => []).add(f);
      }
      for (final MapEntry(key: voice, value: words) in byVoice.entries) {
        final clips = [for (final f in words) readPcm16(f.readAsBytesSync())];
        final gap = silence(0.5);
        final all = join([
          for (final c in clips) ...[c, gap],
          for (final c in clips) ...[c, gap],
        ]);
        final timeline = timelineOf(all);
        final analyzer = LipSyncAnalyzer();
        // Where each clip of the second pass starts and ends (seconds).
        final windows = <(double, double)>[];
        var at =
            clips.fold(0, (n, c) => n + (c.length + gap.length)) / speechRate;
        for (final c in clips) {
          windows.add((at, at + c.length / speechRate));
          at += (c.length + gap.length) / speechRate;
        }
        final presses = List<double>.filled(clips.length, 0);
        for (var k = 0; k / 60 < at; k++) {
          final t = k / 60;
          final press = analyzer.update(timeline, t, 1 / 60).press;
          for (var i = 0; i < windows.length; i++) {
            if (t >= windows[i].$1 && t < windows[i].$2) {
              presses[i] = math.max(presses[i], press);
            }
          }
        }
        final line = StringBuffer('$voice ');
        for (var i = 0; i < clips.length; i++) {
          final word = words[i].uri.pathSegments.last.split('_').last;
          line.write(
            '${word.replaceAll('.wav', '')} ${presses[i].toStringAsFixed(2)}  ',
          );
        }
        print(line);
      }
      expect(byVoice, isNotEmpty);
    },
  );

  test('prints the mouth-shape histogram of a voice', skip: wav == null, () {
    final samples = readPcm16(File(wav!).readAsBytesSync());
    final timeline = timelineOf(samples);
    final analyzer = LipSyncAnalyzer();
    final counts = {for (final v in Viseme.values) v: 0};
    var pressed = 0;
    final trace = StringBuffer(
      't,db,f1,f2,hiss,nasal,gap,jaw,width,round,press,viseme\n',
    );
    final seconds = samples.length / speechRate;
    var frames = 0;
    for (var t = 0.0; t < seconds; t += 1 / 60) {
      final f = analyzer.update(timeline, t, 1 / 60);
      final s = timeline.at(t + analyzer.lead);
      counts[f.viseme] = counts[f.viseme]! + 1;
      if (f.press > 0.5) pressed++;
      frames++;
      trace.writeln(
        [
          t.toStringAsFixed(3),
          s?.db.toStringAsFixed(1) ?? '',
          s?.openness.toStringAsFixed(0) ?? '',
          s?.spread.toStringAsFixed(0) ?? '',
          s?.hiss.toStringAsFixed(2) ?? '',
          s?.nasal.toStringAsFixed(2) ?? '',
          f.gap.toStringAsFixed(3),
          f.jaw.toStringAsFixed(3),
          f.width.toStringAsFixed(3),
          f.round.toStringAsFixed(2),
          f.press.toStringAsFixed(2),
          f.viseme.name,
        ].join(','),
      );
    }
    for (final e in counts.entries) {
      final share = (100 * e.value / frames).toStringAsFixed(1);
      print('${e.key.name.padRight(10)} $share%');
    }
    print('pressed    ${(100 * pressed / frames).toStringAsFixed(1)}%');
    if (csv != null) File(csv).writeAsStringSync(trace.toString());
    expect(frames, greaterThan(0));
  });
}

/// The samples of a PCM16 WAV file's `data` chunk, in -1..1.
Float32List readPcm16(Uint8List wav) {
  final data = ByteData.sublistView(wav);
  var offset = 12;
  while (offset + 8 <= wav.length) {
    final id = String.fromCharCodes(wav.sublist(offset, offset + 4));
    final size = data.getUint32(offset + 4, Endian.little);
    if (id == 'data') {
      return Float32List.fromList([
        for (var i = 0; i < size ~/ 2; i++)
          data.getInt16(offset + 8 + i * 2, Endian.little) / 32768,
      ]);
    }
    offset += 8 + size + (size.isOdd ? 1 : 0);
  }
  throw const FormatException('no data chunk');
}
