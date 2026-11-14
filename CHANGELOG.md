## 0.3.0

- `RigOverlay` on `PhotoLipSyncAvatar`: draws the triangle mesh, the 478
  landmarks and a heat map, either of live motion (with the head's own
  motion taken out) or of a region's weights (`RigRegion`: jaw, lips,
  corners, eyelids, brows, irises, head).
- `FaceRig.weights(region)` and `FaceRig.landmarkCount`.
- Example: `MicSpeechSource`, a `LipSyncSource` over the microphone.
- Live demo at https://lipsync.azanello.com (in `demo/`, not part of the
  package).

## 0.2.0

- `pcm16ToSamples`: converts little-endian 16-bit PCM, as OpenAI Realtime
  and Gemini Live stream it, to samples for a `SpeechChunk`.
- README: recipe for realtime voice models (OpenAI Realtime, Gemini Live).
- Example: `WebAudioSpeechSource.playPcm16`, a short fade on `stop()`, a
  scheduling lead after gaps, and a latency fix for Safari, which has no
  `outputLatency`.

## 0.1.1

- Example: uses `package:material_ui`, since `package:flutter/material.dart`
  is deprecated on the current stable Flutter.
- Releases are published from GitHub Actions (version tags, OIDC).

## 0.1.0

First release.

- `LipSyncSource`: the interface your audio player implements (scheduled
  chunks, flushes, audible time).
- `SpeechTimeline` and `LipSyncAnalyzer`: speech analysis ahead of playback
  and a JALI-style mouth model (jaw, lip gap, width, rounding, press, viseme).
- `LipSyncAvatar`: a drawn face for every platform.
- `PhotoLipSyncAvatar`: a rigged photo on the web (MediaPipe Face Landmarker
  loaded at runtime), with blinks, head motion, brows and gaze from
  `AvatarMotion`.
