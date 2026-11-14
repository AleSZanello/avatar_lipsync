import 'dart:async';
import 'dart:developer';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:avatar_lipsync/src/avatar_motion.dart';
import 'package:avatar_lipsync/src/face/face_landmark_detector.dart';
import 'package:avatar_lipsync/src/face/face_landmarks.dart';
import 'package:avatar_lipsync/src/face/face_rig.dart';
import 'package:avatar_lipsync/src/face/mouth_palette.dart';
import 'package:avatar_lipsync/src/lip_sync_analyzer.dart';
import 'package:avatar_lipsync/src/lip_sync_driver.dart';
import 'package:avatar_lipsync/src/lip_sync_source.dart';
import 'package:avatar_lipsync/src/viseme.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// A photo of a face that talks: the mouth follows [source] in real time and
/// the face blinks, breathes, nods and glances like a person on a call.
///
/// The image at [imageAsset] is rigged once (face points from [detector],
/// see `FaceRig`) and then redrawn every frame as a deformed mesh, with the
/// inside of the mouth (teeth, tongue, shadow) painted where the lips part.
/// It fills its box like a video feed (cover, centred on the face).
///
/// While the face is being found the still photo shows; if no face is found
/// (or off the web) [fallback] shows instead.
class PhotoLipSyncAvatar extends StatefulWidget {
  /// Creates the avatar.
  const PhotoLipSyncAvatar({
    required this.source,
    required this.imageAsset,
    this.detector,
    this.fallback,
    this.showDebug = false,
    this.onFrame,
    this.imageLoader,
    super.key,
  });

  /// Where the audible audio is read from.
  final LipSyncSource source;

  /// Flutter asset key of a frontal face photo with the mouth closed.
  final String imageAsset;

  /// Finds the face points; the MediaPipe detector by default.
  final FaceLandmarkDetector? detector;

  /// Shown when the photo cannot be rigged.
  final Widget? fallback;

  /// Prints the live viseme, loudness, delay and frame times on the photo.
  final bool showDebug;

  /// Called with every mouth frame.
  final ValueChanged<LipSyncFrame>? onFrame;

  /// Decodes [imageAsset]; reads the asset bundle by default. Tests pass a
  /// loader that reads a file.
  final Future<ui.Image> Function(String asset)? imageLoader;

  @override
  State<PhotoLipSyncAvatar> createState() => _PhotoLipSyncAvatarState();
}

enum _Status { loading, ready, failed }

