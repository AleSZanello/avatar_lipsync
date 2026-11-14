// The README's realtime recipes, compiled with the example so they stay
// correct. Call them from your WebSocket (or SDK) message handler.
import 'dart:async';
import 'dart:convert';

import 'package:avatar_lipsync_example/sources/web_audio_speech_source.dart';

/// Gemini Live: every server message.
void onGeminiMessage(WebAudioSpeechSource source, Map<String, Object?> msg) {
  if (msg case {'serverContent': {'interrupted': true}}) {
    return source.stop(); // barge-in
  }
  if (msg case {
    'serverContent': {'modelTurn': {'parts': final List<Object?> parts}},
  }) {
    for (final part in parts) {
      if (part case {'inlineData': {'data': final String audio}}) {
        unawaited(source.playPcm16(base64Decode(audio), 24000));
      }
    }
  }
}

/// OpenAI Realtime (WebSocket transport): every server event.
void onOpenAIEvent(WebAudioSpeechSource source, Map<String, Object?> event) {
  switch (event) {
    // 'response.audio.delta' is the beta API's name for the same event.
    case {
      'type': 'response.output_audio.delta' || 'response.audio.delta',
      'delta': final String audio,
    }:
      unawaited(source.playPcm16(base64Decode(audio), 24000));
    case {'type': 'input_audio_buffer.speech_started'}: // the user talks
      source.stop();
  }
}
