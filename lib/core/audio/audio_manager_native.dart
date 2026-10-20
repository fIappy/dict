import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../services/dictionary_service.dart';
import 'audio_background.dart';
import 'ipa_asset.dart';
import 'playback_wait.dart';
import 'sentence_voice.dart';
import 'speech_clip_player.dart';

class AudioManager implements SpeechClipPlayer {
  static final AudioManager _instance = AudioManager._();
  factory AudioManager() => _instance;
  AudioManager._();

  final AudioPlayer _player = AudioPlayer();
  final DictionaryService _dictService = DictionaryService();

  bool _isPlaying = false;
  String? _currentlyPlayingTag;

  bool get isPlaying => _isPlaying;
  String? get currentlyPlayingTag => _currentlyPlayingTag;

  /// Plays a pronunciation for [word].
  ///
  /// Resolution order:
  /// * **American** — the archive's own `.mdd` recording first (offline, exact),
  ///   then an online dictionary voice, then OS text-to-speech.
  /// * **British** — the bundled `.mdd` holds *American* recordings, so it is
  ///   never used here; British playback goes online, then OS text-to-speech.
  ///
  /// The online step is what keeps a dictionary imported **without** its `.mdd`
  /// audible: previously "美音" was a silent no-op on anything but Windows.
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
    AudioBackground.begin();

