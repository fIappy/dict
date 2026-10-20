import '../audio/audio_manager.dart';
import '../audio/pcm_audio.dart';
import '../audio/piper_voice.dart';
import '../audio/speech_clip_player.dart';
import '../audio/voice_choice.dart';
import 'number_audio.dart';
import 'sentence_engine.dart';

/// How the module speaks a number.
///
/// [sentence] reads the whole number in one go — with the host's voice, with the
/// bundled Piper voice, or by splicing the module's own recordings — which is what
/// makes "one thousand two hundred and thirty-four" sound like one utterance
/// instead of a list of words. [clips] plays the recordings one word at a time
/// with an audible gap, which is what dictation practice wants; it is also what
/// [sentence] falls back to when the selected engine cannot speak.
enum SpeechMode {
  sentence('整句朗读', '整句交给所选引擎一次念完（连读自然；引擎不可用时自动改用录音）'),
  clips('逐词拼读', '只播单词录音：完全离线，英美两种口音都来自录音');

  final String labelZh;
  final String hint;
  const SpeechMode(this.labelZh, this.hint);
}

/// Plays a number sentence.
///
/// A number sentence is generated rather than recorded ("one thousand and
/// twenty-three"), so every engine builds it from the single-word clips in
/// `assets/audio/numbers/` or from a voice model. A comma in the sentence — which
/// [NumberSpeller] writes at every phone-number group boundary — becomes a short
/// pause, and the training module adds the interval between whole items on top of
/// that.
///
/// The UI can stop a run instantly: every async step carries the id of the run
/// it belongs to and drops out once that id is superseded, and [cancel] also
/// silences whatever is sounding.
class NumberSpeaker {
  NumberSpeaker({
    SpeechClipPlayer? player,
    ClipResolver? resolver,
    this.engine = SentenceEngine.system,
    SplicedSentence? splicer,
    PiperVoice? piper,
  })  : _player = player ?? AudioManager(),
        _resolve = resolver ?? NumberAudio.resolve,
        _piper = piper,
        _splicer = splicer ??
            SplicedSentence(
              player: player ?? AudioManager(),
              resolver: resolver ?? NumberAudio.resolve,
            );

  final SpeechClipPlayer _player;
  final ClipResolver _resolve;

  /// How a whole sentence is spoken in [SpeechMode.sentence]; the UI's engine
  /// switch writes it, and a sentence the engine cannot say falls back to the
  /// recorded words either way.
  SentenceEngine engine;

  /// The engine that splices the recorded words; owns no state between calls.
  final SplicedSentence _splicer;

  /// The Piper model, when the app owns one. Null means the engine reports
  /// itself unavailable and the module falls back — a build without a model is a
  /// normal state, not a failure.
  final PiperVoice? _piper;

  /// Pause inserted where the sentence has a comma (phone-number groups).
  static const Duration groupPause = Duration(milliseconds: 200);

  /// Monotonic run id, bumped by every start and every stop.
  ///
  /// An async step captures the id it began under and drops out as soon as the
  /// id changes. A plain boolean cannot express that: `cancel()` sets it, but
  /// the *next* run clears it again, so a run abandoned mid-`await` would wake
  /// up, read "not cancelled", and carry on talking over the run that replaced
  /// it — the overlapping speech (串音) this replaced. The window is wide here
  /// because a Piper render takes about a second per number and a spliced
  /// sentence decodes every clip before it plays anything.
  int _runId = 0;

  bool _stale(int runId) => runId != _runId;

