/// Real-time lip sync for Flutter: a talking avatar driven by streamed speech.
///
/// Implement a `LipSyncSource` over your audio playback. `SpeechTimeline`
/// analyses each chunk as it is scheduled and `LipSyncAnalyzer` turns it into
/// smoothed `LipSyncFrame`s. Show them with `LipSyncAvatar` (a drawn face, any
/// platform) or `PhotoLipSyncAvatar` (a rigged photo, web), or feed them to
/// your own character through `onFrame`.
library;

export 'src/avatar_motion.dart';
export 'src/face/face_landmark_detector.dart';
export 'src/face/face_landmarks.dart';
export 'src/face/face_rig.dart';
export 'src/face/mouth_palette.dart';
export 'src/lip_sync_analyzer.dart';
export 'src/lip_sync_avatar.dart';
export 'src/lip_sync_driver.dart';
export 'src/lip_sync_source.dart';
export 'src/photo_lip_sync_avatar.dart';
export 'src/speech_timeline.dart';
export 'src/viseme.dart';
