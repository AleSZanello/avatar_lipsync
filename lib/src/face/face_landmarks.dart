import 'dart:typed_data';
import 'dart:ui';

/// The face points of one image, in image pixels.
///
/// Uses MediaPipe Face Landmarker's topology: 468 face-mesh points plus 10
/// iris points (468–477). [FaceMeshIndex] names the ones the rig needs.
class FaceLandmarks {
  /// Creates landmarks from pixel [points] on an image of [imageSize].
  const FaceLandmarks(this.points, this.imageSize);

  /// Builds landmarks from MediaPipe's normalized `x, y` pairs.
  factory FaceLandmarks.fromNormalized(Float32List xy, Size imageSize) {
    final points = <Offset>[
      for (var i = 0; i + 1 < xy.length; i += 2)
        Offset(xy[i] * imageSize.width, xy[i + 1] * imageSize.height),
    ];
    return FaceLandmarks(points, imageSize);
  }

  /// Every point, indexed as MediaPipe numbers them.
  final List<Offset> points;

  /// Size of the image the points belong to.
  final Size imageSize;

  /// Whether every point the rig relies on is present.
  bool get isComplete => points.length >= FaceMeshIndex.faceMeshCount;

  /// The point at MediaPipe [index].
  Offset operator [](int index) => points[index];
}

/// MediaPipe face-mesh indices the rig uses.
///
/// "First" and "second" eye are the subject's right and left eye, as they
/// appear left and right in a non-mirrored photo.
abstract final class FaceMeshIndex {
  /// Points of the face mesh without the irises.
  static const faceMeshCount = 468;

  /// Outer mouth corners (left, right in the image).
  static const mouthCornerLeft = 61;

  /// See [mouthCornerLeft].
  static const mouthCornerRight = 291;

  /// Middle of the upper inner lip.
  static const upperInnerLipMid = 13;

  /// Middle of the lower inner lip.
  static const lowerInnerLipMid = 14;

  /// Bottom edge of the lower lip, in the middle.
  static const lowerLipBottom = 17;

  /// Bottom of the chin.
  static const chin = 152;

  /// Tip of the nose.
  static const noseTip = 1;

  /// Upper inner lip, corner to corner.
  static const upperInnerLip = [
    78, 191, 80, 81, 82, 13, 312, 311, 310, 415, 308, //
  ];

  /// Lower inner lip, corner to corner.
  static const lowerInnerLip = [
    78, 95, 88, 178, 87, 14, 317, 402, 318, 324, 308, //
  ];

  /// Corners of the first eye (outer, inner).
  static const firstEyeCorners = (33, 133);

  /// Corners of the second eye (inner, outer).
  static const secondEyeCorners = (362, 263);

  /// Upper and lower lid middles of the first eye.
  static const firstEyeLids = (159, 145);

  /// Upper and lower lid middles of the second eye.
  static const secondEyeLids = (386, 374);

  /// Iris points of the first eye (468–472) and the second (473–477).
  static const firstIris = [468, 469, 470, 471, 472];

  /// See [firstIris].
  static const secondIris = [473, 474, 475, 476, 477];

  /// The first eye's upper lid edge, from corner to corner.
  static const firstUpperLid = [33, 246, 161, 160, 159, 158, 157, 173, 133];

  /// The first eye's lower lid edge, from corner to corner.
  static const firstLowerLid = [33, 7, 163, 144, 145, 153, 154, 155, 133];

  /// The second eye's upper lid edge, from corner to corner.
  static const secondUpperLid = [362, 398, 384, 385, 386, 387, 388, 466, 263];

  /// The second eye's lower lid edge, from corner to corner.
  static const secondLowerLid = [362, 382, 381, 380, 374, 373, 390, 249, 263];

  /// The first eye's brow: its upper and lower edges.
  static const firstBrow = [70, 63, 105, 66, 107, 46, 53, 52, 65, 55];

  /// The second eye's brow: its upper and lower edges.
  static const secondBrow = [300, 293, 334, 296, 336, 276, 283, 282, 295, 285];
}
