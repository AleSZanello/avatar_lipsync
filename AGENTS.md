# AGENTS.md: guide for AI coding agents

This file is for agents that **use** `avatar_lipsync` in an app and for agents
that **work on** this package. Read the section you need.

## What the package does

It turns speech audio into mouth shapes in real time and animates a face with
them.

```
your audio player
   │  implements LipSyncSource
   ▼
LipSyncDriver ── chunks ──▶ SpeechTimeline   (FFT analysis, ahead of playback)
   │  tick(dt) every frame        │
   ▼                              ▼
LipSyncAnalyzer ── reads audibleTime + 30 ms ──▶ LipSyncFrame
                                                    │
        ┌───────────────────────────────────────────┼─────────────────┐
        ▼                                           ▼                 ▼
LipSyncAvatar (drawn, any platform)   PhotoLipSyncAvatar (web)   onFrame → your rig
                                       + FaceRig, AvatarMotion,
                                         MouthPalette, MediaPipe
```

Public API (everything is exported from `package:avatar_lipsync/avatar_lipsync.dart`):

| Type | Role |
| --- | --- |
| `LipSyncSource` | Interface the app implements: `chunks`, `flushes`, `audibleTime`. |
| `SpeechChunk` | Mono `Float32List` samples in -1..1, `startTime` (s, player clock) and `sampleRate`. |
| `LipSyncAvatar` | Drawn face. Needs `source` and `colors` (`LipSyncAvatarColors`). |
| `PhotoLipSyncAvatar` | Rigged photo (web). Needs `source` and `imageAsset`. Takes `fallback`, `detector`, `onFrame`, `showDebug` and `imageLoader`. |
| `LipSyncFrame` | `level`, `gap`, `jaw`, `width`, `round`, `press`, `viseme`, `speaking`, and `mouthOpen` (0..1). |
| `Viseme` | `rest`, `a`, `e`, `i`, `o`, `u`, `fricative`. `index` is stable for a Rive `viseme` input. |
| `LipSyncDriver` | Source plus analyzer without widgets: `tick(dt)` returns a `LipSyncFrame`. |
| `SpeechTimeline`, `LipSyncAnalyzer` | Lower-level analysis, for tuning or custom pipelines. |
| `FaceLandmarkDetector`, `FaceLandmarks`, `FaceRig`, `MouthPalette`, `AvatarMotion` | Photo rig internals. They are public so tests and custom renderers can use them. |

## Using the package in an app

### Implementing `LipSyncSource` correctly

This is where integrations go wrong. The contract:

1. **Emit chunks when they are scheduled, not when they sound.** Analysis runs
   ahead of playback. If you emit at play time, the mouth lags.
2. **One clock.** `SpeechChunk.startTime` and `audibleTime` must use the same
   clock: for Web Audio, `AudioContext.currentTime`. Don't mix
   `DateTime.now()` with the player's clock.
3. **`audibleTime` = player clock − output latency.** Return `null` when
   nothing plays or the clock is unknown, and the mouth settles to rest.
4. **Flush on interruption.** When playback is cut (barge-in, stop, skip),
   add the cut time to `flushes`. Without it, the mouth keeps "speaking"
   audio that was never heard.
5. **Mono, float, -1..1.** Convert PCM16 with `sample / 32768`. If the audio
   is stereo, average or pick one channel. Any sample rate works.
6. **Broadcast streams.** Both avatars subscribe in `initState`. Chunks
   emitted before the widget is mounted are lost, so mount the avatar first.

Reference implementations live in `example/lib/sources/`:
- `web_audio_speech_source.dart` plays and schedules over Web Audio. Copy it
  for streamed TTS or voice agents: call `play(chunkSamples, rate)` for every
  network chunk as it arrives.
- `clock_speech_source.dart` keeps a `Stopwatch` clock and plays nothing. Use
  it for tests, previews, or when another player plays the sound but you
  still have the samples.

Other players (`just_audio`, `audioplayers`, native) work if you can get the
**samples** and a **position clock**. Emit the samples (decoded) with their
start position, and return the player's position as `audibleTime`. If a
player gives no samples, this package cannot lip-sync it.

### Choosing a widget

- Cross-platform, or no photo: `LipSyncAvatar`.
- Web with a photo: `PhotoLipSyncAvatar`, always with `fallback:
  LipSyncAvatar(...)`, because off the web, or when no face is found, the
  fallback shows.
- Photo requirements: frontal, mouth closed, face well lit, declared as a
  Flutter asset. Rigging happens once per image: the first time, it
  downloads MediaPipe (wasm runtime and face model) from
  `cdn.jsdelivr.net` and `storage.googleapis.com`. A strict CSP must allow
  both.
- Custom character: either widget with `onFrame`, or `LipSyncDriver`
  directly.

### Debugging

- `showDebug: true` shows the live viseme, level, delay and frame times.
- Mouth always closed: `audibleTime` is `null`, chunks were emitted before
  the widget subscribed, or the `startTime`s are on a different clock than
  `audibleTime`.
- Mouth late or early: the latency is not subtracted from `audibleTime`, or
  the chunks are emitted at play time.
- Mouth keeps moving after stop: a missing flush.

## Working on this package

```sh
flutter pub get
flutter analyze          # very_good_analysis, must be clean
flutter test             # root package
cd example && flutter analyze && flutter test && flutter build web
dart pub publish --dry-run
```

Conventions:
- Lints come from `very_good_analysis` and are enforced. Constructors use
  classic names and `{}` bodies, not Dart 3.13 primary constructors (see
  `analysis_options.yaml`).
- Doc comments explain *why* in plain terms. Public members document units
  (seconds, Hz, 0..1).
- Don't add runtime dependencies. The package only depends on Flutter and
  `package:web`.
- Web-only code goes behind the conditional import in
  `lib/src/face/face_landmark_detector.dart` (`_web.dart` / `_stub.dart`).
  The rest must compile on every platform.
- The MediaPipe version and model URL are pinned in
  `lib/src/face/face_landmark_detector_web.dart`. Bump them deliberately and
  test in Chrome.
- Don't bundle MediaPipe or any third-party asset in `lib/`.

Tests and tools:
- `test/src/helpers.dart` synthesises vowels, hisses and silence, and has
  a `FakeSource` you drive by hand. Prefer synthetic signals over audio files.
- `test/fixtures/face.jpg` and `face_landmarks.json` (CC0, 768×768) feed
  the rig tests. To replace the photo, regenerate the landmarks with the same
  MediaPipe model and keep the JSON shape `{width, height, xy}` (normalized
  x, y pairs, 478 points). Fixtures are excluded from the published package
  by `.pubignore`.
- `AVATAR_PREVIEW_DIR=/tmp/out flutter test test/src/photo_preview_test.dart`
  renders PNGs of mouth shapes and eye poses. Look at them after changing
  `FaceRig` or `MouthPalette`.
- `AVATAR_CALIBRATION_WAV=voice.wav flutter test test/src/viseme_calibration_test.dart`
  prints viseme statistics for real speech. Use it after changing
  `LipSyncAnalyzer` thresholds.

Releasing (automated, `.github/workflows/publish.yml`):
1. Bump `version` in `pubspec.yaml` and add a `CHANGELOG.md` entry.
2. Commit and push to `main`.
3. `git tag vX.Y.Z && git push origin vX.Y.Z`. The tag must match the
   pubspec version. The workflow checks format, analyze and tests (package
   and example), runs a dry run, and publishes to pub.dev through GitHub
   OIDC. There are no secrets to manage.
4. To validate without publishing, run the workflow by hand
   (`gh workflow run publish.yml`). The publish step only runs on tags.
