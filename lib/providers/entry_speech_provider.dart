import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/audio/audio_manager.dart';
import '../core/audio/online_audio_cache.dart';
import '../core/audio/online_tts.dart';
import '../core/audio/pcm_audio.dart';
import '../core/audio/kokoro_voice.dart';
import '../core/audio/speech_engine.dart';
import '../core/audio/speech_clip_player.dart';
import '../core/mdx/entry_speech.dart';

/// One line ready to sound.
///
/// Three shapes because the engines differ: a local render arrives as samples,
/// an online voice as MP3, and the platform voice needs no audio at all — it is
/// handed the text when its turn comes.
sealed class _Line {
  const _Line();
}

class _PcmLine extends _Line {
  const _PcmLine(this.clip);
  final PcmClip clip;
}

class _Mp3Line extends _Line {
  const _Mp3Line(this.bytes);
  final Uint8List bytes;
}

class _SpokenLine extends _Line {
  const _SpokenLine();
}

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
  EntrySpeechProvider({
    SpeechClipPlayer? player,
    KokoroVoice? kokoro,
    OnlineSynthesizer? online,
  })  : _player = player ?? AudioManager(),
        _kokoro = kokoro ?? KokoroVoice(),
        // Every online line goes through the disk queue: the same sentences are
        // read again and again in a drill.
        _online = online ?? OnlineAudioCache.instance.synthesize;

  final SpeechClipPlayer _player;
  final KokoroVoice? _kokoro;

  /// How a sentence becomes MP3 for the online engines; injectable so a test can
  /// drive the fallback without a network.
  final OnlineSynthesizer _online;

  List<EntryUtterance> _items = const [];
  int? _currentIndex;
  bool _isPlaying = false;
  bool _isPaused = false;
  int _run = 0;

  /// Whether a line's render/playback is in flight right now.
  ///
  /// Pausing during the gap between lines and pausing during a line need
  /// different answers on resume: the first keeps walking, the second says
  /// that line again. The paused flag alone cannot tell them apart once the
  /// listener presses 继续 before the cut playback returns.
  bool _inLine = false;

  /// A pause landed inside the current line (not in the gap after it).
  bool _pausedInLine = false;

  /// Ends the line's playback wait at once when the reader pauses or stops.
  ///
  /// The player is told to stop separately; this is what stops the *await* from
  /// sitting out the clip's own completion or the stall guard.
  Completer<void>? _lineAbort;

  /// How many lines the engine may render ahead of the one sounding.
  ///
  /// Ten short lines is a few hundred kilobytes of PCM and covers a render that
  /// takes longer than the clip itself; the first line still waits for the model
  /// ([warmUp] is what shortens that).
  static const int prefetchWindow = 10;

  /// Clips kept after they sound: enough for a looped drill of a few dozen
  /// lines, small enough that a whole passage never sits in memory.
  static const int clipCacheSize = 32;

  /// 循环播放: repeat the list until stopped.
  bool _loop = false;

  /// Whether the run in flight repeats. Separate from [_loop] so a one-off
  /// "read this selection" never loops even when the switch is on.
  bool _loopRun = false;

  /// Line the run should go back to, set by 重复当前 / 重复前一句.
  int? _repeatFrom;

  /// Bumped to abandon the line in flight (打断) without ending the run.
  int _lineEpoch = 0;

  SpeechEngine _engine = SpeechEngine.kokoro;
  double _rate = 1.0;
  Duration _gap = Duration.zero;
  String _accent = 'us';

  /// Whether the model is loaded for this run. Probed once per run: Kokoro is
  /// the only engine, so a line it cannot render is skipped rather than spoken
  /// in some other voice.
  bool _kokoroReady = false;

  /// The list [playAll] is walking (or walked last), for the UI's progress.
  List<EntryUtterance> get items => _items;

  /// The line sounding right now, or null when nothing is playing.
  int? get currentIndex => _currentIndex;

  /// The utterance sounding right now, or null when nothing is playing.
  EntryUtterance? get currentUtterance =>
      (_isPlaying && _currentIndex != null && _currentIndex! < _items.length)
          ? _items[_currentIndex!]
          : null;

  /// Returns the sentence index if [itemId] is currently being read, or null.
  int? sentenceIndexFor(String itemId) {
    if (!_isPlaying || _currentIndex == null || _currentIndex! >= _items.length) {
      return null;
    }
    final current = _items[_currentIndex!];
    if (current.itemId == itemId) return current.sentenceIndex;
    return null;
  }

  bool get isPlaying => _isPlaying;

  /// Sound is cut and the run waits; resuming replays the interrupted line.
  bool get isPaused => _isPaused;

  bool get loop => _loop;

  /// Whether the run in flight reads exactly [lines] right now.
  ///
  /// The player is shared by every screen, so a view tints its own text only
  /// when the words on screen are the words being spoken.
  bool isReading(List<String> lines) {
    if (!_isPlaying || _items.length != lines.length) return false;
    for (var i = 0; i < lines.length; i++) {
      if (_items[i].text != lines[i]) return false;
    }
    return true;
  }

  /// Whether 重复当前 / 重复前一句 can do anything right now.
  bool get canRepeat => _isPlaying && _currentIndex != null;

  /// 重复当前: let the line that is sounding finish, then say it again and carry
  /// on — the usual way of replaying a sentence that slipped past.
  ///
  /// A click during the gap lands on the same line: the request is picked up
  /// before the next line starts, so nothing extra is spoken.
  void repeatCurrent() {
    if (_isPlaying && _currentIndex != null) {
      _repeatFrom = _currentIndex;
    }
  }

  /// 重复前一句: cut the line that is sounding and start again from the line
  /// before it (the first line stays the first line).
  void repeatPrevious() {
    if (!_isPlaying || _currentIndex == null) return;
    _repeatFrom = _currentIndex! > 0 ? _currentIndex! - 1 : 0;
    _lineEpoch++; // the line in flight must not start sounding any more
    _player.stop();
  }

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
    SpeechEngine engine = SpeechEngine.kokoro,
    double volume = 1.0,
  }) async {
    if (items.isEmpty) return;
    _engine = engine;
    await _player.setVolume(volume);
    final run = ++_run;
    _items = items;
    _rate = rate;
    _gap = gap;
    _accent = accent;
    _loopRun = loop ?? _loop;
    _repeatFrom = null;
    _kokoroReady = engine == SpeechEngine.system ? false : await _kokoroUsable();
    if (run != _run) return;
    _isPlaying = true;
    _isPaused = false;
    _currentIndex = null;
    _inLine = false;
    _pausedInLine = false;
    notifyListeners();
    try {
      // Render ahead, not one line but a window of them: a word or a short
      // sentence takes about a second to synthesize and the reader asked for a
      // 350 ms gap, so one line of head start is not enough — the pause would
      // come out as gap + render. With a window the only render the listener
      // ever waits for is the first one.
      // Insertion-ordered, capped: a loop over a short list reuses its clips,
      // a 700-line passage does not pin every clip in memory.
      final clips = <int, Future<_Line?>>{};
      Future<_Line?> clipAt(int at) {
        final ready = clips.remove(at);
        if (ready != null) {
          clips[at] = ready; // touch: most recently used goes last
          return ready;
        }
        final created = _render(items[at].text, rate: _rate);
        clips[at] = created;
        while (clips.length > clipCacheSize) {
          clips.remove(clips.keys.first);
        }
        return created;
      }
      void prefetchFrom(int from) {
        for (var ahead = from; ahead < from + prefetchWindow && ahead < items.length; ahead++) {
          unawaited(clipAt(ahead));
        }
      }

      prefetchFrom(0);
      var index = 0;
      while (run == _run) {
        for (; index < items.length; index++) {
          if (run != _run) return;
          if (_isPaused) {
            await _waitWhilePaused(run);
            if (run != _run) return;
          }

          // A repeat asked for while the gap was running lands here, before the
          // next line starts, so only the requested line is said.
          final requested = _repeatFrom;
          if (requested != null) {
            _repeatFrom = null;
            index = requested;
          }

          _currentIndex = index;
          notifyListeners();
          // Keep the window full as lines move out of it.
          prefetchFrom(index + 1);
          _inLine = true;
          _pausedInLine = false;
          _lineAbort = Completer<void>();
          final clip = await clipAt(index);
          await _playClip(clip, run: run);
          _inLine = false;
          _lineAbort = null;
          if (run != _run) return;

          // A repeat asked for during the line lands here, after it finished.
          final again = _repeatFrom;
          if (again != null) {
            _repeatFrom = null;
            index = again - 1; // the loop's ++ lands on the requested line
            continue;
          }

          // Paused mid-line: hold, then say this line again from its start.
          // The flag survives an early 继续: pressing play while the cut
          // playback is still returning used to look like "the line ended"
          // and the reader heard nothing until the next line.
          if (_pausedInLine) {
            _pausedInLine = false;
            index--;
            await _waitWhilePaused(run);
            if (run != _run) return;
            continue; // the for's ++ lands on the same line, with no gap
          }
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
      }
    } finally {
      // Only the run that still owns the id may clear the state: a stopped run
      // wakes up here after the next one has already started.
      if (run == _run) {
        _isPlaying = false;
        _isPaused = false;
        _inLine = false;
        _pausedInLine = false;
        _currentIndex = null;
        notifyListeners();
      }
    }
  }

  /// 暂停: silence now, keep the place.
  void pause() {
    if (!_isPlaying || _isPaused) return;
    _isPaused = true;
    if (_inLine) _pausedInLine = true;
    _lineAbort?.complete();
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
    SpeechEngine engine = SpeechEngine.kokoro,
    double volume = 1.0,
  }) async {
    stop();
    _engine = engine;
    // The engine reads these fields, not the parameters: without this the
    // platform voice and Google spoke at the previous run's accent and speed.
    _accent = accent;
    _rate = rate;
    await _player.setVolume(volume);
    final run = ++_run;
    _items = [item];
    _kokoroReady = engine == SpeechEngine.system ? false : await _kokoroUsable();
    if (run != _run) return;
    _isPlaying = true;
    _isPaused = false;
    _currentIndex = 0;
    notifyListeners();
    try {
      _inLine = true;
      _pausedInLine = false;
      _lineAbort = Completer<void>();
      final line = await _render(item.text, rate: rate);
      await _playClip(line, run: run);
      _inLine = false;
      _lineAbort = null;
      if (_pausedInLine) {
        _pausedInLine = false;
        await _waitWhilePaused(run);
        if (run == _run) await _playClip(line, run: run);
      }
    } finally {
      _inLine = false;
      _pausedInLine = false;
      _lineAbort = null;
      if (run == _run) {
        _isPlaying = false;
        _currentIndex = null;
        notifyListeners();
      }
    }
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
    SpeechEngine engine = SpeechEngine.kokoro,
    double volume = 1.0,
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
      engine: engine,
      volume: volume,
    );
  }

  /// Stops the current run: no further line, and no leftover pause.
  void stop() {
    _run++;
    _isPlaying = false;
    _isPaused = false;
    _currentIndex = null;
    _repeatFrom = null;
    _lineEpoch++;
    _inLine = false;
    _pausedInLine = false;
    _lineAbort?.complete();
    _lineAbort = null;
    _player.stop();
    notifyListeners();
  }

  @override
  void dispose() {
    _run++;
    _player.stop();
    _kokoro?.dispose();
    super.dispose();
  }

  /// Loads the model and runs one throwaway line, so the first 播放 does not pay
  /// for either.
  ///
  /// Loading takes about a second, and the first inference costs about as much
  /// again while ONNX builds its kernels — together that was the "click 朗读 and
  /// wait" pause. The engine lives in its own isolate, so this warms up without
  /// touching the UI thread.
  void warmUp() {
    unawaited(_warmUp());
  }

  Future<void> _warmUp() async {
    final kokoro = _kokoro;
    if (kokoro == null) return;
    if (!await kokoro.isReady()) return;
    // A single letter: the cheapest line that makes ONNX do its first pass.
    await kokoro.synthesize('a', accent: _accent, rate: 1.0);
  }

  /// Whether this machine has the Kokoro model.
  Future<bool> _kokoroUsable() async {
    final kokoro = _kokoro;
    if (kokoro == null) return false;
    try {
      return await kokoro.isReady();
    } catch (e) {
      debugPrint('Kokoro probe failed: $e');
      return false;
    }
  }

  /// The next line's audio, rendered while the current one is sounding.
  ///
  /// Synthesis takes about half a second per sentence. Rendering it *after* the
  /// configured gap is what made a 1 s pause feel like 3 s: the reader waited the
  /// gap and then waited again for the model. Doing it during playback costs
  /// nothing the reader notices.
  Future<_Line?> _render(String text, {required double rate}) async {
    if (_engine.isOnline) {
      final bytes = await _online(_engine, text: text, accent: _accent, rate: rate);
      if (bytes != null && bytes.isNotEmpty) return _Mp3Line(bytes);
      // A blocked route, an outage, a quota: the line still has to sound, so
      // the machine's own voice takes over instead of leaving dead air.
      debugPrint('${_engine.label} answered no audio; using this machine\'s voice');
      if (_kokoroReady) {
        final clip = await _kokoro!.synthesize(text, accent: _accent, rate: rate);
        if (clip != null && clip.samples.isNotEmpty) return _PcmLine(clip);
      }
      return const _SpokenLine();
    }
    if (_engine == SpeechEngine.system) return const _SpokenLine();
    // A local engine that cannot render skips the line, as it always has: the
    // reader picked one voice, and switching mid-passage is worse than silence.
    if (!_kokoroReady) return null;
    final clip = await _kokoro!.synthesize(text, accent: _accent, rate: rate);
    if (clip == null || clip.samples.isEmpty) {
      debugPrint('Kokoro could not render a line; skipping it');
      return null;
    }
    return _PcmLine(clip);
  }

  /// Sounds one rendered line.
  Future<bool> _playClip(
    _Line? line, {
    required int run,
  }) async {
    if (run != _run || _isPaused) return false;
    if (line == null) return false;
    final epoch = _lineEpoch;
    final abort = _lineAbort;
    // Stopping must end the wait, not just the sound: a paused line used to sit
    // on its playback future until the stall guard ran out, and 继续 pressed
    // meanwhile found the state already "finished" — silence until next line.
    Future<bool> wait(Future<bool> call, {bool acceptCancel = false}) {
      if (abort == null) return call;
      return Future.any<bool>([
        call,
        abort.future.then((_) => false),
      ]);
    }

    final bool played;
    switch (line) {
      case _SpokenLine():
        // The platform voice speaks the line itself; there is no clip to play.
        final index = _currentIndex;
        if (index == null || index < 0 || index >= _items.length) return false;
        return wait(_player.speakSentence(
          _items[index].text,
          accent: _accent,
          rate: _rate,
        ));
      case _Mp3Line(:final bytes):
        // Edge and 百度 bake the speed into the clip; scaling it again would
        // apply the slider twice. Google's endpoint ignores speed, so there the
        // player does the work (and shifts pitch with it).
        played = await wait(_player.playOnlineClip(
          bytes,
          rate: _engine.bakesRate ? 1.0 : _rate,
          cancel: abort?.future,
        ));
      case _PcmLine(:final clip):
        played = await wait(_player.playAudioBytes(
          encodeWav(clip.samples, sampleRate: clip.sampleRate),
          rate: 1.0,
          cancel: abort?.future,
        ));
    }
    if (run != _run || _isPaused || epoch != _lineEpoch) return false;
    return played;
  }
}
