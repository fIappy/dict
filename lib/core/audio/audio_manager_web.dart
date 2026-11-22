import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../api/api_config.dart';
import 'ipa_asset.dart';
import 'online_tts.dart';
import 'playback_wait.dart';
import 'prepared_pronunciation.dart';
import 'sentence_voice.dart';
import 'speech_clip_player.dart';
import 'word_audio_cache_web.dart';

/// Web implementation of the audio manager.
///
/// Word pronunciation uses online voice endpoints (proxied & cached up to
/// 10,000 words when the backend proxy is reachable, with direct streaming
/// fallback). Bundled IPA and alphabet assets always play locally.
class AudioManager implements SpeechClipPlayer {
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

  static final AudioManager _instance = AudioManager._();
  factory AudioManager() => _instance;
  AudioManager._();

  final AudioPlayer _player = AudioPlayer();
  final WordAudioCache _wordCache = WordAudioCache();
  final http.Client _http = http.Client();
  final StreamController<void> _cancellations = StreamController<void>.broadcast();
  int _playId = 0;

  WordAudioCache get wordCache => _wordCache;

  bool _isPlaying = false;
  String? _currentlyPlayingTag;

  bool get isPlaying => _isPlaying;
  String? get currentlyPlayingTag => _currentlyPlayingTag;

  Future<void> _play(
    String playTag,
    Source source, {
    void Function(bool isPlaying)? onStateChanged,
    Duration resetAfter = const Duration(milliseconds: 1200),
  }) async {
    _currentlyPlayingTag = playTag;
    _isPlaying = true;
    onStateChanged?.call(true);

    try {
      await _player.stop();
      await _player.play(source);
    } catch (e) {
      debugPrint('Web audio error for $playTag: $e');
    } finally {
      Future.delayed(resetAfter, () {
        if (_currentlyPlayingTag == playTag) {
          _isPlaying = false;
          _currentlyPlayingTag = null;
          onStateChanged?.call(false);
        }
      });
    }
  }

  Future<void> playWord({
    required String word,
    String? soundKey,
    String accent = 'us',
    void Function(bool isPlaying)? onStateChanged,
  }) async {
    final normAccent = normalizeWordCacheAccent(accent);
    final cached = await _wordCache.getBytes(word, normAccent);
    if (cached != null) {
      await _play(
        '${word}_$normAccent',
        BytesSource(cached, mimeType: 'audio/mpeg'),
        onStateChanged: onStateChanged,
        resetAfter: const Duration(milliseconds: 1500),
      );
      return;
    }

    final clip = await prepareWord(
      word: word,
      soundKey: soundKey,
      accent: normAccent,
    );
    final Source source;
    if (clip.bytes != null) {
      source = BytesSource(clip.bytes!, mimeType: 'audio/mpeg');
    } else if (clip.url != null) {
      source = UrlSource(clip.url!);
    } else {
      return;
    }
    await _play(
      '${word}_$normAccent',
      source,
      onStateChanged: onStateChanged,
      resetAfter: const Duration(milliseconds: 1500),
    );
  }

  /// Resolves [word]'s audio without playing it, so the drill can queue words
  /// ahead and keep the configured gap between them.
  Future<PreparedPronunciation> prepareWord({
    required String word,
    String? soundKey,
    String accent = 'us',
  }) async {
    final normAccent = normalizeWordCacheAccent(accent);
    final cached = await _wordCache.getBytes(word, normAccent);
    if (cached != null) {
      return PreparedPronunciation(word: word, bytes: cached);
    }

    await ApiConfig.resolve();
    try {
      final uri = ApiConfig.endpoint('/api/word-audio', {
        'word': word,
        'accent': normAccent,
      });
      final res = await _http.get(uri).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200 && OnlineTts.looksLikeAudio(res.bodyBytes)) {
        await _wordCache.put(word, normAccent, res.bodyBytes);
        return PreparedPronunciation(word: word, bytes: res.bodyBytes);
      }
    } catch (_) {}

