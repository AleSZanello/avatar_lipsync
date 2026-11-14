import 'dart:async';

import 'package:avatar_lipsync/avatar_lipsync.dart';
import 'package:avatar_lipsync_example/sources/mic_speech_source.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:material_ui/material_ui.dart';
import 'package:web/web.dart' as web;

void main() => runApp(const DemoApp());

const _accent = Color(0xFF7C9CFF);

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'avatar_lipsync · live demo',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _accent,
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xFF0E1015),
    ),
    home: const DemoPage(),
  );
}

enum Face {
  micaela('Micaela', 'assets/micaela.jpg'),
  portrait('1880 portrait', 'assets/portrait_1880.jpg'),
  drawn('Drawn', null);

  Face(this.label, this.asset);
  final String label;
  final String? asset;
}

class DemoPage extends StatefulWidget {
  const DemoPage({super.key});

  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {
  final _source = MicSpeechSource();
  final _frame = ValueNotifier<LipSyncFrame?>(null);
  Face _face = Face.micaela;
  bool _mesh = false;
  bool _landmarks = false;
  RigRegion? _heat = RigRegion.motion;
  bool _starting = false;
  String? _error;

  @override
  void dispose() {
    unawaited(_source.dispose());
    _frame.dispose();
    super.dispose();
  }

  Future<void> _toggleMic() async {
    if (_source.isListening) {
      await _source.stop();
      setState(() {});
      return;
    }
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      await _source.start();
    } on Object {
      _error =
          'The microphone is not available. Allow it in the browser and '
          'try again.';
    }
    setState(() => _starting = false);
  }

  RigOverlay get _overlay =>
      RigOverlay(mesh: _mesh, landmarks: _landmarks, heat: _heat);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) {
            final wide = box.maxWidth >= 920;
            final stage = _Stage(
              face: _face,
              source: _source,
              overlay: _overlay,
              onFrame: (f) => _frame.value = f,
            );
            final panel = _Panel(
              face: _face,
              listening: _source.isListening,
              starting: _starting,
              error: _error,
              mesh: _mesh,
              landmarks: _landmarks,
              heat: _heat,
              frame: _frame,
              onMic: _toggleMic,
              onFace: (f) => setState(() => _face = f),
              onMesh: (v) => setState(() => _mesh = v),
              onLandmarks: (v) => setState(() => _landmarks = v),
              onHeat: (v) => setState(() => _heat = v),
            );
            final content = wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: stage),
                      const SizedBox(width: 32),
                      SizedBox(width: 380, child: panel),
                    ],
                  )
                : Column(children: [stage, const SizedBox(height: 24), panel]);
            return SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: wide ? 40 : 16,
                vertical: 24,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1240),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _Header(),
                      const SizedBox(height: 24),
                      content,
                      const SizedBox(height: 32),
                      const _Footer(),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'avatar_lipsync',
          style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          'A photo that lip-syncs to your voice in real time. Turn on the '
          'microphone and talk.',
          style: text.bodyLarge?.copyWith(color: Colors.white70),
        ),
      ],
    );
  }
}

class _Stage extends StatelessWidget {
  const _Stage({
    required this.face,
    required this.source,
    required this.overlay,
    required this.onFrame,
  });

  final Face face;
  final LipSyncSource source;
  final RigOverlay overlay;
  final ValueChanged<LipSyncFrame> onFrame;

