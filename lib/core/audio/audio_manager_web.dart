import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../api/api_config.dart';
import '../services/dictionary_service.dart';
import 'ipa_asset.dart';
import 'sentence_voice.dart';
import 'speech_clip_player.dart';

/// Web implementation of the audio manager.
///
/// Pronunciation audio comes from the backend's `.mdd` archive when available
/// (identical recordings to the desktop build); otherwise it streams from an
/// online dictionary voice endpoint. Bundled IPA and alphabet assets always
/// play locally.
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
    await ApiConfig.resolve();

    // 1. Server-side .mdd archive: the same recording the native build plays.
    for (final key in [soundKey, '$word.mp3']) {
      if (key == null || key.isEmpty) continue;
      final bytes = await _dictService.getAudioBytes(key);
      if (bytes != null && bytes.isNotEmpty) {
        await _play(
          '${word}_$accent',
          BytesSource(bytes),
          onStateChanged: onStateChanged,
          resetAfter: const Duration(milliseconds: 1500),
        );
        return;
      }
    }

    // 2. Fallback: stream from an online dictionary voice endpoint.
    //    type=1 -> British voice, type=2 -> American voice.
    final type = accent == 'uk' ? 1 : 2;
    final url =
        'https://dict.youdao.com/dictvoice?audio=${Uri.encodeComponent(word)}&type=$type';
    await _play(
      '${word}_$accent',
      UrlSource(url),
      onStateChanged: onStateChanged,
      resetAfter: const Duration(milliseconds: 1500),
    );
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
    try {
      if (rate != 1.0) {
        try {
          await _player.setPlaybackRate(rate);
        } catch (e) {
          // Not supported everywhere; the clip still plays.
          debugPrint('Playback rate $rate unsupported: $e');
        }
      }
      // Completion is what advances the queue: the clip must finish sounding
      // before the next word starts. The timeout is only a stall guard, and it
      // can never cut a word short — the floor is longer than the longest clip
      // (1.0 s), so even a bogus duration report from the platform leaves the
      // clip playing to its end.
      // The wait is raced against a delay with Future.any, NOT with
      // `timeout(onTimeout:)`: that callback has to return the stream's own
      // element type, so a `() { … }` closure compiles but fails at runtime
      // ("type '() => Null' is not a subtype of '(() => FutureOr<AudioEvent>)?'")
      // — which returned immediately and cut every word short.
      final length = Future.any<Duration?>([
        _player.onDurationChanged.first,
        Future<Duration?>.delayed(const Duration(milliseconds: 600)),
      ]);
      final finished = _player.onPlayerComplete.first.then<void>((_) {});
      // No stop() before play(): replacing the source already ends whatever is
      // sounding, and stopping first is how a word gets chopped in half.
      await _player.play(source);
      final reported = await length;
      const floor = Duration(milliseconds: 1500);
      final cap = (reported ?? floor) * 1.4 + const Duration(milliseconds: 300);
      var completed = false;
      await Future.any<void>([
        finished.then((_) => completed = true),
        Future<void>.delayed(cap > floor ? cap : floor).then((_) {
          // The loser of the race still runs, so only a real stall is reported.
          if (!completed) {
            debugPrint('Speech clip $label did not report completion');
          }
        }),
      ]);
    } catch (e) {
      debugPrint('Speech clip $label failed: $e');
    } finally {
      if (_currentlyPlayingTag == tag) {
        _isPlaying = false;
        _currentlyPlayingTag = null;
      }
      try {
        await _player.setPlaybackRate(1.0);
      } catch (_) {}
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
    cancelSystemVoice();
    try {
      await _player.stop();
    } catch (_) {}
    _isPlaying = false;
    _currentlyPlayingTag = null;
  }

  void dispose() {
    _player.dispose();
  }
}