    final type = normAccent == 'uk' ? 1 : 2;
    return PreparedPronunciation(
      word: word,
      url: 'https://dict.youdao.com/dictvoice'
          '?audio=${Uri.encodeComponent(word)}&type=$type',
    );
  }

  /// Plays a prepared clip and waits for it to end.
  Future<void> playPrepared(
    PreparedPronunciation clip, {
    Duration maxWait = const Duration(seconds: 6),
  }) async {
    final Source source;
    if (clip.bytes != null) {
      source = BytesSource(clip.bytes!);
    } else if (clip.path != null) {
      source = UrlSource(clip.path!);
    } else if (clip.url != null) {
      source = UrlSource(clip.url!);
    } else {
      return;
    }
    await _play('${clip.word}_clip', source);
    try {
      await _player.onPlayerComplete.first.timeout(maxWait);
    } on TimeoutException {
      await _player.stop();
    } catch (e) {
      debugPrint('Pronunciation of ${clip.word} did not report its end: $e');
    }
  }

  /// Plays [word] and waits for the clip to end — the 背词 loop needs one word
  /// to finish before the next starts.
  Future<void> playWordAndWait({
    required String word,
    String? soundKey,
    String accent = 'us',
    Duration maxWait = const Duration(seconds: 6),
  }) async {
    await playWord(word: word, soundKey: soundKey, accent: accent);
    try {
      await _player.onPlayerComplete.first.timeout(maxWait);
    } on TimeoutException {
      await _player.stop();
    } catch (e) {
      debugPrint('Pronunciation completion not reported for $word: $e');
    }
  }

  /// Cuts the pronunciation in flight.
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

  Future<void> playIpaPhoneme(
    String audioAssetKey, {
    String accent = 'uk',
    void Function(bool isPlaying)? onStateChanged,
  }) async {
    final asset = await resolveIpaAsset(audioAssetKey, accent);
    if (asset == null) {
      debugPrint('No bundled IPA clip for $audioAssetKey ($accent)');
      return;
    }
    await _play(
      'ipa_${audioAssetKey}_$accent',
      AssetSource(asset),
      onStateChanged: onStateChanged,
      resetAfter: const Duration(milliseconds: 1000),
    );
  }

  Future<void> playLetter(
    String letterKey, {
    String accent = 'us',
    void Function(bool isPlaying)? onStateChanged,
  }) async {
    await _play(
      'letter_${letterKey}_$accent',
      AssetSource('audio/letters/${letterKey.toLowerCase()}_$accent.mp3'),
      onStateChanged: onStateChanged,
      resetAfter: const Duration(milliseconds: 800),
    );
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
  /// samples). On web `BytesSource` becomes a blob URL, so nothing is written to
  /// disk.
  @override
  Future<bool> playAudioBytes(Uint8List bytes, {double rate = 1.0}) =>
      _playToCompletion(
        BytesSource(bytes, mimeType: 'audio/wav'),
        tag: 'bytes_${bytes.length}',
        label: '${bytes.length} bytes of WAV',
        rate: rate,
      );

  @override
  Future<bool> playOnlineClip(Uint8List bytes, {double rate = 1.0}) =>
      _playToCompletion(
        BytesSource(bytes, mimeType: 'audio/mpeg'),
        tag: 'mp3_${bytes.length}',
        label: '${bytes.length} bytes of MP3',
        rate: rate,
      );

  Future<bool> _playToCompletion(
    Source source, {
    required String tag,
    required String label,
    required double rate,
  }) async {
    final playId = ++_playId;
    _currentlyPlayingTag = tag;
    _isPlaying = true;
    try {
      // Completion is what advances the queue: the clip must finish sounding
      // before the next word starts. No stop() before play() either: replacing
      // the source already ends whatever is sounding, and stopping first is how
      // a word gets chopped in half.
      //
      // The wait is in `awaitPlayback`, which explains why `stream.first` (and
      // the `timeout(onTimeout:)` variant before it) both cut clips short.
      final completed = await awaitPlayback(
        completions: _player.onPlayerComplete,
        durations: _player.onDurationChanged,
        cancellations: _cancellations.stream,
        start: () async {
          if (playId != _playId) return;
          await _player.play(source);
          // After `play`: loading the source resets the element's rate.
          if (rate != 1.0 && playId == _playId) {
            try {
              await _player.setPlaybackRate(rate);
            } catch (e) {
              debugPrint('Playback rate $rate unsupported: $e');
            }
          }
        },
        minPlausible: _minPlausiblePlayback,
        durationWait: const Duration(milliseconds: 600),
        stallGuard: _clipStallGuard,
      );
      if (!completed && playId == _playId) {
        debugPrint('Speech clip $label did not report completion');
      }
      return completed;
    } catch (e) {
      debugPrint('Speech clip $label failed: $e');
      return false;
    } finally {
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

  /// Speaks the whole sentence with the browser's own voice, so "twenty-four" is
  /// read as one number instead of the module playing the `twenty` and `four`
  /// recordings back to back. Returns false when the browser has no voice (or
  /// refuses to speak), and the caller then uses the recordings, which stay the
  /// offline-safe path.
  @override
  Future<bool> speakSentence(
    String sentence, {
    String accent = 'us',
    double rate = 1.0,
  }) async {
    final voice = await chosenSentenceVoice(accent);
    if (voice == null) return false;

    _currentlyPlayingTag = 'sentence_$accent';
    _isPlaying = true;
    try {
      return await speakWithSystemVoice(
        sentenceForSpeech(sentence),
        voice,
        rate: rate,
        volume: _volume,
      );
    } finally {
      _isPlaying = false;
      _currentlyPlayingTag = null;
    }
  }

  @override
  Future<String?> sentenceVoiceLabel(String accent) async {
    final voice = await chosenSentenceVoice(accent);
    return voice == null ? null : sentenceVoiceDescription(voice, accent);
  }

  @override
  Future<void> stop() async {
    _playId++;
    if (!_cancellations.isClosed) _cancellations.add(null);
    cancelSystemVoice();
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
    _http.close();
    _player.dispose();
  }
}
