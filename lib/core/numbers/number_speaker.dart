import '../audio/audio_manager.dart';
import '../audio/kokoro_voice.dart';
import '../audio/pcm_audio.dart';
import '../audio/speech_clip_player.dart';

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
  NumberSpeaker({SpeechClipPlayer? player, KokoroVoice? kokoro})
      : _player = player ?? AudioManager(),
        _kokoro = kokoro;

  final SpeechClipPlayer _player;
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
  }) async {
    final run = ++_runId;
    await _speakLine(sentenceForSpeech(sentence), accent: accent, rate: rate, run: run);
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
  }) =>
      speakRuns(
        [for (final sentence in sentences) <String>[sentence]],
        accent: accent,
        rate: rate,
        gap: gap,
        onIndex: onIndex,
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
  }) async {
    final run = ++_runId;
    final joinRow = innerGap == Duration.zero;

    for (var i = 0; i < rows.length; i++) {
      if (_stale(run)) return;
      onIndex?.call(i);
      final parts =
          joinRow && rows[i].length > 1 ? <String>[rows[i].join(', ')] : rows[i];
      if (parts.isEmpty) continue;

      if (parts.length == 1) {
        await _speakLine(sentenceForSpeech(parts.first), accent: accent, rate: rate, run: run);
      } else {
        await _speakRow(parts, accent: accent, rate: rate, innerGap: innerGap, run: run);
      }
      if (_stale(run) || i == rows.length - 1) return;
      await Future.delayed(gap);
    }
  }

  /// Renders every number of a row and plays the row as one clip, with
  /// [innerGap] of real silence between them.
  Future<bool> _speakRow(
    List<String> parts, {
    required String accent,
    required double rate,
    required Duration innerGap,
    required int run,
  }) async {
    final kokoro = _kokoro;
    if (kokoro == null) return false;

    final clips = <PcmClip>[];
    for (final part in parts) {
      if (_stale(run)) return false;
      final clip =
          await kokoro.synthesize(sentenceForSpeech(part), accent: accent, rate: rate);
      if (_stale(run)) return false;
      if (clip == null || clip.isEmpty) return false;
      clips.add(clip);
    }
    final joined = joinClips(
      clips,
      gaps: [for (var i = 0; i < clips.length - 1; i++) innerGap],
    );
    await _player.playAudioBytes(
      encodeWav(joined.samples, sampleRate: joined.sampleRate),
    );
    return true;
  }

  /// Reads one line with Kokoro. False when the model is missing or the line
  /// could not be rendered; nothing else takes over.
  Future<bool> _speakLine(
    String sentence, {
    required String accent,
    required double rate,
    required int run,
  }) async {
    final kokoro = _kokoro;
    if (kokoro == null) return false;
    // The model paces itself (`speed`), so the player must not scale the audio a
    // second time.
    final clip = await kokoro.synthesize(sentence, accent: accent, rate: rate);
    if (_stale(run)) return false;
    if (clip == null || clip.isEmpty) return false;
    await _player.playAudioBytes(
      encodeWav(clip.samples, sampleRate: clip.sampleRate),
    );
    return true;
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