    try {
      if (accent == 'uk') {
        final ukClip = await _cachedOnlineClip(word, 'uk');
        if (ukClip != null) {
          await _player.stop();
          await _player.play(DeviceFileSource(ukClip));
          return;
        }
        await _speakWithOs(word);
        return;
      }

      // 1. The archive's own recording, available when the dictionary ships an .mdd.
      Uint8List? audioBytes;
      if (soundKey != null && soundKey.isNotEmpty) {
        audioBytes = await _dictService.getAudioBytes(soundKey);
      }
      audioBytes ??= await _dictService.getAudioBytes('$word.mp3');

      if (audioBytes != null && audioBytes.isNotEmpty) {
        try {
          if (Platform.isWindows) {
            final tempDir = await getTemporaryDirectory();
            final tempFile = File(p.join(tempDir.path, 'temp_audio_us.mp3'));
            await tempFile.writeAsBytes(audioBytes, flush: true);
            await _player.stop();
            await _player.play(DeviceFileSource(tempFile.path));
          } else {
            await _player.stop();
            await _player.play(BytesSource(audioBytes));
          }
          return;
        } catch (e) {
          debugPrint('AudioPlayer error: $e');
        }
      }

      // 2. No .mdd in this archive (e.g. an .mdx imported on its own): use the
      //    online voice instead of staying silent.
      final usClip = await _cachedOnlineClip(word, 'us');
      if (usClip != null) {
        await _player.stop();
        await _player.play(DeviceFileSource(usClip));
        return;
      }

      // 3. Offline and no archive audio: fall back to OS text-to-speech.
      await _speakWithOs(word);
    } catch (e) {
      debugPrint('Error playing pronunciation for $word: $e');
    } finally {
      AudioBackground.end();
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (_currentlyPlayingTag == playTag) {
          _isPlaying = false;
          _currentlyPlayingTag = null;
          onStateChanged?.call(false);
        }
      });
    }
  }

  /// Downloads one dictionary-voice clip and caches it on disk.
  ///
  /// Returns the cached file path, or null when the network is unavailable.
  Future<String?> _cachedOnlineClip(String word, String accent) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final safe = word.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
      final file = File(p.join(tempDir.path, 'tts_${accent}_$safe.mp3'));
      if (file.existsSync() && file.lengthSync() > 500) return file.path;

      // type=1 -> British voice, type=2 -> American voice.
      final type = accent == 'uk' ? 1 : 2;
      final url = Uri.parse(
        'https://dict.youdao.com/dictvoice?audio=${Uri.encodeComponent(word)}&type=$type',
      );
      final res = await http.get(url).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200 && res.bodyBytes.length > 500) {
        await file.writeAsBytes(res.bodyBytes, flush: true);
        return file.path;
      }
    } catch (e) {
      debugPrint('Failed to download $accent audio for $word: $e');
    }
    return null;
  }

  /// Last-resort speech synthesis; only Windows exposes a usable CLI.
  Future<void> _speakWithOs(String word) async {
    if (!Platform.isWindows) return;
    final clean = word.replaceAll("'", '').replaceAll('"', '');
    try {
      await Process.run('powershell', [
        '-Command',
        "(New-Object -ComObject SAPI.SpVoice).Speak('$clean')",
      ]);
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
  @override
  Future<void> playAudioBytes(Uint8List bytes, {double rate = 1.0}) =>
      _playToCompletion(
        BytesSource(bytes, mimeType: 'audio/wav'),
        tag: 'bytes_${bytes.length}',
        label: '${bytes.length} bytes of WAV',
        rate: rate,
      );

  Future<void> _playToCompletion(
    Source source, {
    required String tag,
    required String label,
    required double rate,
  }) async {
    _currentlyPlayingTag = tag;
    _isPlaying = true;
    AudioBackground.begin();
    try {
      if (rate != 1.0) {
        try {
          await _player.setPlaybackRate(rate);
        } catch (e) {
          // Not every platform implements rate control; the clip still plays.
          debugPrint('Playback rate $rate unsupported: $e');
        }
      }
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
        start: () => _player.play(source),
        minPlausible: _minPlausiblePlayback,
        durationWait: const Duration(milliseconds: 600),
        stallGuard: _clipStallGuard,
      );
      if (!completed) {
        debugPrint('Speech clip $label did not report completion');
      }
    } catch (e) {
      debugPrint('Speech clip $label failed: $e');
    } finally {
      AudioBackground.end();
      if (_currentlyPlayingTag == tag) {
        _isPlaying = false;
        _currentlyPlayingTag = null;
      }
      try {
        await _player.setPlaybackRate(1.0);
      } catch (_) {}
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

    _currentlyPlayingTag = 'sentence_$accent';
    _isPlaying = true;
    AudioBackground.begin();
    try {
      if (voice.engine == VoiceEngine.oneCore) {
        final wav = await synthesizeWithVoice(text, voice, rate: rate);
        if (wav != null && await _playFileToCompletion(wav)) return true;
        // Fall through to SAPI if the modern engine could not produce audio.
        final sapi = chooseSentenceVoice(
          (await systemVoices()).where((v) => v.engine == VoiceEngine.sapi).toList(),
          accent,
        );
        if (sapi == null) return false;
        return await speakWithSystemVoice(text, sapi, rate: rate);
      }
      return await speakWithSystemVoice(text, voice, rate: rate);
    } finally {
      AudioBackground.end();
      _isPlaying = false;
      _currentlyPlayingTag = null;
    }
  }

  /// Plays a rendered wav and completes when it has finished sounding.
  Future<bool> _playFileToCompletion(String path) async {
    try {
      final completed = await awaitPlayback(
        completions: _player.onPlayerComplete,
        durations: _player.onDurationChanged,
        start: () => _player.play(DeviceFileSource(path)),
        minPlausible: _minPlausiblePlayback,
        durationWait: const Duration(milliseconds: 600),
        stallGuard: _utteranceStallGuard,
      );
      if (!completed) {
        debugPrint('The rendered sentence did not report completion');
      }
      return true;
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
    // A sentence is spoken by a child process (or played from a rendered file),
    // so stopping means killing the process and silencing the player.
    cancelSystemVoice();
    AudioBackground.stopNow();
    try {
      await _player.stop();
      _isPlaying = false;
      _currentlyPlayingTag = null;
    } catch (_) {}
  }

  void dispose() {
    _player.dispose();
  }
}
