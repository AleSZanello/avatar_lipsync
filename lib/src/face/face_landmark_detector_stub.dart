import 'package:avatar_lipsync/src/face/face_landmark_detector.dart';
import 'package:avatar_lipsync/src/face/face_landmarks.dart';

/// Off the web there is no MediaPipe: the avatar falls back.
FaceLandmarkDetector createFaceLandmarkDetector() => _NoFaceDetector();

class _NoFaceDetector implements FaceLandmarkDetector {
  @override
  Future<FaceLandmarks?> detectAsset(String assetKey) async => null;
}
