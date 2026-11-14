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
