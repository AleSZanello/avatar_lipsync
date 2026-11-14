import 'dart:async';
import 'dart:ui' as ui;

import 'package:avatar_lipsync/avatar_lipsync.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';
import 'photo_helpers.dart';

Widget _wrap(Widget child) => MediaQuery(
  data: const MediaQueryData(),
  child: Directionality(textDirection: TextDirection.ltr, child: child),
);

class _ThrowingDetector implements FaceLandmarkDetector {
  @override
  Future<FaceLandmarks?> detectAsset(String assetKey) =>
      Future.error(StateError('no model'));
}

Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 200)),
  );
  await tester.pump();
}

void main() {
  group(PhotoLipSyncAvatar, () {
    testWidgets('talks: frames follow the source', (tester) async {
      final source = FakeSource()..audibleTime = 0;
      final frames = <LipSyncFrame>[];
      await tester.pumpWidget(
        _wrap(
          PhotoLipSyncAvatar(
            source: source,
            imageAsset: facePhoto,
            detector: FixtureDetector(),
            imageLoader: loadFixtureImage,
            showDebug: true,
            onFrame: frames.add,
          ),
        ),
      );
      await _settle(tester);
      source.schedule(vowel(Viseme.a, seconds: 0.5));
      for (var i = 0; i < 20; i++) {
        source.audibleTime = i / 60;
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(frames, isNotEmpty);
      expect(frames.last.mouthOpen, greaterThan(0.3));
      expect(find.textContaining('mesh'), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('shows the fallback when no face is found', (tester) async {
      await tester.pumpWidget(
        _wrap(
          PhotoLipSyncAvatar(
            source: FakeSource(),
            imageAsset: facePhoto,
            detector: FixtureDetector(found: false),
            imageLoader: loadFixtureImage,
            fallback: const Text('fallback'),
          ),
        ),
      );
      await _settle(tester);
      expect(find.text('fallback'), findsOneWidget);
    });

    testWidgets('shows the fallback when detection fails', (tester) async {
      await tester.pumpWidget(
        _wrap(
          PhotoLipSyncAvatar(
            source: FakeSource(),
            imageAsset: facePhoto,
            detector: _ThrowingDetector(),
            imageLoader: loadFixtureImage,
            fallback: const Text('fallback'),
          ),
        ),
      );
      await _settle(tester);
      expect(find.text('fallback'), findsOneWidget);
    });

    testWidgets('paints nothing until the photo decodes', (tester) async {
      await tester.pumpWidget(
        _wrap(
          PhotoLipSyncAvatar(
            source: FakeSource(),
            imageAsset: facePhoto,
            detector: FixtureDetector(),
            imageLoader: (_) => Completer<ui.Image>().future,
          ),
        ),
      );
      expect(find.byType(CustomPaint), findsNothing);
    });
  });
}
