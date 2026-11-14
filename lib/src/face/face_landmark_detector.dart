import 'package:avatar_lipsync/src/face/face_landmark_detector_stub.dart'
    if (dart.library.js_interop) 'package:avatar_lipsync/src/face/face_landmark_detector_web.dart';
import 'package:avatar_lipsync/src/face/face_landmarks.dart';

/// Finds the face points of an image.
abstract interface class FaceLandmarkDetector {
  /// The browser detector (MediaPipe Face Landmarker), or one that finds
  /// nothing off the web.
  factory FaceLandmarkDetector() => createFaceLandmarkDetector();

  /// Landmarks of the face in the image at [assetKey] (a Flutter asset), or
  /// `null` when no face is found or detection cannot run.
  Future<FaceLandmarks?> detectAsset(String assetKey);
}
