import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'core/audio/audio_manager.dart';
import 'core/audio/kokoro_model_store.dart';
import 'core/mdx/entry_speech.dart';
import 'providers/entry_speech_provider.dart';
import 'core/audio/kokoro_voice.dart';
import 'core/audio/pcm_audio.dart';
import 'core/audio/speech_clip_player.dart';
import 'core/numbers/number_speaker.dart';

/// On-device smoke test for the number module's speech engine.
///
/// This is a separate entry point, not part of the app: `tool/android_smoke.sh`
/// runs it on a connected phone and turns the `SMOKE …` lines below into a
/// pass/fail code. It answers the one question a host-side `flutter test` cannot:
/// does *this device* actually turn a number into audio?
///
/// There is one engine — Kokoro — so a missing model is a `skip` with the path
/// the model belongs at, not a failure.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final lines = <String>[];
  void say(String line) {
    lines.add(line);
    debugPrint(line);
  }

  await _checkKokoro(say);
  await _checkTiming(say);
  await _checkRunPacing(say);

  final failed = lines.any((line) => line.startsWith('SMOKE fail'));
  say(failed ? 'SMOKE failed' : 'SMOKE done');

  runApp(_SmokeApp(lines: lines, ok: !failed));
}

/// The sentence the engine is asked to say.
const String _sentence = 'Twenty-four.';

Future<void> _checkKokoro(void Function(String) say) async {
  final voice = KokoroVoice();
  try {
    final files = await findKokoroModel();
    if (files == null) {
      say('SMOKE skip kokoro: ${await kokoroModelHint()}');
      return;
    }
    final clip = await voice.synthesize(_sentence, accent: 'uk', rate: 1.0);
    if (clip == null || clip.sampleCount == 0) {
      say('SMOKE fail kokoro: 模型在 ${files.folder} 但没有合成出音频');
      return;
    }
    say('SMOKE ok kokoro ${clip.sampleCount} samples @ ${clip.sampleRate} Hz '
        '(${clip.duration.inMilliseconds} ms)');
    await AudioManager().playAudioBytes(
      encodeWav(clip.samples, sampleRate: clip.sampleRate),
    );
    say('SMOKE ok kokoro playback');
  } catch (e) {
    say('SMOKE fail kokoro: $e');
  } finally {
    voice.dispose();
  }
}

/// How long a reader actually waits: model load, first sound, and whether a 1 s
/// gap is the gap between lines rather than gap + synthesis.
Future<void> _checkTiming(void Function(String) say) async {
  try {
    final voice = KokoroVoice();
    final loadWatch = Stopwatch()..start();
    final ready = await voice.isReady();
    say('SMOKE timing load ${loadWatch.elapsedMilliseconds} ms ready=$ready');
    if (!ready) return;

    final firstWatch = Stopwatch()..start();
    await voice.synthesize('One.', accent: 'us', rate: 1.0);
    say('SMOKE timing first line ${firstWatch.elapsedMilliseconds} ms');

    final secondWatch = Stopwatch()..start();
    await voice.synthesize('Two.', accent: 'us', rate: 1.0);
    say('SMOKE timing next line ${secondWatch.elapsedMilliseconds} ms');

    // Three lines, 1 s apart, through the real player and the real pipeline.
    final speech = EntrySpeechProvider(kokoro: voice);
    final runWatch = Stopwatch()..start();
    await speech.playAll(
      const [
        EntryUtterance(text: 'One.', isPhrase: false),
        EntryUtterance(text: 'Two.', isPhrase: false),
        EntryUtterance(text: 'Three.', isPhrase: false),
      ],
      rate: 1.0,
      gap: const Duration(seconds: 1),
      accent: 'us',
    );
    final total = runWatch.elapsedMilliseconds;
    say('SMOKE timing three lines @1s gap: $total ms '
        '(${(total - 2000) ~/ 3} ms of audio each, synthesis overlapped)');
  } catch (e) {
    say('SMOKE fail timing: $e');
  }
}

/// 组内间隔 has to be audible: 0 means the row is read as one sentence, a gap
/// means one utterance per number joined with exactly that silence.
Future<void> _checkRunPacing(void Function(String) say) async {
  try {
    final rows = <List<String>>[
      ['twenty-four', 'thirty-one'],
    ];
    final player = _RecordingAudio();
    final speaker = NumberSpeaker(player: player, kokoro: KokoroVoice());

    await speaker.speakRuns(rows, accent: 'uk', innerGap: Duration.zero);
    final joined = player.buffers.length;
    player.buffers.clear();
    player.sentences.clear();

    final watch = Stopwatch()..start();
    await speaker.speakRuns(rows, accent: 'uk', innerGap: const Duration(milliseconds: 200));
    final buffers = player.buffers.length;

    if (joined == 0) {
      say('SMOKE skip runs: 没有模型，无法比较组内间隔');
      return;
    }
    if (joined != 1) {
      say('SMOKE fail runs: 组内 0 应把整行并成一句，实际 $joined 次');
      return;
    }
    if (buffers != 2) {
      say('SMOKE fail runs: 有间隔时每个数字一段音频，实际 $buffers 次');
      return;
    }
    final elapsed = watch.elapsedMilliseconds;
    if (elapsed < 190) {
      say('SMOKE fail runs: 组内间隔只有 $elapsed ms，设定是 200 ms');
      return;
    }
    say('SMOKE ok runs $elapsed ms for a 200 ms gap');
  } catch (e) {
    say('SMOKE fail runs: $e');
  }
}

class _RecordingAudio implements SpeechClipPlayer {
  final List<String> sentences = [];
  final List<String> played = [];
  final List<Uint8List> buffers = [];
  final List<String> singleWords = [];

  @override
  Future<void> playSpeechClip(String assetPath, {double rate = 1.0}) async {
    singleWords.add(assetPath);
  }

  @override
  Future<bool> playAudioBytes(Uint8List bytes, {double rate = 1.0}) async {
    buffers.add(bytes);
    return true;
  }

  @override
  Future<void> stop() async {}
}

class _SmokeApp extends StatelessWidget {
  const _SmokeApp({required this.lines, required this.ok});

  final List<String> lines;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: Text(ok ? '自检通过' : '自检失败')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final line in lines)
              Text(line, style: const TextStyle(fontFamily: 'monospace')),
          ],
        ),
      ),
    );
  }
}
