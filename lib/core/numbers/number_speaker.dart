import 'dart:typed_data';

import '../audio/audio_manager.dart';
import '../audio/kokoro_voice.dart';
import '../audio/pcm_audio.dart';
import '../audio/speech_clip_player.dart';
import '../audio/online_audio_cache.dart';
import '../audio/online_tts.dart';
import '../audio/speech_engine.dart';

/// Plays a number sentence.
///
/// A number sentence is generated rather than recorded ("one thousand and
/// twenty-three"), so Kokoro renders it as audio; a comma — which [NumberSpeller]
/// writes at every phone-number group boundary — becomes a short pause, and the
/// training module adds the interval between whole items on top of that.
///
/// This is the only engine: when the model is missing nothing is spoken, and the
/// UI says so. There is no host-voice or recorded-word fallback on purpose —
/// switching engines mid-drill changes the timbre.
///
/// The UI can stop a run instantly: every async step carries the id of the run it
/// belongs to and drops out once that id is superseded, and [cancel] also
/// silences whatever is sounding.
class NumberSpeaker {
  NumberSpeaker({
    SpeechClipPlayer? player,
    KokoroVoice? kokoro,
    OnlineSynthesizer? online,
  })  : _player = player ?? AudioManager(),
        _kokoro = kokoro,
        _online = online ?? OnlineAudioCache.instance.synthesize;

  final SpeechClipPlayer _player;

  /// How a sentence becomes MP3 for the online engines; injectable for tests.
  final OnlineSynthesizer _online;
  final KokoroVoice? _kokoro;

  /// Pause inserted where the sentence has a comma (phone-number groups).
  static const Duration groupPause = Duration(milliseconds: 200);

  /// Monotonic run id, bumped by every start and every stop.
  ///
  /// An async step captures the id it began under and drops out as soon as the
  /// id changes: a run abandoned mid-`await` would otherwise wake up and talk
  /// over the run that replaced it — the overlapping speech (串音) this prevents.
  int _runId = 0;

  bool _stale(int runId) => runId != _runId;

  /// Speaks one sentence, e.g. `NumberSpeller.read('1234')!.ukText`.
  Future<void> speak(
    String sentence, {
    String accent = 'uk',
    double rate = 1.0,
    SpeechEngine engine = SpeechEngine.kokoro,
    double volume = 1.0,
  }) async {
    final run = ++_runId;
    await _player.setVolume(volume);
    final line = await _render(sentence,
        engine: engine, accent: accent, rate: rate);
    await _play(line, run: run, engine: engine, text: sentence,
        accent: accent, rate: rate);
  }

  /// Speaks [sentences] one after another, waiting [gap] between them.
  ///
  /// [onIndex] reports which item is sounding so the UI can mark it; it is called
  /// before the item starts.
  Future<void> speakAll(
    List<String> sentences, {
    String accent = 'uk',
    double rate = 1.0,
    Duration gap = const Duration(seconds: 1),
    void Function(int index)? onIndex,
    SpeechEngine engine = SpeechEngine.kokoro,
    double volume = 1.0,
  }) =>
      speakRuns(
        [for (final sentence in sentences) <String>[sentence]],
        accent: accent,
        rate: rate,
        gap: gap,
        onIndex: onIndex,
        engine: engine,
        volume: volume,
      );

