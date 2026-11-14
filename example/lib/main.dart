import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:avatar_lipsync/avatar_lipsync.dart';
import 'package:avatar_lipsync_example/sources/synthetic_speech.dart';
import 'package:avatar_lipsync_example/sources/web_audio_speech_source.dart';
import 'package:material_ui/material_ui.dart';
import 'package:web/web.dart' as web;

void main() => runApp(const MaterialApp(home: DemoPage()));

class DemoPage extends StatefulWidget {
  const DemoPage({super.key});

  @override
  State<DemoPage> createState() => _DemoPageState();
}

enum _Face { photo, drawn }

class _DemoPageState extends State<DemoPage> {
  final _source = WebAudioSpeechSource();
  _Face _face = _Face.photo;
  var _debug = false;

  static const _colors = LipSyncAvatarColors(
    face: Color(0xFFF2D3B3),
    ink: Color(0xFF3B2A20),
    mouth: Color(0xFF6B1F2A),
  );

  @override
  void dispose() {
    unawaited(_source.dispose());
    super.dispose();
  }

  Future<void> _pickFile() async {
    final input = web.HTMLInputElement()
      ..type = 'file'
      ..accept = 'audio/*'
      ..click();
    await input.onChange.first;
    final file = input.files?.item(0);
    if (file == null) return;
    final bytes = await file.arrayBuffer().toDart;
    await _source.playFile(Uint8List.view(bytes.toDart));
  }

  @override
  Widget build(BuildContext context) {
    final drawn = LipSyncAvatar(
      source: _source,
      colors: _colors,
      size: 220,
      showDebug: _debug,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('avatar_lipsync')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<_Face>(
              segments: const [
                ButtonSegment(value: _Face.photo, label: Text('Photo')),
                ButtonSegment(value: _Face.drawn, label: Text('Drawn')),
              ],
              selected: {_face},
              onSelectionChanged: (s) => setState(() => _face = s.first),
            ),
            const SizedBox(height: 24),
            SizedBox.square(
              dimension: 360,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: switch (_face) {
                  // Rigs the photo once (MediaPipe, in the browser), then
                  // animates it. Shows `fallback` if no face is found.
                  _Face.photo => PhotoLipSyncAvatar(
                    source: _source,
                    imageAsset: 'assets/face.jpg',
                    fallback: drawn,
                    showDebug: _debug,
                  ),
                  _Face.drawn => Center(child: drawn),
                },
              ),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.record_voice_over),
                  label: const Text('Say something'),
                  onPressed: () =>
                      _source.play(syntheticSpeech(), syntheticSampleRate),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.audio_file),
                  label: const Text('Play an audio file'),
                  onPressed: _pickFile,
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop'),
                  onPressed: _source.stop,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch(
                  value: _debug,
                  onChanged: (v) => setState(() => _debug = v),
                ),
                const Text('Debug overlay'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