class _PhotoLipSyncAvatarState extends State<PhotoLipSyncAvatar>
    with SingleTickerProviderStateMixin {
  late final LipSyncDriver _driver;
  final _motion = AvatarMotion();
  final _state = ValueNotifier<_Frame?>(null);
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  ui.Image? _image;
  FaceRig? _rig;
  MouthPalette _palette = MouthPalette.fallback;
  ui.ImageShader? _shader;
  _Status _status = _Status.loading;
  double _poseMs = 0;

  @override
  void initState() {
    super.initState();
    // Listen from the start: chunks are scheduled before they are heard.
    _driver = LipSyncDriver(widget.source);
    _ticker = createTicker(_onTick);
    unawaited(_load());
  }

  Future<void> _load() async {
    final detector = widget.detector ?? FaceLandmarkDetector();
    // Detection (a model download the first time) runs while the photo
    // decodes; the still photo shows as soon as it is ready.
    final found = detector
        .detectAsset(widget.imageAsset)
        .then<FaceLandmarks?>(
          (landmarks) => landmarks,
          onError: (Object error, StackTrace stack) {
            log(
              '[Avatar] face detection failed',
              name: 'AvatarLipSync',
              error: error,
              stackTrace: stack,
            );
            return null;
          },
        );
    try {
      final image = await (widget.imageLoader ?? _decode)(widget.imageAsset);
      if (!mounted) {
        image.dispose();
        return;
      }
      setState(() => _image = image);
      final landmarks = await found;
      final rig = landmarks == null ? null : FaceRig.build(landmarks);
      if (!mounted) return;
      if (rig == null) {
        log(
          '[Avatar] no rig: '
          '${landmarks == null ? 'no landmarks' : 'incomplete landmarks'}',
          name: 'AvatarLipSync',
        );
      }
      if (rig == null) {
        // The fallback runs its own lip sync; stop analysing twice.
        unawaited(_driver.dispose());
      } else {
        _shader = _shaderFor(image);
      }
      setState(() {
        _rig = rig;
        _status = rig != null ? _Status.ready : _Status.failed;
      });
      if (_status != _Status.ready || landmarks == null) return;
      _ticker.start();
      // The mouth's colors come from the photo; until they are read the
      // fallback palette paints it.
      final pixels = await image.toByteData();
      if (pixels != null && mounted) {
        setState(
          () => _palette = MouthPalette.sample(pixels, image.width, landmarks),
        );
      }
    } on Object catch (error, stack) {
      log(
        '[Avatar] photo avatar failed to load',
        name: 'AvatarLipSync',
        error: error,
        stackTrace: stack,
      );
      if (mounted) setState(() => _status = _Status.failed);
    }
  }

  static ui.ImageShader _shaderFor(ui.Image image) => ui.ImageShader(
    image,
    TileMode.clamp,
    TileMode.clamp,
    Matrix4.identity().storage,
    filterQuality: FilterQuality.medium,
  );

  static Future<ui.Image> _decode(String asset) async {
    // ImmutableBuffer.fromAsset is not supported on the web.
    final data = await rootBundle.load(asset);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  void _onTick(Duration elapsed) {
    final rig = _rig;
    if (rig == null) return;
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    final frame = _driver.tick(dt);
    final pose = _motion.update(dt, frame);
    final started = DateTime.now().microsecondsSinceEpoch;
    final positions = rig.pose(frame, pose);
    _poseMs =
        _poseMs * 0.9 +
        (DateTime.now().microsecondsSinceEpoch - started) / 1000 * 0.1;
    _state.value = _Frame(
      frame: frame,
      pose: pose,
      positions: positions,
      analysisMs: _driver.analysisMs,
      tickMs: _driver.tickMs,
      poseMs: _poseMs,
      leadMs: _driver.analyzer.lead * 1000,
    );
    widget.onFrame?.call(frame);
  }

  @override
  void dispose() {
    _ticker.dispose();
    unawaited(_driver.dispose());
    _state.dispose();
    _shader?.dispose();
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _motion.reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final image = _image;
    final rig = _rig;
    if (_status == _Status.failed) {
      return widget.fallback ?? const SizedBox.shrink();
    }
    if (image == null) return const SizedBox.expand();
    final face = CustomPaint(
      size: Size.infinite,
      painter: _PhotoPainter(
        image: image,
        shader: _shader ??= _shaderFor(image),
        rig: rig,
        state: _state,
        palette: _palette,
      ),
    );
    if (!widget.showDebug || rig == null) return face;
    return Stack(
      fit: StackFit.expand,
      children: [
        face,
        Positioned(
          left: 8,
          top: 8,
          child: ValueListenableBuilder(
            valueListenable: _state,
            builder: (context, state, _) => _DebugLabel(state: state, rig: rig),
          ),
        ),
      ],
    );
  }
}

class _DebugLabel extends StatelessWidget {
  const _DebugLabel({required this.state, required this.rig});

  final _Frame? state;
  final FaceRig rig;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final text = s == null
        ? 'rig ${rig.vertexCount} v'
        : '${s.frame.viseme.name}  gap ${s.frame.gap.toStringAsFixed(2)} W'
              '  jaw ${s.frame.jaw.toStringAsFixed(2)} H'
              '  press ${s.frame.press.toStringAsFixed(1)}'
              '  level ${s.frame.level.toStringAsFixed(2)}\n'
              'mouth leads by ${s.leadMs.toStringAsFixed(0)} ms  '
              'chunk ${s.analysisMs.toStringAsFixed(2)} ms  '
              'frame ${s.tickMs.toStringAsFixed(2)} + '
              '${s.poseMs.toStringAsFixed(2)} ms\n'
              'mesh ${rig.vertexCount} v / ${rig.indices.length ~/ 3} t';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0x99000000),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          text,
          style: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 11),
        ),
      ),
    );
  }
}

class _Frame {
  const _Frame({
    required this.frame,
    required this.pose,
    required this.positions,
    required this.analysisMs,
    required this.poseMs,
    required this.tickMs,
    required this.leadMs,
  });