  /// Speaks [rows] one after another, where each row is a short run of sentences
  /// read back to back (整数 mode's 多组 option).
  ///
  /// Inside a row the numbers follow [innerGap] apart; rows are [gap] apart,
  /// which is the pause a learner writes a group down in.
  ///
  /// At `innerGap == 0` a whole row goes to the engine as **one** sentence — its
  /// commas carry the rhythm, which is what 连读 means and what "组内间隔 0 = 连读"
  /// promises. With a gap set, each number is rendered separately and the clips
  /// are joined with exactly that much silence, so the slider means what it says.
  Future<void> speakRuns(
    List<List<String>> rows, {
    String accent = 'uk',
    double rate = 1.0,
    Duration innerGap = const Duration(milliseconds: 80),
    Duration gap = const Duration(seconds: 1),
    void Function(int index)? onIndex,
    SpeechEngine engine = SpeechEngine.kokoro,
    double volume = 1.0,
  }) async {
    final run = ++_runId;
    await _player.setVolume(volume);
    final joinRow = innerGap == Duration.zero;

    for (var i = 0; i < rows.length; i++) {
      if (_stale(run)) return;
      onIndex?.call(i);
      final parts =
          joinRow && rows[i].length > 1 ? <String>[rows[i].join(', ')] : rows[i];
      if (parts.isEmpty) continue;

      // Render the next number while this one sounds: synthesis is the slow
      // part, and waiting for it after the gap is what made a 1 s gap feel like
      // three.
      var pending = _render(parts.first,
          engine: engine, accent: accent, rate: rate);
      for (var j = 0; j < parts.length; j++) {
        if (_stale(run)) return;
        final line = await pending;
        if (j + 1 < parts.length) {
          pending = _render(parts[j + 1],
              engine: engine, accent: accent, rate: rate);
        }
        await _play(line, run: run, engine: engine, text: parts[j],
            accent: accent, rate: rate);
        if (_stale(run)) return;
        if (j < parts.length - 1) await Future<void>.delayed(innerGap);
      }
      if (i == rows.length - 1) return;
      await Future<void>.delayed(gap);
    }
  }

  /// The audio for one line, or null when the platform voice should read it.
  Future<_NumberLine?> _render(
    String text, {
    required SpeechEngine engine,
    required String accent,
    required double rate,
  }) async {
    final spoken = sentenceForSpeech(text);
    if (engine.isOnline) {
      final bytes = await _online(engine, text: spoken, accent: accent, rate: rate);
      if (bytes != null && bytes.isNotEmpty) return _NumberLine.mp3(bytes);
      // The service answered nothing: speak the line rather than skip it.
      return null;
    }
    if (engine == SpeechEngine.system) return null;
    final kokoro = _kokoro;
    if (kokoro == null) return null;
    final clip = await kokoro.synthesize(spoken, accent: accent, rate: rate);
    return clip == null ? null : _NumberLine.pcm(clip);
  }

  /// Sounds one rendered line.
  Future<bool> _play(
    _NumberLine? line, {
    required int run,
    required SpeechEngine engine,
    required String text,
    required String accent,
    required double rate,
  }) async {
    if (_stale(run)) return false;
    if (line == null) {
      return _player.speakSentence(text, accent: accent, rate: rate);
    }
    if (line.mp3 != null) {
      // Edge and 百度 bake the speed into the clip; Google's endpoint cannot, so
      // there the player scales it.
      await _player.playOnlineClip(line.mp3!,
          rate: engine.bakesRate ? 1.0 : rate);
      return !_stale(run);
    }
    final clip = line.clip;
    if (clip == null || clip.isEmpty) return false;
    // The model paces itself (`speed`), so the player must not scale the audio a
    // second time.
    await _player.playAudioBytes(
      encodeWav(clip.samples, sampleRate: clip.sampleRate),
    );
    return !_stale(run);
  }

  /// Stops the current run: the run id moves on, so every step still in flight
  /// — a render, a pending pause — drops out instead of resuming, and whatever
  /// is sounding right now is silenced.
  void cancel() {
    _runId++;
    _player.stop();
  }
}

/// The text the engine should read for [text].
///
/// Engines take their sentence prosody from punctuation, so a bare phrase gets a
/// capital and a full stop even though the card shows it without them.
String sentenceForSpeech(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return trimmed;
  final capitalised =
      trimmed[0].toUpperCase() + (trimmed.length > 1 ? trimmed.substring(1) : '');
  return RegExp(r'[.!?]$').hasMatch(capitalised) ? capitalised : '$capitalised.';
}

/// One number line ready to sound: local samples, or an online voice's MP3.
class _NumberLine {
  const _NumberLine.pcm(PcmClip this.clip) : mp3 = null;
  const _NumberLine.mp3(Uint8List this.mp3) : clip = null;

  final PcmClip? clip;
  final Uint8List? mp3;
}
