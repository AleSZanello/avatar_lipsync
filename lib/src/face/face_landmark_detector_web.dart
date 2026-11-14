import 'dart:async';
import 'dart:developer';
import 'dart:js_interop';
import 'dart:ui' show Size;
import 'dart:ui_web' as ui_web;

import 'package:avatar_lipsync/src/face/face_landmark_detector.dart';
import 'package:avatar_lipsync/src/face/face_landmarks.dart';
import 'package:web/web.dart' as web;

FaceLandmarkDetector createFaceLandmarkDetector() => _MediaPipeDetector();

/// Pinned MediaPipe Tasks Vision release and its float16 face model.
const _visionVersion = '0.10.14';
const _visionBase =
    'https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@$_visionVersion';
const _modelUrl =
    'https://storage.googleapis.com/mediapipe-models/face_landmarker/'
    'face_landmarker/float16/1/face_landmarker.task';

/// The JS side, loaded as an ES module from a blob URL so the host
/// page needs no script tag. It runs MediaPipe once per image,
/// closes it, and returns normalized x, y pairs plus the image's size.
const _moduleSource =
    '''
const BASE = "$_visionBase";
export async function detect(url) {
  const image = new Image();
  image.crossOrigin = "anonymous";
  image.src = url;
  await image.decode();
  const vision = await import(BASE + "/vision_bundle.mjs");
  const files = await vision.FilesetResolver.forVisionTasks(BASE + "/wasm");
  const landmarker = await vision.FaceLandmarker.createFromOptions(files, {
    baseOptions: { modelAssetPath: "$_modelUrl", delegate: "CPU" },
    runningMode: "IMAGE",
    numFaces: 1,
  });
  // One photo, one detection: free the model's memory right after.
  let result;
  try {
    result = landmarker.detect(image);
  } finally {
    landmarker.close();
  }
  const points = result.faceLandmarks && result.faceLandmarks[0];
  if (!points) return null;
  const xy = new Float32Array(points.length * 2);
  points.forEach((p, i) => { xy[2 * i] = p.x; xy[2 * i + 1] = p.y; });
  return { xy, width: image.naturalWidth, height: image.naturalHeight };
}
''';

extension type _Module(JSObject _) implements JSObject {
  external JSPromise<_Detection?> detect(JSString url);
}

extension type _Detection(JSObject _) implements JSObject {
  external JSFloat32Array get xy;
  external double get width;
  external double get height;
}

class _MediaPipeDetector implements FaceLandmarkDetector {
  static Future<_Module>? _module;
  static final _cache = <String, Future<FaceLandmarks?>>{};

  @override
  Future<FaceLandmarks?> detectAsset(String assetKey) =>
      _cache.putIfAbsent(assetKey, () => _detect(assetKey));

  Future<FaceLandmarks?> _detect(String assetKey) async {
    try {
      final module = await (_module ??= _load());
      final url = ui_web.assetManager.getAssetUrl(assetKey);
      final started = DateTime.now();
      final found = await module.detect(url.toJS).toDart;
      if (found == null) {
        log('[Avatar] no face found in $assetKey', name: 'AvatarLipSync');
        return null;
      }
      final landmarks = FaceLandmarks.fromNormalized(
        found.xy.toDart,
        Size(found.width, found.height),
      );
      log(
        '[Avatar] ${landmarks.points.length} landmarks in '
        '${DateTime.now().difference(started).inMilliseconds} ms',
        name: 'AvatarLipSync',
      );
      return landmarks;
    } on Object catch (error, stack) {
      log(
        '[Avatar] face detection failed',
        name: 'AvatarLipSync',
        error: error,
        stackTrace: stack,
      );
      unawaited(_cache.remove(assetKey));
      return null;
    }
  }

  static Future<_Module> _load() async {
    final blob = web.Blob(
      [_moduleSource.toJS].toJS,
      web.BlobPropertyBag(type: 'text/javascript'),
    );
    final url = web.URL.createObjectURL(blob);
    try {
      final module = await importModule(url.toJS).toDart;
      return module as _Module;
    } finally {
      web.URL.revokeObjectURL(url);
    }
  }
}