  @override
  Widget build(BuildContext context) {
    final drawn = Center(
      child: LipSyncAvatar(
        source: source,
        colors: const LipSyncAvatarColors(
          face: Color(0xFFF2D3B3),
          ink: Color(0xFF3B2A20),
          mouth: Color(0xFF6B1F2A),
        ),
        size: 300,
        onFrame: onFrame,
      ),
    );
    final asset = face.asset;
    return AspectRatio(
      aspectRatio: 1,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: ColoredBox(
          color: const Color(0xFF1A1D25),
          child: asset == null
              ? drawn
              : PhotoLipSyncAvatar(
                  key: ValueKey(face),
                  source: source,
                  imageAsset: asset,
                  overlay: overlay,
                  onFrame: onFrame,
                  fallback: drawn,
                ),
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.face,
    required this.listening,
    required this.starting,
    required this.error,
    required this.mesh,
    required this.landmarks,
    required this.heat,
    required this.frame,
    required this.onMic,
    required this.onFace,
    required this.onMesh,
    required this.onLandmarks,
    required this.onHeat,
  });

  final Face face;
  final bool listening;
  final bool starting;
  final String? error;
  final bool mesh;
  final bool landmarks;
  final RigRegion? heat;
  final ValueListenable<LipSyncFrame?> frame;
  final VoidCallback onMic;
  final ValueChanged<Face> onFace;
  final ValueChanged<bool> onMesh;
  final ValueChanged<bool> onLandmarks;
  final ValueChanged<RigRegion?> onHeat;

  @override
  Widget build(BuildContext context) {
    final photo = face != Face.drawn;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 52,
          child: FilledButton.icon(
            onPressed: starting ? null : onMic,
            icon: Icon(listening ? Icons.mic_off : Icons.mic),
            label: Text(
              listening ? 'Stop the microphone' : 'Turn on the microphone',
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          error ??
              (listening
                  ? 'Listening. Talk, sing, read something out loud.'
                  : 'Everything runs in your browser: your voice is not '
                        'recorded or sent anywhere.'),
          style: TextStyle(
            color: error == null ? Colors.white60 : Colors.redAccent,
            fontSize: 13,
          ),
        ),
        const _Section('Face'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final f in Face.values)
              ChoiceChip(
                label: Text(f.label),
                selected: f == face,
                onSelected: (_) => onFace(f),
              ),
          ],
        ),
        const _Section('See how it moves'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilterChip(
              label: const Text('Mesh'),
              selected: mesh,
              onSelected: photo ? onMesh : null,
            ),
            FilterChip(
              label: const Text('478 landmarks'),
              selected: landmarks,
              onSelected: photo ? onLandmarks : null,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Heat map',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (label, region) in const [
              ('Off', null),
              ('Live motion', RigRegion.motion),
              ('Jaw', RigRegion.jaw),
              ('Lips', RigRegion.lips),
              ('Corners', RigRegion.corners),
              ('Eyelids', RigRegion.eyelids),
              ('Brows', RigRegion.brows),
              ('Head', RigRegion.head),
            ])
              ChoiceChip(
                label: Text(label),
                selected: heat == region,
                onSelected: photo ? (_) => onHeat(region) : null,
              ),
          ],
        ),
        const _Section('Live mouth'),
        _Meters(frame: frame),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 28, bottom: 10),
    child: Text(
      title.toUpperCase(),
      style: const TextStyle(
        fontSize: 12,
        letterSpacing: 1.2,
        fontWeight: FontWeight.w600,
        color: _accent,
      ),
    ),
  );
}

class _Meters extends StatelessWidget {
  const _Meters({required this.frame});

  final ValueListenable<LipSyncFrame?> frame;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: frame,
    builder: (context, f, _) {
      final rows = <(String, double)>[
        ('Loudness', f?.level ?? 0),
        ('Open', f?.mouthOpen ?? 0),
        ('Jaw', ((f?.jaw ?? 0) / 0.12).clamp(0, 1)),
        ('Round', f?.round ?? 0),
        ('Spread', ((f?.width ?? 0) / 0.18).clamp(0, 1)),
        ('Lips pressed', f?.press ?? 0),
      ];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Shape', style: TextStyle(color: Colors.white60)),
              const SizedBox(width: 12),
              Text(
                (f == null || !f.speaking) ? '—' : f.viseme.name,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 104,
                    child: Text(
                      label,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: value.clamp(0.0, 1.0),
                        minHeight: 8,
                        backgroundColor: Colors.white10,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    },
  );
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(color: Colors.white54, fontSize: 13);
    Widget link(String label, String url) => InkWell(
      onTap: () => web.window.open(url, '_blank'),
      child: Text(
        label,
        style: style.copyWith(
          color: _accent,
          decoration: TextDecoration.underline,
          decorationColor: _accent,
        ),
      ),
    );
    return Wrap(
      spacing: 18,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        link('GitHub', 'https://github.com/AleSZanello/avatar_lipsync'),
        link('pub.dev', 'https://pub.dev/packages/avatar_lipsync'),
        const Text('Photo:', style: style),
        link('@micaela_valente', 'https://www.instagram.com/micaela_valente/'),
        const Text(
          '1880 portrait: Paris Musées, CC0. Face points by MediaPipe.',
          style: style,
        ),
      ],
    );
  }
}