  /// Speaks one sentence, e.g. `NumberSpeller.read('1234')!.ukText`.
  Future<void> speak(
    String sentence, {
    String accent = 'uk',
    double rate = 1.0,
    SpeechMode mode = SpeechMode.sentence,
  }) async {
    final run = ++_runId;
    // The slider value travels unchanged. Only the Windows voices need the
    // teaching anchor and they apply it themselves (`speech_rate.dart`); Piper,
    // Android's engine, the browser and the player take a plain multiplier of
    // their own natural pace.
    await _speak(sentence, accent: accent, rate: rate, mode: mode, run: run);
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
  /// which is the pause a learner writes a group down in.
  ///
  /// At `innerGap == 0` a whole row goes to the engine as **one** sentence — its
  /// commas carry the rhythm, which is what 连读 means and what "组内间隔 0 = 连读"
  /// promises. With a gap set, the row is spoken number by number with exactly
  /// that pause between them; joining the row and hoping the engine's own comma
  /// pause matches the slider is what made the slider look dead.
  Future<void> speakRuns(
    List<List<String>> rows, {
    String accent = 'uk',
    double rate = 1.0,
    Duration innerGap = const Duration(milliseconds: 80),
    Duration gap = const Duration(seconds: 1),
    void Function(int index)? onIndex,
    SpeechMode mode = SpeechMode.sentence,
  }) async {
    final run = ++_runId;
    final joinRow = mode == SpeechMode.sentence && innerGap == Duration.zero;
    // Piper synthesizes on the device's CPU — about a second per number on a
    // phone — and that cost would land *between* two numbers, so the pause the
    // slider asks for would grow by it (0.2 s became ~1.4 s). The row is therefore
    // rendered first and played as one clip whose internal pauses are exactly the
    // ones asked for. Only worth it for a gap; at 连读 the row is a single
    // sentence anyway.
    final renderRowFirst = mode == SpeechMode.sentence &&
        !joinRow &&
        innerGap > Duration.zero &&
        _piper != null &&
        (engine == SentenceEngine.piper || _spokenBy == SentenceEngine.piper);

    for (var i = 0; i < rows.length; i++) {
      if (_stale(run)) return;
      onIndex?.call(i);
      final parts = joinRow && rows[i].length > 1 ? <String>[rows[i].join(', ')] : rows[i];

      if (renderRowFirst && parts.length > 1) {
        final rendered = await _playRenderedRow(
          parts,
          accent: accent,
          rate: rate,
          innerGap: innerGap,
          run: run,
        );
        // A render is the longest wait in this loop; check before acting on it.
        if (_stale(run)) return;
        if (rendered) {
          if (i == rows.length - 1) return;
          await Future.delayed(gap);
          continue;
        }
        // Rendering failed: fall through and speak them one by one.
      }

      for (var j = 0; j < parts.length; j++) {
        if (_stale(run)) return;
        await _speak(parts[j], accent: accent, rate: rate, mode: mode, run: run);
        if (_stale(run) || j == parts.length - 1) break;
        await Future.delayed(innerGap);
      }
      if (_stale(run) || i == rows.length - 1) return;
      await Future.delayed(gap);
    }
  }

  /// Reads [sentence] with the Piper model and plays the samples once.
  /// False when there is no model (or it failed): the caller falls back.
  Future<bool> _speakWithPiper(
    String sentence, {
    required String accent,
    required double rate,
    required int run,
  }) async {
    final piper = _piper;
    if (piper == null) return false;
    // The model paces itself (`speed`), so the player must not scale the audio a
    // second time.
    final clip = await piper.synthesize(
      sentenceForSpeech(sentence),
      accent: accent,
      rate: rate,
    );
    if (_stale(run)) return false;
    if (clip == null || clip.isEmpty) return false;
    await _player.playAudioBytes(
      encodeWav(clip.samples, sampleRate: clip.sampleRate),
    );
    return true;
  }

  /// Renders every part of a row with the model and plays the row as one clip,
  /// with [innerGap] of real silence between the numbers. False when the model
  /// could not render one of them, so the caller can speak them one by one.
  Future<bool> _playRenderedRow(
    List<String> parts, {
    required String accent,
    required double rate,
    required Duration innerGap,
    required int run,
  }) async {
    final piper = _piper;
    if (piper == null) return false;

    final clips = <PcmClip>[];
    for (final part in parts) {
      if (_stale(run)) return false;
      final clip = await piper.synthesize(sentenceForSpeech(part), accent: accent, rate: rate);
      if (_stale(run)) return false;
      if (clip == null || clip.isEmpty) return false;
      clips.add(clip);
    }

    final joined = joinClips(clips, gaps: [for (var i = 0; i < clips.length - 1; i++) innerGap]);
    await _player.playAudioBytes(
      encodeWav(joined.samples, sampleRate: joined.sampleRate),
    );
    _spokenBy = SentenceEngine.piper;
    return true;
  }

  /// The order a sentence is read with when the chosen engine cannot read it:
  /// the neural voice, then the host's voice, then the module's own recordings
  /// spliced into one clip. Splicing is always available (the clips ship with the
  /// app), so a two-digit number is never read as two separate words just because
  /// the device has no English voice — that is what used to happen on Android
  /// phones whose TTS engine has no English installed.
  static const List<SentenceEngine> sentenceFallback = [
    SentenceEngine.piper,
    SentenceEngine.system,
    SentenceEngine.spliced,
  ];

  /// Which engine read the last sentence, for the UI and for the on-device
  /// self-test; null when no engine managed it and the words were played singly.
  SentenceEngine? get spokenBy => _spokenBy;
  SentenceEngine? _spokenBy;

  /// Reads one sentence by the first engine that can: the selected one, then
  /// [sentenceFallback]. Returns false when none of them could.
  Future<bool> _speakSentence(
    String sentence, {
    required String accent,
    required double rate,
    required int run,
  }) async {
    final order = <SentenceEngine>[
      engine,
      ...sentenceFallback.where((candidate) => candidate != engine),
    ];

    for (final candidate in order) {
      if (_stale(run)) return false;
      final spoken = switch (candidate) {
        SentenceEngine.system =>
          await _player.speakSentence(sentence, accent: accent, rate: rate),
        SentenceEngine.piper =>
          await _speakWithPiper(sentence, accent: accent, rate: rate, run: run),
        SentenceEngine.spliced => await _splicer.speak(
            sentence,
            accent: accent,
            rate: rate,
            isCancelled: () => _stale(run),
          ),
      };
      if (_stale(run)) return false;
      if (spoken) {
        _spokenBy = candidate;
        return true;
      }
    }
    _spokenBy = null;
    return false;
  }

  /// Stops the current run: the run id moves on, so every step still in flight —
  /// a Piper render, a splice decode, a pending pause — drops out instead of
  /// resuming, and whatever is sounding right now is silenced.
  void cancel() {
    _runId++;
    _player.stop();
  }

  Future<void> _speak(
    String sentence, {
    required String accent,
    required double rate,
    required SpeechMode mode,
    required int run,
  }) async {
    if (mode == SpeechMode.sentence) {
      // One sentence in one go. The engine the user picked goes first; if it
      // cannot read this sentence (no English voice on the device, no model
      // installed), another engine takes over rather than splitting the number
      // into single words — that is what `_speakSentence` walks.
      final spoken = await _speakSentence(sentence, accent: accent, rate: rate, run: run);
      if (spoken || _stale(run)) return;
    }
    for (final group in NumberAudio.pauseGroups(sentence)) {
      for (final word in NumberAudio.words(group)) {
        if (_stale(run)) return;
        final clip = await _resolve(word, accent);
        // Resolving hits the asset bundle; the run may have been replaced while
        // it was in flight.
        if (_stale(run)) return;
        if (clip == null) {
          // A word without a clip is skipped: staying on the previous clip, or
          // borrowing an unrelated one, would be worse than a small gap.
          continue;
        }
        await _player.playSpeechClip(clip, rate: rate);
      }
      if (_stale(run)) return;
      await Future.delayed(groupPause);
    }
  }
}
