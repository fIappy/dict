import '../audio/audio_manager.dart';
import '../audio/speech_clip_player.dart';
import 'number_audio.dart';

/// How the module speaks a number.
///
/// [sentence] hands the whole sentence to the system voice, which is what makes
/// "one thousand two hundred and thirty-four" sound like one utterance: recorded
/// words played back to back keep each word's citation form, so they sound like a
/// list of words. [clips] is the fully offline path with the module's own
/// recordings in both accents, and it is also what [sentence] falls back to when
/// the platform has no usable voice.
enum SpeechMode {
  sentence('整句朗读', '整句交给本机语音合成，连读与语调自然（不联网）'),
  clips('逐词拼读', '只播单词录音：完全离线，英美两种口音都来自录音');

  final String labelZh;
  final String hint;
  const SpeechMode(this.labelZh, this.hint);
}

/// Plays a number sentence.
///
/// A number sentence is generated rather than recorded ("one thousand and
/// twenty-three"), so it is assembled from the single-word clips in
/// `assets/audio/numbers/`: one clip per word, played back to back. A comma in
/// the sentence — which [NumberSpeller] writes at every phone-number group
/// boundary — becomes a short pause, and the training module adds the interval
/// between whole items on top of that.
///
/// The class owns no state that survives a call except [isCancelled], so the UI
/// can stop a run instantly: every word checks the flag before it plays, and
/// [cancel] also stops the clip that is already sounding.
/// Resolves the clips that exist for one word in one accent.
///
/// Defaults to the bundled asset manifest; injectable so the sequencing logic
/// can be tested without the asset bundle.
typedef ClipResolver = Future<String?> Function(String word, String accent);

class NumberSpeaker {
  NumberSpeaker({SpeechClipPlayer? player, ClipResolver? resolver})
      : _player = player ?? AudioManager(),
        _resolve = resolver ?? NumberAudio.resolve;

  final SpeechClipPlayer _player;
  final ClipResolver _resolve;

  /// Pause inserted where the sentence has a comma (phone-number groups).
  static const Duration groupPause = Duration(milliseconds: 200);

  bool _cancelled = false;
  bool get isCancelled => _cancelled;

  /// Speaks one sentence, e.g. `NumberSpeller.read('1234')!.ukText`.
  Future<void> speak(
    String sentence, {
    String accent = 'uk',
    double rate = 1.0,
    SpeechMode mode = SpeechMode.sentence,
  }) async {
    _cancelled = false;
    await _speak(sentence, accent: accent, rate: rate, mode: mode);
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
    SpeechMode mode = SpeechMode.sentence,
  }) =>
      speakRuns(
        [for (final sentence in sentences) <String>[sentence]],
        accent: accent,
        rate: rate,
        gap: gap,
        onIndex: onIndex,
        mode: mode,
      );

  /// Speaks [rows] one after another, where each row is a short run of sentences
  /// read back to back (整数 mode's 多组 option).
  ///
  /// Inside a row the sentences follow [innerGap] apart; rows are [gap] apart,
  /// which is the pause a learner writes a group down in. The machine voice reads
  /// a whole row as **one** sentence — its commas carry the rhythm — because
  /// starting it once per number would pay the engine's start-up cost every time
  /// and would not be 连读 at all.
  Future<void> speakRuns(
    List<List<String>> rows, {
    String accent = 'uk',
    double rate = 1.0,
    Duration innerGap = const Duration(milliseconds: 80),
    Duration gap = const Duration(seconds: 1),
    void Function(int index)? onIndex,
    SpeechMode mode = SpeechMode.sentence,
  }) async {
    _cancelled = false;
    for (var i = 0; i < rows.length; i++) {
      if (_cancelled) return;
      onIndex?.call(i);
      final parts = mode == SpeechMode.sentence && rows[i].length > 1
          ? <String>[rows[i].join(', ')]
          : rows[i];
      for (var j = 0; j < parts.length; j++) {
        if (_cancelled) return;
        await _speak(parts[j], accent: accent, rate: rate, mode: mode);
        if (_cancelled || j == parts.length - 1) break;
        await Future.delayed(innerGap);
      }
      if (_cancelled || i == rows.length - 1) return;
      await Future.delayed(gap);
    }
  }

  /// Stops the current run: the remaining words are dropped and the clip that is
  /// playing right now is silenced.
  void cancel() {
    _cancelled = true;
    _player.stop();
  }

  Future<void> _speak(
    String sentence, {
    required String accent,
    required double rate,
    required SpeechMode mode,
  }) async {
    if (mode == SpeechMode.sentence) {
      // A whole sentence in one utterance by this machine's voice. The platform
      // answers false when it has no English voice at all, and then the recorded
      // words take over — so the module always says something, offline either way.
      final spoken = await _player.speakSentence(sentence, accent: accent, rate: rate);
      if (spoken || _cancelled) return;
    }
    for (final group in NumberAudio.pauseGroups(sentence)) {
      for (final word in NumberAudio.words(group)) {
        if (_cancelled) return;
        final clip = await _resolve(word, accent);
        if (clip == null) {
          // A word without a clip is skipped: staying on the previous clip, or
          // borrowing an unrelated one, would be worse than a small gap.
          continue;
        }
        await _player.playSpeechClip(clip, rate: rate);
      }
      if (_cancelled) return;
      await Future.delayed(groupPause);
    }
  }
}
