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
  int _run = 0;

  /// The list [playAll] is walking (or walked last), for the UI's progress.
  List<EntryUtterance> get items => _items;

  /// The line sounding right now, or null when nothing is playing.
  int? get currentIndex => _currentIndex;

  bool get isPlaying => _isPlaying;

  /// Speaks every line of [items], waiting [gap] between them.
  Future<void> playAll(
    List<EntryUtterance> items, {
    required double rate,
    required Duration gap,
    required String accent,
  }) async {
    if (items.isEmpty) return;
    final run = ++_run;
    _items = items;
    _isPlaying = true;
    _currentIndex = null;
    notifyListeners();
    try {
      for (var index = 0; index < items.length; index++) {
        if (run != _run) return;
        _currentIndex = index;
        notifyListeners();
        await _speak(items[index].text, accent: accent, rate: rate, run: run);
        if (run != _run) return;
        if (index < items.length - 1) await Future.delayed(gap);
      }
    } finally {
      // Only the run that still owns the id may clear the state: a stopped run
      // wakes up here after the next one has already started.
      if (run == _run) {
        _isPlaying = false;
        _currentIndex = null;
        notifyListeners();
      }
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
    _currentIndex = 0;
    notifyListeners();
    await _speak(item.text, accent: accent, rate: rate, run: run);
    if (run != _run) return;
    _isPlaying = false;
    _currentIndex = null;
    notifyListeners();
  }

  /// Stops the current run: no further line, and no leftover pause.
  void stop() {
    _run++;
    _isPlaying = false;
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
        await _player.playAudioBytes(
          encodeWav(clip.samples, sampleRate: clip.sampleRate),
          rate: 1.0,
        );
        return run == _run;
      }
    }
    return _player.speakSentence(text, accent: accent, rate: rate);
  }
}
