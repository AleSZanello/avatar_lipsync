import 'dart:async';
import 'dart:math' as math;

import 'package:avatar_lipsync/src/lip_sync_analyzer.dart';
import 'package:avatar_lipsync/src/lip_sync_driver.dart';
import 'package:avatar_lipsync/src/lip_sync_source.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Colors of the drawn face.
class LipSyncAvatarColors {
  /// Creates the palette.
  const LipSyncAvatarColors({
    required this.face,
    required this.ink,
    required this.mouth,
  });

  /// Head fill.
  final Color face;

  /// Eyes and lip outline.
  final Color ink;

  /// Inside of the open mouth.
  final Color mouth;
}

/// A simple drawn face whose mouth follows [source] in real time.
///
/// Reads the source once per animation frame through a [Ticker] and repaints
/// through a [ValueNotifier], so the widget tree never rebuilds while the
/// voice speaks. Works on every platform. To drive your own character (a Rive
/// state machine, sprites, a 3D model), use [onFrame], which exposes each
/// [LipSyncFrame].
class LipSyncAvatar extends StatefulWidget {
  /// Creates the avatar.
  const LipSyncAvatar({
    required this.source,
    required this.colors,
    this.size = 140,
    this.showDebug = false,
    this.onFrame,
    super.key,
  });

  /// Where the audible audio is read from.
  final LipSyncSource source;

  /// Face palette.
  final LipSyncAvatarColors colors;

  /// Diameter of the face.
  final double size;

  /// Prints the live viseme, loudness, delay and frame time under the face.
  final bool showDebug;

  /// Called with every frame (for a Rive state machine or for measuring).
  final ValueChanged<LipSyncFrame>? onFrame;

  @override
  State<LipSyncAvatar> createState() => _LipSyncAvatarState();
}

class _LipSyncAvatarState extends State<LipSyncAvatar>
    with SingleTickerProviderStateMixin {
  late final LipSyncDriver _driver;
  final _frame = ValueNotifier<_PaintState>(const _PaintState());
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  double _nextBlink = 3;
  double _blinkLeft = 0;
  final _random = math.Random();

  @override
  void initState() {
    super.initState();
    // Listen from the start: chunks are scheduled before they are heard.
    _driver = LipSyncDriver(widget.source);
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    final frame = _driver.tick(dt);
    _frame.value = _PaintState(
      frame: frame,
      blink: _blink(dt),
      time: elapsed.inMicroseconds / 1e6,
      frameMs: _driver.tickMs,
      delayMs: _driver.analyzer.lead * -1000,
    );
    widget.onFrame?.call(frame);
  }

  /// Eyelid closure, 0 (open) .. 1 (closed), blinking every 2.5–5 s.
  double _blink(double dt) {
    if (_blinkLeft > 0) {
      _blinkLeft -= dt;
      return 1;
    }
    _nextBlink -= dt;
    if (_nextBlink <= 0) {
      _nextBlink = 2.5 + _random.nextDouble() * 2.5;
      _blinkLeft = 0.12;
    }
    return 0;
  }

  @override
  void dispose() {
    _ticker.dispose();
    unawaited(_driver.dispose());
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final face = SizedBox.square(
      dimension: widget.size,
      child: CustomPaint(
        painter: _FacePainter(_frame, widget.colors, still: still),
      ),
    );
    if (!widget.showDebug) return face;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        face,
        ValueListenableBuilder(
          valueListenable: _frame,
          builder: (context, state, _) => Text(
            '${state.frame.viseme.name}  '
            'open ${state.frame.mouthOpen.toStringAsFixed(2)}  '
            'level ${state.frame.level.toStringAsFixed(2)}\n'
            'sync ${state.delayMs.toStringAsFixed(0)} ms  '
            'frame ${state.frameMs.toStringAsFixed(2)} ms',
            textAlign: TextAlign.center,
            style: TextStyle(color: widget.colors.ink, fontSize: 11),
          ),
        ),
      ],
    );
  }
}

class _PaintState {
  const _PaintState({
    this.frame = LipSyncFrame.rest,
    this.blink = 0,
    this.time = 0,
    this.frameMs = 0,
    this.delayMs = 0,
  });

  final LipSyncFrame frame;
  final double blink;
  final double time;
  final double frameMs;
  final double delayMs;
}

class _FacePainter extends CustomPainter {
  _FacePainter(this.state, this.colors, {required this.still})
    : super(repaint: state);

  final ValueNotifier<_PaintState> state;
  final LipSyncAvatarColors colors;
  final bool still;

  @override
  void paint(Canvas canvas, Size size) {
    final s = state.value;
    final r = size.shortestSide / 2;
    // Idle breathing plus a small nod with the voice; off for reduced motion.
    final bob = still
        ? 0.0
        : math.sin(s.time * 1.6) * r * 0.012 + s.frame.mouthOpen * r * 0.02;
    final center = Offset(size.width / 2, size.height / 2 + bob);

    canvas.drawCircle(center, r, Paint()..color = colors.face);

    final ink = Paint()..color = colors.ink;
    final eyeY = center.dy - r * 0.18;
    final eyeH = r * 0.16 * (1 - s.blink * 0.9);
    for (final dx in [-r * 0.32, r * 0.32]) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(center.dx + dx, eyeY),
          width: r * 0.12,
          height: math.max(eyeH, r * 0.02),
        ),
        ink,
      );
    }

    final f = s.frame;
    final mouthW = r * 0.42 * (1 + f.width);
    final mouthH = math.max(r * 0.05, r * 0.5 * f.mouthOpen);
    final mouth = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(center.dx, center.dy + r * 0.38),
        width: mouthW,
        height: mouthH,
      ),
      Radius.elliptical(mouthW / 2 * (0.4 + 0.6 * f.round), mouthH / 2),
    );
    canvas
      ..drawRRect(mouth, Paint()..color = colors.mouth)
      ..drawRRect(
        mouth,
        Paint()
          ..color = colors.ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.035,
      );
  }

  @override
  bool shouldRepaint(_FacePainter oldDelegate) =>
      oldDelegate.colors != colors || oldDelegate.still != still;
}
