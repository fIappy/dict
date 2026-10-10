import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../api/api_config.dart';
import '../services/dictionary_service.dart';
import 'ipa_asset.dart';

/// Web implementation of the audio manager.
///
/// Pronunciation audio comes from the backend's `.mdd` archive when available
/// (identical recordings to the desktop build); otherwise it streams from an
/// online dictionary voice endpoint. Bundled IPA and alphabet assets always
/// play locally.
class AudioManager {
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

  Future<void> stop() async {
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
