// Renders the photo avatar in a few mouth shapes to PNG files, for a person
// to look at. Runs only with AVATAR_PREVIEW_DIR set:
//   AVATAR_PREVIEW_DIR=/tmp/out flutter test test/src/photo_preview_test.dart
// Another photo: also set AVATAR_PREVIEW_PHOTO (an image file) and
// AVATAR_PREVIEW_LANDMARKS (its landmarks, as in test/fixtures).
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:avatar_lipsync/avatar_lipsync.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';
import 'photo_helpers.dart';

void main() {
  final dir = Platform.environment['AVATAR_PREVIEW_DIR'];
  final photo = Platform.environment['AVATAR_PREVIEW_PHOTO'] ?? facePhoto;
  final landmarks = Platform.environment['AVATAR_PREVIEW_LANDMARKS'];

  testWidgets('renders preview frames', skip: dir == null, (tester) async {
    await _shoot(tester, dir!, RigOverlay.none, '', photo, landmarks);
  });

  testWidgets('renders overlay frames', skip: dir == null, (tester) async {
    for (final (prefix, overlay) in [
      ('mesh_', const RigOverlay(mesh: true, landmarks: true)),
      ('motion_', const RigOverlay(heat: RigRegion.motion, mesh: true)),
      ('jaw_', const RigOverlay(heat: RigRegion.jaw)),
      ('lips_', const RigOverlay(heat: RigRegion.lips)),
    ]) {
      await _shoot(tester, dir!, overlay, prefix, photo, landmarks);
    }
  });

  test(
    'renders each mouth shape straight from the rig',
    skip: dir == null,
    () async {
      final rig = FaceRig.build(
        landmarks == null ? fixtureLandmarks() : fixtureLandmarks(landmarks),
      )!;
      final image = await loadFixtureImage(photo);
      final frames = <String, LipSyncFrame>{
        for (final v in Viseme.values)
          'v_${v.name}': LipSyncFrame(
            level: 0.8,
            gap: v.gap,
            jaw: v.jaw,
            width: v.widthChange,
            round: v.round,
            press: 0,
            viseme: v,
          ),
        'v_press': const LipSyncFrame(
          level: 0.6,
          gap: 0,
          jaw: 0,
          width: -0.03,
          round: 0,
          press: 1,
          viseme: Viseme.rest,
        ),
      };
      for (final MapEntry(key: name, value: frame) in frames.entries) {
        final pose = name == 'v_rest'
            ? const AvatarPose(blink: 1)
            : const AvatarPose();
        await _writeRig(rig, image, rig.pose(frame, pose), '$dir/$name.png');
      }
    },
  );

  test('renders eye poses straight from the rig', skip: dir == null, () async {
    final rig = FaceRig.build(
      landmarks == null ? fixtureLandmarks() : fixtureLandmarks(landmarks),
    )!;
    final image = await loadFixtureImage(photo);
    for (final (name, pose) in [
      ('7_blink', const AvatarPose(blink: 1)),
      ('8_half_blink', const AvatarPose(blink: 0.5)),
      ('9_brow_gaze', const AvatarPose(brow: 1, gazeX: 1)),
    ]) {
      final positions = rig.pose(LipSyncFrame.rest, pose);
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawVertices(
        ui.Vertices.raw(
          VertexMode.triangles,
          positions,
          textureCoordinates: rig.rest,
          indices: rig.indices,
        ),
        BlendMode.srcOver,
        Paint()
          ..shader = ui.ImageShader(
            image,
            TileMode.clamp,
            TileMode.clamp,
            Matrix4.identity().storage,
          ),
      );
      final picture = recorder.endRecording();
      final out = await picture.toImage(image.width, image.height);
      final png = await out.toByteData(format: ui.ImageByteFormat.png);
      File('$dir/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
    }
  });
}

Future<void> _shoot(
  WidgetTester tester,
  String dir,
  RigOverlay overlay,
  String prefix,
  String photo,
  String? landmarks,
) async {
  tester.view
    ..physicalSize = const Size(640, 640)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final source = FakeSource()..audibleTime = 0;
  final boundary = GlobalKey();
  await tester.pumpWidget(
    MediaQuery(
      data: const MediaQueryData(),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(
          key: boundary,
          child: PhotoLipSyncAvatar(
            source: source,
            imageAsset: photo,
            detector: FixtureDetector(landmarksPath: landmarks),
            imageLoader: loadFixtureImage,
            showDebug: overlay.isEmpty,
            overlay: overlay,
          ),
        ),
      ),
    ),
  );
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 300)),
  );
  await tester.pump();

  // Warm up on mixed vowels, then hold each vowel and shoot mid-way.
  final shapes = [Viseme.a, Viseme.e, Viseme.i, Viseme.o, Viseme.u];
  final parts = <Float32List>[
    for (var r = 0; r < 6; r++)
      for (final v in shapes) vowel(v, seconds: 0.18),
  ];
  final shots = <(String, double)>[];
  var at = parts.fold(0, (n, p) => n + p.length) / speechRate;
  for (final v in shapes) {
    parts.add(vowel(v, seconds: 0.35));
    shots.add(('1_${v.name}', at + 0.25));
    at += 0.35;
  }
  parts
    ..add(silence(0.07))
    ..add(vowel(Viseme.a, seconds: 0.3));
  shots
    ..add(('2_press', at + 0.03))
    ..add(('3_rest', at + 2));
  source.schedule(join(parts));

  var now = 0.0;
  for (final (name, time) in shots) {
    while (now < time) {
      now += 1 / 60;
      source.audibleTime = now;
      await tester.pump(const Duration(milliseconds: 16));
    }
    final render =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await render.toImage();
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      File('$dir/$prefix$name.png').writeAsBytesSync(png!.buffer.asUint8List());
    });
  }
}

Future<void> _writeRig(
  FaceRig rig,
  ui.Image image,
  Float32List positions,
  String path,
) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder)
    ..drawImage(image, Offset.zero, Paint())
    ..drawVertices(
      ui.Vertices.raw(
        VertexMode.triangles,
        positions,
        textureCoordinates: rig.rest,
        indices: rig.indices,
      ),
      BlendMode.srcOver,
      Paint()
        ..shader = ui.ImageShader(
          image,
          TileMode.clamp,
          TileMode.clamp,
          Matrix4.identity().storage,
        ),
    );
  final out = await recorder.endRecording().toImage(image.width, image.height);
  final png = await out.toByteData(format: ui.ImageByteFormat.png);
  File(path).writeAsBytesSync(png!.buffer.asUint8List());
}
