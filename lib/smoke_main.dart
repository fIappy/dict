import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'core/audio/audio_manager.dart';
import 'core/audio/pcm_audio.dart';
import 'core/audio/piper_model_store.dart';
import 'core/audio/piper_voice.dart';
import 'core/audio/sentence_voice.dart';
import 'core/audio/speech_clip_player.dart';
import 'core/numbers/number_speaker.dart';
import 'core/numbers/sentence_engine.dart';

/// On-device smoke test for the number module's speech engines.
///
/// This is a separate entry point, not part of the app: `tool/android_smoke.sh`
/// runs it on a connected phone and turns the `SMOKE …` lines below into a
/// pass/fail code. It answers the one question a host-side `flutter test` cannot:
/// does *this device* actually turn a number into audio —
///
///  * **录音拼接** needs nothing but the bundled assets, so it runs on a
///    freshly installed app;
///  * **Piper** runs when a model has been installed and reports `skip` when it
///    has not (that is a normal state, not a failure);
///  * **系统语音** asks the platform voice to say the same number.
///
/// Every engine's audio is also handed to the real player, so the person holding
/// the phone hears the result — a failure there is reported, not swallowed.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final lines = <String>[];
  void say(String line) {
    lines.add(line);
    debugPrint(line);
  }

  await _checkSpliced(say);
  await _checkPiper(say);
  await _checkFallback(say);
  await _checkRunPacing(say);

  final failed = lines.any((line) => line.startsWith('SMOKE fail'));
  say(failed ? 'SMOKE failed' : 'SMOKE done');

  runApp(_SmokeApp(lines: lines, ok: !failed));
}

/// The sentence every engine is asked to say, and the way a two-digit number
/// reaches the engines (see [NumberSpeaker]).
const String _sentence = 'twenty-four';

Future<void> _checkSpliced(void Function(String) say) async {
  try {
    // The buffer is what is checked, so it is captured instead of played here;
    // it is played once below, through the real player.
    final buffers = <List<int>>[];
    final spoken = await SplicedSentence(player: _CapturingPlayer(buffers)).speak(
      _sentence,
      accent: 'uk',
      rate: 1.0,
    );
    if (!spoken || buffers.isEmpty) {
      say('SMOKE fail splice: no audio for $_sentence');
      return;
    }
    final clip = decodeWav(Uint8List.fromList(buffers.first));
    if (clip.sampleCount == 0) {
      say('SMOKE fail splice: empty buffer');
      return;
    }
    say('SMOKE ok splice ${clip.sampleCount} samples @ ${clip.sampleRate} Hz '
        '(${clip.duration.inMilliseconds} ms)');
    await AudioManager().playAudioBytes(
      encodeWav(clip.samples, sampleRate: clip.sampleRate),
    );
    say('SMOKE ok splice playback');
  } catch (e) {
    say('SMOKE fail splice: $e');
  }
}

Future<void> _checkPiper(void Function(String) say) async {
  final piper = PiperVoice();
  try {
    for (final accent in const ['uk', 'us']) {
      final files = await findPiperModel(accent);
      if (files == null) {
        say('SMOKE skip piper-$accent: 未安装模型');
        continue;
      }
      final clip = await piper.synthesize('Twenty-four.', accent: accent, rate: 1.0);
      if (clip == null || clip.sampleCount == 0) {
        say('SMOKE fail piper-$accent: 模型在 ${files.folder} 但没有合成出音频');
        continue;
      }
      say('SMOKE ok piper-$accent ${clip.sampleCount} samples @ ${clip.sampleRate} Hz');
      await AudioManager().playAudioBytes(
        encodeWav(clip.samples, sampleRate: clip.sampleRate),
      );
      say('SMOKE ok piper-$accent playback');
    }
  } catch (e) {
    say('SMOKE fail piper: $e');
  } finally {
    piper.dispose();
  }
}

/// The app's own default is the host voice, and plenty of phones have no English
/// TTS installed. What must *not* happen then is the number being read as two
/// separate words; another engine has to take the sentence over.
Future<void> _checkFallback(void Function(String) say) async {
  try {
    final player = _RecordingAudio();
    final speaker = NumberSpeaker(player: player, piper: PiperVoice());
    final voice = await chosenSentenceVoice('uk');
    say('SMOKE voice system: ${voice?.name ?? '无（本机没有英语语音）'}');
    speaker.engine = SentenceEngine.system;

    await speaker.speak('twenty-four', accent: 'uk', rate: 1.0);
    final by = speaker.spokenBy;
    if (player.singleWords.isNotEmpty) {
      say('SMOKE fail fallback: 整句朗读退化成了逐词播放 '
          '(${player.singleWords.length} 段: ${player.singleWords.take(2).join(', ')})');
      return;
    }
    if (by == null) {
      say('SMOKE fail fallback: 没有任何引擎念出 twenty-four');
      return;
    }
    say('SMOKE ok sentence: twenty-four 由 ${by.labelZh} 整句念出'
        '${by == SentenceEngine.system ? '' : '（选中的系统语音不可用）'}');
  } catch (e) {
    say('SMOKE fail fallback: $e');
  }
}

