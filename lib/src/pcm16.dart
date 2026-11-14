import 'dart:typed_data';

/// Converts little-endian 16-bit PCM to samples in -1..1.
///
/// This is the format realtime voice APIs stream (OpenAI Realtime and Gemini
/// Live send it base64-encoded, mono, at 24 kHz): decode the base64 string
/// to bytes and pass them here to build a `SpeechChunk`. A trailing odd byte
/// is ignored.
Float32List pcm16ToSamples(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  final out = Float32List(bytes.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = data.getInt16(i * 2, Endian.little) / 32768;
  }
  return out;
}