  final LipSyncFrame frame;
  final AvatarPose pose;
  final Float32List positions;
  final double analysisMs;
  final double poseMs;
  final double tickMs;
  final double leadMs;
}

class _PhotoPainter extends CustomPainter {
  _PhotoPainter({
    required this.image,
    required this.shader,
    required this.state,
    this.rig,
    this.palette = MouthPalette.fallback,
  }) : super(repaint: state);

  final ui.Image image;
  final FaceRig? rig;
  final MouthPalette palette;
  final ValueNotifier<_Frame?> state;
  final ui.ImageShader shader;

  @override
  void paint(Canvas canvas, Size size) {
    final rig = this.rig;
    final s = rig == null ? null : state.value;
    final imageSize = Size(image.width.toDouble(), image.height.toDouble());
    // Cover the box like a video feed, a little zoomed so head motion never
    // shows the photo's edge, and keep the face near the upper middle.
    final scale =
        math.max(size.width / imageSize.width, size.height / imageSize.height) *
        1.06;
    final focus = rig?.faceCenter ?? imageSize.center(Offset.zero);
    var tx = size.width / 2 - focus.dx * scale;
    var ty = size.height * 0.46 - focus.dy * scale;
    tx = tx.clamp(size.width - imageSize.width * scale, 0.0);
    ty = ty.clamp(size.height - imageSize.height * scale, 0.0);

    canvas
      ..save()
      ..clipRect(Offset.zero & size)
      ..translate(tx, ty)
      ..scale(scale)
      // The untouched photo underneath fills any sliver the mesh leaves;
      // its edge pixels stretch outward (clamp) so a head turn never shows
      // the box behind the photo.
      ..drawRect(
        (Offset.zero & imageSize).inflate(imageSize.shortestSide * 0.2),
        Paint()
          ..shader = shader
          ..filterQuality = FilterQuality.medium,
      );

    final positions = s?.positions;
    if (rig != null && positions != null) {
      final vertices = ui.Vertices.raw(
        VertexMode.triangles,
        positions,
        textureCoordinates: rig.rest,
        indices: rig.indices,
      );
      canvas.drawVertices(
        vertices,
        BlendMode.srcOver,
        Paint()
          ..shader = shader
          ..filterQuality = FilterQuality.medium,
      );
      vertices.dispose();
      _paintMouth(canvas, rig, s!.frame);
    }
    canvas.restore();
  }

