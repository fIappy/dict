import 'dart:collection';
import 'dart:typed_data';

import 'online_tts.dart';
import 'word_audio_cache_types.dart';

export 'word_audio_cache_types.dart';

/// Bounded 10,000-word in-memory LRU cache for online word pronunciations on
/// Web, completely independent of [EntrySpeechProvider]'s sentence cache.
class WordAudioCache {
  static final WordAudioCache _instance = WordAudioCache._();
  factory WordAudioCache() => _instance;

  WordAudioCache._({int maxWords = defaultMaxWords}) : _maxWords = maxWords;

  WordAudioCache.withCapacity({int maxWords = defaultMaxWords})
      : _maxWords = maxWords;

  static const int defaultMaxWords = 10000;

  final int _maxWords;
  final LinkedHashMap<String, Map<String, Uint8List>> _lru =
      LinkedHashMap<String, Map<String, Uint8List>>();

  Future<Uint8List?> getBytes(String word, String accent) async {
    final key = normalizeWordCacheKey(word);
    if (key.isEmpty) return null;
    final normAccent = normalizeWordCacheAccent(accent);
    final accents = _lru[key];
    if (accents == null) return null;
    final bytes = accents[normAccent];
    if (bytes == null) return null;

    // Touch word to MRU tail.
    _lru.remove(key);
    _lru[key] = accents;
    return bytes;
  }

  Future<void> put(String word, String accent, Uint8List bytes) async {
    if (!OnlineTts.looksLikeAudio(bytes)) return;
    final key = normalizeWordCacheKey(word);
    if (key.isEmpty) return;
    final normAccent = normalizeWordCacheAccent(accent);

    final accents = _lru.remove(key) ?? <String, Uint8List>{};
    accents[normAccent] = bytes;
    _lru[key] = accents;

    while (_lru.length > _maxWords) {
      _lru.remove(_lru.keys.first);
    }
  }

  Future<WordAudioCacheStats> stats() async {
    var clips = 0;
    var totalBytes = 0;
    for (final accents in _lru.values) {
      clips += accents.length;
      for (final bytes in accents.values) {
        totalBytes += bytes.length;
      }
    }
    return WordAudioCacheStats(
      wordCount: _lru.length,
      clipCount: clips,
      totalBytes: totalBytes,
      maxWords: _maxWords,
    );
  }

  Future<void> clear() async {
    _lru.clear();
  }
}
