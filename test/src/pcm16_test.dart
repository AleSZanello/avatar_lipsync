import 'dart:typed_data';

import 'package:avatar_lipsync/avatar_lipsync.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('pcm16ToSamples', () {
    test('decodes little-endian 16-bit samples to -1..1', () {
      final bytes = Uint8List.fromList([
        0x00, 0x00, // 0
        0xFF, 0x7F, // 32767
        0x00, 0x80, // -32768
        0x00, 0x40, // 16384
      ]);
      expect(pcm16ToSamples(bytes), [0, closeTo(1, 1e-4), -1, 0.5]);
    });

    test('ignores a trailing odd byte', () {
      expect(pcm16ToSamples(Uint8List.fromList([0, 0x40, 7])), [0.5]);
    });

    test('reads a view that does not start at offset 0', () {
      final buffer = Uint8List.fromList([9, 0x00, 0x40]);
      final view = Uint8List.sublistView(buffer, 1);
      expect(pcm16ToSamples(view), [0.5]);
    });
  });
}