  /// The inside of the parted lips, in the photo's own colors: a cavity
  /// that darkens toward the back, upper teeth hugging the upper lip, lower
  /// teeth and the tongue only when the jaw is well open, depth shading at
  /// the sides and the lips' ambient occlusion.
  void _paintMouth(Canvas canvas, FaceRig rig, LipSyncFrame frame) {
    final gap = rig.mouthGap;
    final width = rig.mouthWidth;
    // Neutral mouth width: the unit every size below is a fraction of, so
    // any photo resolution looks the same.
    final unit = width / (1 + frame.width);
    if (gap < unit * 0.005) return;
    final outline = rig.mouthOutline;
    final path = _smoothPath(outline);
    final bounds = path.getBounds();
    final center = bounds.center;
    // Upper lip corner to corner, then the lower lip back (see FaceRig).
    final upper = outline.sublist(0, 11);
    final lower = [outline[10], ...outline.sublist(11), outline[0]];
    final p = palette;

    canvas
      ..save()
      ..clipPath(path)
      ..drawRect(
        bounds.inflate(2),
        Paint()
          ..shader = ui.Gradient.radial(
            center.translate(0, bounds.height * 0.15),
            math.max(bounds.width * 0.55, bounds.height),
            [p.cavity, p.deep],
          ),
      );

    // Lower teeth and tongue show only with the jaw well open (an a or e).
    final wide = _smoothstep(0.16, 0.28, gap / unit);
    if (wide > 0) {
      final bottom = lower.map((q) => q.dy).reduce(math.max);
      final tongueShown = switch (frame.viseme) {
        Viseme.a || Viseme.e => 1.0,
        _ => 0.45,
      };
      final tongue = Rect.fromCenter(
        center: Offset(center.dx, bottom - gap * 0.06),
        width: width * 0.48,
        height: gap * 0.42,
      );
      canvas.drawOval(
        tongue,
        Paint()
          ..shader = ui.Gradient.radial(
            tongue.center.translate(0, -tongue.height * 0.2),
            tongue.width * 0.55,
            [
              p.tongue.withValues(alpha: 0.9 * wide * tongueShown),
              p.tongueShade.withValues(alpha: 0.9 * wide * tongueShown),
            ],
          ),
      );
      _paintTeeth(
        canvas,
        lower,
        height: math.min(gap * 0.14, unit * 0.05),
        down: false,
        alpha: 0.6 * wide,
        unit: unit,
      );
    }

    final teeth = _smoothstep(0.012, 0.05, gap / unit);
    if (teeth > 0) {
      _paintTeeth(
        canvas,
        upper,
        height: math.min(gap * 0.32, unit * 0.09),
        down: true,
        alpha: teeth,
        unit: unit,
      );
    }

    final occlusion = unit * 0.045;
    canvas
      // Depth: the sides of the mouth sit in shadow.
      ..drawRect(
        bounds,
        Paint()
          ..shader = ui.Gradient.linear(
            bounds.centerLeft,
            bounds.centerRight,
            [
              p.deep.withValues(alpha: 0.85),
              p.deep.withValues(alpha: 0),
              p.deep.withValues(alpha: 0),
              p.deep.withValues(alpha: 0.85),
            ],
            const [0, 0.28, 0.72, 1],
          ),
      )
      // Ambient occlusion: the lips shade the cavity right behind them.
      ..drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = occlusion * 2
          ..color = p.deep.withValues(alpha: 0.7)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, occlusion * 0.6),
      )
      ..restore()
      // A soft, thin line where lip meets cavity keeps the edge defined.
      ..drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = unit * 0.007
          ..color = p.deep.withValues(alpha: 0.35)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, unit * 0.004),
      );
  }

  /// A row of teeth hugging [lip] (corner to corner): it starts under the lip
  /// and reaches [height] in the middle, tapering to nothing at the corners.
  void _paintTeeth(
    Canvas canvas,
    List<Offset> lip, {
    required double height,
    required bool down,
    required double alpha,
    required double unit,
  }) {
    if (height < unit * 0.004) return;
    final sign = down ? 1.0 : -1.0;
    final n = lip.length - 1;
    final edge = <Offset>[
      for (var i = 0; i <= n; i++) lip[i].translate(0, -sign * unit * 0.025),
      for (var i = n; i >= 0; i--)
        lip[i].translate(
          0,
          sign * height * math.pow(math.sin(math.pi * i / n), 0.6),
        ),
    ];
    final path = _smoothPath(edge);
    final box = path.getBounds();
    canvas.drawPath(
      path,
      Paint()
        ..shader = ui.Gradient.linear(
          down ? box.topCenter : box.bottomCenter,
          down ? box.bottomCenter : box.topCenter,
          [
            palette.teeth.withValues(alpha: alpha),
            palette.teethShade.withValues(alpha: alpha),
          ],
        )
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, unit * 0.005),
    );
    // A hint of the gaps between the front teeth.
    final seam = Paint()
      ..color = palette.deep.withValues(alpha: 0.18 * alpha)
      ..strokeWidth = unit * 0.006;
    final mid = lip[n ~/ 2];
    for (final k in [-1.0, 0.0, 1.0]) {
      final x = mid.dx + k * box.width * 0.14;
      canvas.drawLine(
        Offset(x, mid.dy),
        Offset(x, mid.dy + sign * height * (k == 0 ? 0.9 : 0.75)),
        seam,
      );
    }
  }

  static Path _smoothPath(List<Offset> points) {
    final path = Path();
    final n = points.length;
    final start = (points[n - 1] + points[0]) / 2;
    path.moveTo(start.dx, start.dy);
    for (var i = 0; i < n; i++) {
      final p = points[i];
      final next = points[(i + 1) % n];
      final mid = (p + next) / 2;
      path.quadraticBezierTo(p.dx, p.dy, mid.dx, mid.dy);
    }
    return path..close();
  }

  static double _smoothstep(double edge0, double edge1, double x) {
    final t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  @override
  bool shouldRepaint(_PhotoPainter oldDelegate) =>
      oldDelegate.image != image ||
      oldDelegate.rig != rig ||
      oldDelegate.palette != palette;
}
