# avatar_lipsync example

A Flutter web app with a talking avatar:

- **Say something** plays synthetic speech (no audio file needed).
- **Play an audio file** plays any WAV/MP3/OGG you pick, and the face
  lip-syncs to it.
- **Photo / Drawn** switches between `PhotoLipSyncAvatar` (the photo is rigged
  in the browser with MediaPipe) and the drawn `LipSyncAvatar`.

```sh
flutter run -d chrome
```

Sources worth copying:

- `lib/sources/web_audio_speech_source.dart`: a `LipSyncSource` over Web
  Audio, the pattern for any player or streamed speech.
- `lib/sources/clock_speech_source.dart`: the smallest `LipSyncSource`, for
  tests and previews.

`assets/face.jpg`: "Portrait de Blanche Angers, actrice" (Bacard fils, Paris,
c. 1880), Paris Musées / Musée Carnavalet, CC0, via
[Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Portrait_de_Blanche_Angers,_actrice,_PH41663.jpg).
