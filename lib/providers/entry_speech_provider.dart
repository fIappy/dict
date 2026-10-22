import 'package:flutter/foundation.dart';

import '../core/audio/audio_manager.dart';
import '../core/audio/pcm_audio.dart';
import '../core/audio/piper_voice.dart';
import '../core/audio/speech_clip_player.dart';
import '../core/mdx/entry_speech.dart';

/// The Piper accent for a settings language tag: `en-GB` reads with the British
/// voice, everything else with the American one.
String accentForLanguage(String language) =>
    language.toLowerCase().endsWith('-gb') ? 'uk' : 'us';

/// Plays the phrases and example sentences of the entry on screen.
///
/// The engine chain is the numbers module's: the bundled Piper voice reads the
/// line in one pass (same model on every platform), and a machine without a
/// model falls back to the platform voice. Both take the slider value as a
/// plain multiplier of their natural pace.
///
/// One [playAll] walks the list in page order, waiting the configured gap
/// between lines; [stop] cuts whatever is sounding and drops the pending pause,
/// so starting again cannot overlap the previous run.
class EntrySpeechProvider extends ChangeNotifier {
  EntrySpeechProvider({SpeechClipPlayer? player, PiperVoice? piper})
    : _player = player ?? AudioManager(),
      _piper = piper ?? PiperVoice();

  final SpeechClipPlayer _player;
  final PiperVoice? _piper;

  List<EntryUtterance> _items = const [];
  int? _currentIndex;
  bool _isPlaying = false;
  bool _isPaused = false;
  int _run = 0;

  /// 循环播放: repeat the list until stopped.
  bool _loop = false;

  /// Whether the run in flight repeats. Separate from [_loop] so a one-off
  /// "read this selection" never loops even when the switch is on.
  bool _loopRun = false;

  double _rate = 1.0;
  Duration _gap = Duration.zero;
  String _accent = 'us';

  /// The list [playAll] is walking (or walked last), for the UI's progress.
  List<EntryUtterance> get items => _items;

  /// The line sounding right now, or null when nothing is playing.
  int? get currentIndex => _currentIndex;

  bool get isPlaying => _isPlaying;

  /// Sound is cut and the run waits; resuming replays the interrupted line.
  bool get isPaused => _isPaused;

  bool get loop => _loop;

  /// Speaks every line of [items], waiting [gap] between them.
  ///
  /// [loop] overrides the 循环 switch for this run only. Pausing cuts the sound
  /// immediately and remembers the line; resuming says that line again from
  /// its start, because a TTS engine cannot be paused mid-utterance.
  Future<void> playAll(
    List<EntryUtterance> items, {
    required double rate,
    required Duration gap,
    required String accent,
    bool? loop,
  }) async {
    if (items.isEmpty) return;
    final run = ++_run;
    _items = items;
    _rate = rate;
    _gap = gap;
    _accent = accent;
    _loopRun = loop ?? _loop;
    _isPlaying = true;
    _isPaused = false;
    _currentIndex = null;
    notifyListeners();
    try {
      var index = 0;
      while (run == _run) {
        for (; index < items.length; index++) {
          if (run != _run) return;
          if (_isPaused) await _waitWhilePaused(run);
          if (run != _run) return;

          _currentIndex = index;
          notifyListeners();
          await _speak(items[index].text, accent: _accent, rate: _rate, run: run);
          if (run != _run) return;

          // Paused mid-line: hold, then say this line again from its start.
          if (_isPaused) {
            index--;
            await _waitWhilePaused(run);
            if (run != _run) return;
          }
          if (index < items.length - 1) await Future<void>.delayed(_gap);
        }
        if (!_loopRun) break;
        index = 0;
        await Future<void>.delayed(_gap);
        if (run != _run) return;
      }
    } finally {
      // Only the run that still owns the id may clear the state: a stopped run
      // wakes up here after the next one has already started.
      if (run == _run) {
        _isPlaying = false;
        _isPaused = false;
        _currentIndex = null;
        notifyListeners();
      }
    }
  }

  /// 暂停: silence now, keep the place.
  void pause() {
    if (!_isPlaying || _isPaused) return;
    _isPaused = true;
    _player.stop();
    notifyListeners();
  }

  /// 继续: pick the interrupted line up again.
  void resume() {
    if (!_isPaused) return;
    _isPaused = false;
    notifyListeners();
  }

  void togglePause() => _isPaused ? resume() : pause();

  /// 循环: applies to the run in flight as well as the next one.
  void setLoop(bool value) {
    if (_loop == value) return;
    _loop = value;
    _loopRun = value;
    notifyListeners();
  }

  Future<void> _waitWhilePaused(int run) async {
    while (_isPaused && run == _run) {
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }
  }

  /// Speaks one line on its own (the speaker icon next to it).
  Future<void> playOne(
    EntryUtterance item, {
    required double rate,
    required String accent,
  }) async {
    stop();
    final run = ++_run;
    _items = [item];
    _isPlaying = true;
    _isPaused = false;
    _currentIndex = 0;
    notifyListeners();
    await _speak(item.text, accent: accent, rate: rate, run: run);
    if (run != _run) return;
    _isPlaying = false;
    _currentIndex = null;
    notifyListeners();
  }

  /// Speaks text the reader picked out of the entry — a definition line, a
  /// usage note, an explanation the archive never flagged as an example.
  ///
  /// The entry's own example markup only covers the lines a dictionary chose to
  /// tag; everything else is plain rendered text, and selecting it is how it
  /// gets a voice.
  Future<void> speakText(
    String text, {
    required double rate,
    required String accent,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    // A one-line run, so pause/继续 work here too; it never repeats.
    await playAll(
      [EntryUtterance(text: trimmed, isPhrase: false)],
      rate: rate,
      gap: Duration.zero,
      accent: accent,
      loop: false,
    );
  }

  /// Stops the current run: no further line, and no leftover pause.
  void stop() {
    _run++;
    _isPlaying = false;
    _isPaused = false;
    _currentIndex = null;
    _player.stop();
    notifyListeners();
  }

  @override
  void dispose() {
    _run++;
    _player.stop();
    _piper?.dispose();
    super.dispose();
  }

  /// One line: Piper when this machine has the model, the platform voice
  /// otherwise.
  Future<bool> _speak(
    String text, {
    required String accent,
    required double rate,
    required int run,
  }) async {
    final piper = _piper;
    if (piper != null && await piper.isReady(accent)) {
      final clip = await piper.synthesize(text, accent: accent, rate: rate);
      if (run != _run) return false;
      if (clip != null && clip.samples.isNotEmpty) {
        final played = await _player.playAudioBytes(
          encodeWav(clip.samples, sampleRate: clip.sampleRate),
          rate: 1.0,
        );
        if (played) return run == _run;
        // The buffer never sounded — a player without byte support, or a mixer
        // that refused it. Speak the line with the platform voice rather than
        // leaving the reader in silence.
        debugPrint('Piper clip did not sound; using the platform voice');
      }
    }
    return _player.speakSentence(text, accent: accent, rate: rate);
  }
}
