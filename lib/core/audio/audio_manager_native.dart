import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'audio_background.dart';
import 'ipa_asset.dart';
import 'online_word_audio.dart';
import 'playback_wait.dart';
import 'prepared_pronunciation.dart';
import 'sentence_voice.dart';
import 'speech_clip_player.dart';
import 'word_audio_cache_native.dart';

class AudioManager implements SpeechClipPlayer {
  static final AudioManager _instance = AudioManager._();
  factory AudioManager() => _instance;
  AudioManager._() {
    _player.onPositionChanged.listen((position) {
      _lastPosition = position;
    });
  }

  final AudioPlayer _player = AudioPlayer();
  final WordAudioCache _wordCache = WordAudioCache();
  final StreamController<void> _cancellations = StreamController<void>.broadcast();
  int _playId = 0;

  WordAudioCache get wordCache => _wordCache;

  bool _isPlaying = false;
  String? _currentlyPlayingTag;

  bool get isPlaying => _isPlaying;
  String? get currentlyPlayingTag => _currentlyPlayingTag;

  /// Plays an online pronunciation for [word], using the independent
  /// 10,000-word [WordAudioCache] before hitting online voice endpoints, and
  /// falling back to the OS voice when offline and uncached on Windows.
  Future<void> playWord({
    required String word,
    String? soundKey,
    String accent = 'us', // 'us' (美音) or 'uk' (英音)
    void Function(bool isPlaying)? onStateChanged,
  }) async {
    final playTag = '${word}_$accent';
    _currentlyPlayingTag = playTag;
    _isPlaying = true;
    onStateChanged?.call(true);
    try {
      final clip = await prepareWord(
        word: word,
        soundKey: soundKey,
        accent: accent,
      );
      await _startClip(clip);
    } catch (e) {
      debugPrint('Error playing pronunciation for $word: $e');
    } finally {
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (_currentlyPlayingTag == playTag) {
          _isPlaying = false;
          _currentlyPlayingTag = null;
          onStateChanged?.call(false);
        }
      });
    }
  }

  /// Resolves [word]'s audio without playing it.
  ///
  /// The drill fills its queue with these ahead of time, so the configured gap
  /// between words is the gap the reader hears instead of a network download.
  Future<PreparedPronunciation> prepareWord({
    required String word,
    String? soundKey,
    String accent = 'us',
  }) async {
    final normAccent = normalizeWordCacheAccent(accent);
    final cachedPath = await _wordCache.getPath(word, normAccent);
    if (cachedPath != null) {
      return PreparedPronunciation(word: word, path: cachedPath);
    }

    final bytes = await fetchOnlineWordAudio(word, accent: normAccent);
    if (bytes != null && bytes.isNotEmpty) {
      final savedPath = await _wordCache.put(word, normAccent, bytes);
      if (savedPath != null) {
        return PreparedPronunciation(word: word, path: savedPath);
      }
      return PreparedPronunciation(word: word, bytes: bytes);
    }

    // Offline and uncached: OS voice reads it when its turn comes on Windows.
    return PreparedPronunciation(word: word);
  }

  /// Starts a prepared clip; returns once the sound has begun.
  Future<void> _startClip(PreparedPronunciation clip) async {
    AudioBackground.begin();
    try {
      final path = clip.path;
      if (path != null) {
        await _player.stop();
        await _player.play(DeviceFileSource(path));
        return;
      }
      final bytes = clip.bytes;
      if (bytes != null) {
        await _player.stop();
        await _player.play(BytesSource(bytes));
        return;
      }
      await _speakWithOs(clip.word);
    } catch (e) {
      debugPrint('Error playing pronunciation for ${clip.word}: $e');
    } finally {
      AudioBackground.end();
    }
  }

  /// Plays a clip from [prepareWord] and waits for it to finish.
  Future<void> playPrepared(
    PreparedPronunciation clip, {
    Duration maxWait = const Duration(seconds: 6),
  }) async {
    final hasAudio = clip.hasAudio;
    await _startClip(clip);
    if (!hasAudio) return; // OS speech finished when it returned
    try {
      await _player.onPlayerComplete.first.timeout(maxWait);
    } on TimeoutException {
      await _player.stop();
    } catch (e) {
      debugPrint('Pronunciation of ${clip.word} did not report its end: $e');
    }
  }

  /// Plays [word] and waits for the clip to finish.
  ///
  /// The loop in 背词 needs one word to end before the next starts; [playWord]
  /// only starts the sound.
  Future<void> playWordAndWait({
    required String word,
    String? soundKey,
    String accent = 'us',
    Duration maxWait = const Duration(seconds: 6),
  }) async {
    final clip = await prepareWord(
      word: word,
      soundKey: soundKey,
      accent: accent,
    );
    await playPrepared(clip, maxWait: maxWait);
  }

  /// Cuts the pronunciation in flight (the drill's loop uses this when stopped).
  Future<void> stopPronunciation() async {
    _playId++;
    if (!_cancellations.isClosed) _cancellations.add(null);
    _currentlyPlayingTag = null;
    _isPlaying = false;
    try {
      await _player.stop();
    } catch (e) {
      debugPrint('Could not stop the pronunciation: $e');
    }
  }

  /// Last-resort speech synthesis; only Windows exposes a usable CLI.
  ///
  /// The text goes over stdin, never into the command line: PowerShell treats
  /// the Unicode quotes a dictionary headword may carry (’ ‘ “ ”) as quotes, so
  /// interpolating it let an entry run arbitrary commands.
  Future<void> _speakWithOs(String word) async {
    if (!Platform.isWindows) return;
    try {
      final process = await Process.start('powershell', [
        '-NoProfile',
        '-Command',
        r'$text = [Console]::In.ReadToEnd(); '
            r'(New-Object -ComObject SAPI.SpVoice).Speak($text)',
      ]);
      process.stdin.write(word);
      await process.stdin.close();
      await process.exitCode;
    } catch (e) {
      debugPrint('OS speech failed for $word: $e');
    }
  }

  Future<void> playIpaPhoneme(
    String audioAssetKey, {
    String accent = 'uk',
    void Function(bool isPlaying)? onStateChanged,
  }) async {
    final playTag = 'ipa_${audioAssetKey}_$accent';
    _currentlyPlayingTag = playTag;
    _isPlaying = true;
    onStateChanged?.call(true);
    AudioBackground.begin();

    try {
      await _player.stop();
      final asset = await resolveIpaAsset(audioAssetKey, accent);
      if (asset == null) {
        debugPrint('No bundled IPA clip for $audioAssetKey ($accent)');
        return;
      }
      await _player.play(AssetSource(asset));
    } catch (e) {
      debugPrint('Error playing IPA phoneme audio $audioAssetKey ($accent): $e');
    } finally {
      AudioBackground.end();
      Future.delayed(const Duration(milliseconds: 1000), () {
        if (_currentlyPlayingTag == playTag) {
          _isPlaying = false;
          _currentlyPlayingTag = null;
          onStateChanged?.call(false);
        }
      });
    }
  }

  Future<void> playLetter(
    String letterKey, {
    String accent = 'us',
    void Function(bool isPlaying)? onStateChanged,
  }) async {
    final playTag = 'letter_${letterKey}_$accent';
    _currentlyPlayingTag = playTag;
    _isPlaying = true;
    onStateChanged?.call(true);
    AudioBackground.begin();

    try {
      final assetPath = 'audio/letters/${letterKey.toLowerCase()}_$accent.mp3';
      await _player.stop();
      await _player.play(AssetSource(assetPath));
    } catch (e) {
      debugPrint('Error playing letter audio $letterKey ($accent): $e');
    } finally {
      AudioBackground.end();
      Future.delayed(const Duration(milliseconds: 800), () {
        if (_currentlyPlayingTag == playTag) {
          _isPlaying = false;
          _currentlyPlayingTag = null;
          onStateChanged?.call(false);
        }
      });
    }
  }

  /// Plays one bundled clip and completes when it has finished sounding.
  ///
  /// The number module assembles a sentence out of single-word clips, so the
  /// caller must know when the current word ends before starting the next one —
  /// otherwise the words overlap. [rate] is applied by the player rather than
  /// baked into the clip, so one recording serves every speed.
  @override
  Future<void> playSpeechClip(String assetPath, {double rate = 1.0}) =>
      _playToCompletion(
        AssetSource(assetPath),
        tag: 'clip_$assetPath',
        label: assetPath,
        rate: rate,
      );

  /// Plays audio the module built itself (a spliced sentence, or Piper's
  /// samples) — one buffer, so nothing is read from disk on any platform.
  /// Last position the player reported, kept for a pause that arrives between
  /// two platform events. The getter API is a stream; reading it here avoids an
  /// async round trip racing the stop.
  Duration? _lastPosition;

  @override
  Duration? get playbackPosition => _lastPosition;

  @override
  Future<bool> playAudioBytes(Uint8List bytes,
          {double rate = 1.0,
          Duration startAt = Duration.zero,
          Future<void>? cancel}) =>
      _playBytes(bytes,
          extension: 'wav',
          mimeType: 'audio/wav',
          rate: rate,
          startAt: startAt,
          cancel: cancel);

  @override
  Future<bool> playOnlineClip(Uint8List bytes,
          {double rate = 1.0,
          Duration startAt = Duration.zero,
          Future<void>? cancel}) =>
      _playBytes(bytes,
          extension: 'mp3',
          mimeType: 'audio/mpeg',
          rate: rate,
          startAt: startAt,
          cancel: cancel);

  Future<bool> _playBytes(
    Uint8List bytes, {
    required String extension,
    required String mimeType,
    required double rate,
    Duration startAt = Duration.zero,
    Future<void>? cancel,
  }) async {
    // The Windows backend of audioplayers does not play a byte buffer: the clip
    // never starts and `_playToCompletion` just waits out its stall guard. That
    // was the whole "the app is silent but thinks it is speaking" bug — every
    // Piper-generated line took this path. The word recordings already avoid it
    // by staging their bytes in a file; do the same here.
    if (Platform.isWindows) {
      File? file;
      try {
        final dir = await getTemporaryDirectory();
        // The extension is part of the contract: the Windows backend picks its
        // decoder from it, and unique seq prevents overlapping writes/deletes.
        final id = _playId + 1;
        file = File(
            p.join(dir.path, 'speech_${id}_${bytes.length}_$extension.$extension'));
        await file.writeAsBytes(bytes, flush: true);
        return await _playToCompletion(
          DeviceFileSource(file.path),
          tag: 'bytes_${bytes.length}_$extension',
          label: '${bytes.length} bytes of $extension (staged)',
          rate: rate,
          startAt: startAt,
          cancel: cancel,
        );
      } on Exception catch (e) {
        debugPrint('Could not stage generated audio on disk: $e');
      } finally {
        try {
          if (file != null && file.existsSync()) file.deleteSync();
        } on FileSystemException {
          // A leftover temp file is not worth failing playback over.
        }
      }
    }
    return _playToCompletion(
      BytesSource(bytes, mimeType: mimeType),
      tag: 'bytes_${bytes.length}_$extension',
      label: '${bytes.length} bytes of $extension',
      rate: rate,
      startAt: startAt,
      cancel: cancel,
    );
  }

  Future<bool> _playToCompletion(
    Source source, {
    required String tag,
    required String label,
    required double rate,
    Duration startAt = Duration.zero,
    Future<void>? cancel,
  }) async {
    final playId = ++_playId;
    _currentlyPlayingTag = tag;
    _isPlaying = true;
    _lastPosition = Duration.zero;
    AudioBackground.begin();
    try {
      // Completion is what advances the queue: the clip must finish sounding
      // before the next word starts. No stop() before play() either: replacing
      // the source already ends whatever is sounding.
      //
      // The wait itself is in `awaitPlayback`, which explains why the obvious
      // `stream.first` — and the `timeout(onTimeout:)` variant before it — both
      // cut clips short.
      final completed = await awaitPlayback(
        completions: _player.onPlayerComplete,
        durations: _player.onDurationChanged,
        cancellations: _cancellations.stream,
        start: () async {
          if (playId != _playId) return;
          await _player.play(source);
          // After `play`, never before: the Windows backend applies the rate to
          // the media engine of the *current* source, and `play` loads a new one
          // — a rate set first is silently dropped (or lands on the clip that
          // just finished), which is why 语速 did nothing on the online voices.
          if (rate != 1.0 && playId == _playId) {
            try {
              await _player.setPlaybackRate(rate);
            } catch (e) {
              // Not every platform implements rate control; the clip still plays.
              debugPrint('Playback rate $rate unsupported: $e');
            }
          }
          if (startAt > Duration.zero) {
            // 继续 from a pause: pick the sentence up where it stopped.
            try {
              await _player.seek(startAt);
            } catch (e) {
              debugPrint('Seek to $startAt unsupported: $e');
            }
          }
        },
        cancel: cancel,
        minPlausible: _minPlausiblePlayback,
        durationWait: const Duration(milliseconds: 600),
        // A slower clip is allowed to take correspondingly longer: the reported
        // duration is the clip's own, and the guard must not call a 0.5×
        // playback "stalled" halfway through (it would then start the next line
        // over the one still sounding).
        stallGuard: (reported) {
          // The remaining part of the clip, not the whole of it: resuming at
          // 3 s of a 4 s line must not wait out 4 s plus the guard again.
          final remaining = reported == null
              ? null
              : (reported > startAt ? reported - startAt : Duration.zero);
          final base = _clipStallGuard(remaining);
          if (rate == 1.0) return base;
          return base * (1 / rate.clamp(0.25, 4.0)) +
              const Duration(milliseconds: 300);
        },
      );
      if (!completed && playId == _playId) {
        debugPrint('Speech clip $label did not report completion');
      }
      return completed;
    } catch (e) {
      debugPrint('Speech clip $label failed: $e');
      return false;
    } finally {
      AudioBackground.end();
      if (playId == _playId) {
        _isPlaying = false;
        _currentlyPlayingTag = null;
        try {
          await _player.setPlaybackRate(1.0);
        } catch (_) {}
      }
    }
  }

  double _volume = 1.0;

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    try {
      await _player.setVolume(_volume);
    } catch (e) {
      debugPrint('Setting the volume failed: $e');
    }
  }

  // ------------------------------------------------------------ sentence speech
  //
  // A number sentence ("one thousand two hundred and thirty-four") is spoken by
  // the system voice in one utterance, because recorded words played back to back
  // keep each word's citation form — its own final fall and its own pause. The
  // engine is SAPI: offline, free-form, and the only English voice this machine
  // has; when the requested accent has no voice here the manager says so and the
  // caller falls back to the recordings.

  /// The voice this machine would speak [accent] with, or null when it has no
  /// English voice at all (the UI then says the recordings are in use).
  @override
  Future<String?> sentenceVoiceLabel(String accent) async {
    final voice = await chosenSentenceVoice(accent);
    return voice == null ? null : sentenceVoiceDescription(voice, accent);
  }

  /// Speaks [sentence] as one utterance through this machine's own voice: the
  /// modern OneCore voices first (they render to a wav, which the player plays so
  /// the UI keeps control of speed and stopping), then SAPI. Returns false when
  /// there is no English voice, and the caller plays the recorded words instead.
  ///
  /// Never touches the network — the module has to work offline.
  @override
  Future<bool> speakSentence(
    String sentence, {
    String accent = 'us',
    double rate = 1.0,
  }) async {
    final voice = await chosenSentenceVoice(accent);
    if (voice == null) return false;
    final text = sentenceForSpeech(sentence);

    final playId = ++_playId;
    _currentlyPlayingTag = 'sentence_$accent';
    _isPlaying = true;
    AudioBackground.begin();
    try {
      if (voice.engine == VoiceEngine.oneCore) {
        final wav = await synthesizeWithVoice(text, voice, rate: rate);
        if (playId != _playId) return false;
        if (wav != null && await _playFileToCompletion(wav, playId: playId)) {
          return true;
        }
        if (playId != _playId) return false;
        // Fall through to SAPI if the modern engine could not produce audio.
        final sapi = chooseSentenceVoice(
          (await systemVoices()).where((v) => v.engine == VoiceEngine.sapi).toList(),
          accent,
        );
        if (sapi == null || playId != _playId) return false;
        return await speakWithSystemVoice(text, sapi, rate: rate, volume: _volume);
      }
      return await speakWithSystemVoice(text, voice, rate: rate, volume: _volume);
    } finally {
      AudioBackground.end();
      if (playId == _playId) {
        _isPlaying = false;
        _currentlyPlayingTag = null;
      }
    }
  }

  /// Plays a rendered wav and completes when it has finished sounding.
  Future<bool> _playFileToCompletion(String path, {required int playId}) async {
    try {
      final completed = await awaitPlayback(
        completions: _player.onPlayerComplete,
        durations: _player.onDurationChanged,
        cancellations: _cancellations.stream,
        start: () async {
          if (playId == _playId) await _player.play(DeviceFileSource(path));
        },
        minPlausible: _minPlausiblePlayback,
        durationWait: const Duration(milliseconds: 600),
        stallGuard: _utteranceStallGuard,
      );
      if (!completed && playId == _playId) {
        debugPrint('The rendered sentence did not report completion');
      }
      return completed;
    } catch (e) {
      debugPrint('Playing the rendered sentence failed: $e');
      return false;
    }
  }

  /// A completion arriving sooner than this after a playback starts cannot be
  /// that playback finishing — it is the previous source being torn down.
  /// Kept below the shortest clip the module plays (about 300 ms).
  static const Duration _minPlausiblePlayback = Duration(milliseconds: 120);

  /// Longest a recorded clip may take. The floor is longer than the longest clip
  /// (1.0 s), so the guard can never cut one short.
  static Duration _clipStallGuard(Duration? reported) {
    const floor = Duration(milliseconds: 1500);
    final cap = (reported ?? floor) * 1.4 + const Duration(milliseconds: 300);
    return cap > floor ? cap : floor;
  }

  /// Longest a rendered sentence may take. A rendered wav reports its duration,
  /// so the guard scales with it; without one, keep the generous cap the
  /// sentence path always had rather than clipping a long number.
  static Duration _utteranceStallGuard(Duration? reported) => reported == null
      ? const Duration(seconds: 30)
      : reported * 1.2 + const Duration(milliseconds: 500);

  @override
  Future<void> stop() async {
    _playId++;
    if (!_cancellations.isClosed) _cancellations.add(null);
    // A sentence is spoken by a child process (or played from a rendered file),
    // so stopping means killing the process and silencing the player.
    _lastPosition = null;
    cancelSystemVoice();
    AudioBackground.stopNow();
    try {
      await _player.stop();
    } catch (_) {}
    _isPlaying = false;
    _currentlyPlayingTag = null;
  }

  void dispose() {
    _playId++;
    if (!_cancellations.isClosed) {
      _cancellations.add(null);
      _cancellations.close();
    }
    _player.dispose();
  }
}
