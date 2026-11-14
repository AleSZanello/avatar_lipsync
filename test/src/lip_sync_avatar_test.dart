import 'package:avatar_lipsync/avatar_lipsync.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

const _colors = LipSyncAvatarColors(
  face: Color(0xFFEEDDCC),
  ink: Color(0xFF222222),
  mouth: Color(0xFF660000),
);

Widget _wrap(Widget child) => MediaQuery(
  data: const MediaQueryData(),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: Center(child: child),
  ),
);

void main() {
  testWidgets('follows the source frame by frame', (tester) async {
    final source = FakeSource()..audibleTime = 0;
    final frames = <LipSyncFrame>[];
    await tester.pumpWidget(
      _wrap(
        LipSyncAvatar(source: source, colors: _colors, onFrame: frames.add),
      ),
    );
    source.schedule(vowel(Viseme.a, seconds: 0.5));
    for (var i = 0; i < 20; i++) {
      source.audibleTime = i / 60;
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(frames.last.viseme, isNot(Viseme.rest));
    expect(frames.last.mouthOpen, greaterThan(0.3));

    for (var i = 0; i < 30; i++) {
      source.audibleTime = 0.6 + i / 120;
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(frames.last.mouthOpen, lessThan(0.05));
  });

  testWidgets('shows live numbers in debug mode', (tester) async {
    await tester.pumpWidget(
      _wrap(
        LipSyncAvatar(source: FakeSource(), colors: _colors, showDebug: true),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.textContaining('rest'), findsOneWidget);
    expect(find.textContaining('sync -30 ms'), findsOneWidget);
  });

  testWidgets('blinks and still paints with reduced motion', (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: LipSyncAvatar(source: FakeSource(), colors: _colors),
      ),
    );
    for (var i = 0; i < 400; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.byType(CustomPaint), findsWidgets);
  });
}