/// 组内间隔 has to be audible: 0 means the row is read as one sentence, a gap
/// means one utterance per number. It used to be swallowed by always joining the
/// row, which is why the slider looked dead.
Future<void> _checkRunPacing(void Function(String) say) async {
  try {
    final rows = <List<String>>[
      ['twenty-four', 'thirty-one'],
    ];
    final player = _RecordingAudio();
    final speaker = NumberSpeaker(player: player, piper: PiperVoice())
      ..engine = SentenceEngine.piper;

    await speaker.speakRuns(rows, accent: 'uk', innerGap: Duration.zero);
    // One continuous reading, whichever way the engine delivers it: the host's
    // voice answers through speakSentence, a model answers as one buffer.
    final joined = player.sentences.length + player.buffers.length;

    player.sentences.clear();
    player.buffers.clear();
    await speaker.speakRuns(rows, accent: 'uk', innerGap: const Duration(milliseconds: 200));
    final buffers = player.buffers.length;
    final seconds = player.buffers.isEmpty
        ? 0.0
        : decodeWav(player.buffers.first).duration.inMilliseconds / 1000;
    final words = player.singleWords.length;

    if (joined != 1) {
      say('SMOKE fail runs: 组内 0 应把整行并成一句，实际 $joined 次');
      return;
    }
    if (buffers != 1 || words != 0) {
      say('SMOKE fail runs: 组内 0.2 s 应渲染成 1 段整行音频，'
          '实际 $buffers 段 + $words 次逐词');
      return;
    }
    if (seconds < 0.2) {
      say('SMOKE fail runs: 组内 0.2 s 没写进音频（整行只有 ${seconds}s）');
      return;
    }
    say('SMOKE ok runs: 组内 0 → 1 次整句；组内 0.2 s → 1 段整行音频 ${seconds}s'
        '（间隔写在音频里，不等合成）');
  } catch (e) {
    say('SMOKE fail runs: $e');
  }
}

/// Forwards to the real player and remembers how the audio arrived, so a check
/// can tell "one sentence by an engine" from "word by word by the player".
class _RecordingAudio implements SpeechClipPlayer {
  final AudioManager _inner = AudioManager();
  final List<String> singleWords = [];
  final List<String> sentences = [];
  /// Whole buffers handed over by the engines that build their own audio.
  final List<Uint8List> buffers = [];

  @override
  Future<void> playSpeechClip(String assetPath, {double rate = 1.0}) async {
    singleWords.add(assetPath);
    await _inner.playSpeechClip(assetPath, rate: rate);
  }

  @override
  Future<void> playAudioBytes(Uint8List bytes, {double rate = 1.0}) async {
    buffers.add(bytes);
    await _inner.playAudioBytes(bytes, rate: rate);
  }

  @override
  Future<bool> speakSentence(String sentence, {String accent = 'us', double rate = 1.0}) async {
    sentences.add(sentence);
    return _inner.speakSentence(sentence, accent: accent, rate: rate);
  }

  @override
  Future<String?> sentenceVoiceLabel(String accent) => _inner.sentenceVoiceLabel(accent);

  @override
  Future<void> stop() => _inner.stop();
}

/// Keeps the buffer the splicer handed over instead of playing it.
class _CapturingPlayer implements SpeechClipPlayer {
  _CapturingPlayer(this.buffers);

  final List<List<int>> buffers;

  @override
  Future<void> playSpeechClip(String assetPath, {double rate = 1.0}) async {}

  @override
  Future<void> playAudioBytes(Uint8List bytes, {double rate = 1.0}) async {
    buffers.add(bytes);
  }

  @override
  Future<bool> speakSentence(String sentence, {String accent = 'us', double rate = 1.0}) async => false;

  @override
  Future<String?> sentenceVoiceLabel(String accent) async => null;

  @override
  Future<void> stop() async {}
}

/// Shows the same lines the script reads, so the phone itself says what happened.
class _SmokeApp extends StatelessWidget {
  const _SmokeApp({required this.lines, required this.ok});

  final List<String> lines;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(title: Text(ok ? '发音自检：通过' : '发音自检：失败')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  line,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12.5,
                    color: line.startsWith('SMOKE fail') ? Colors.red : null,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
