import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'online_tts.dart';
import 'word_audio_cache_types.dart';

export 'word_audio_cache_types.dart';

/// Persistent disk LRU cache for online word pronunciation clips.
///
/// Capacity is counted by **distinct normalized words** ([defaultMaxWords] =
/// 10,000), independent of [EntrySpeechProvider]'s in-memory sentence cache.
class DiskWordAudioCache {
  DiskWordAudioCache(
    this.rootDir, {
    this.maxWords = defaultMaxWords,
  });

  static const int defaultMaxWords = 10000;
  static const String _indexFileName = 'index.json';

  final Directory rootDir;
  final int maxWords;

  /// Ordered oldest (LRU, first) -> newest (MRU, last).
  final LinkedHashMap<String, Map<String, int>> _lru =
      LinkedHashMap<String, Map<String, int>>();
  bool _loaded = false;
  bool _dirty = false;
  Future<void> _queue = Future<void>.value();

  Future<T> _serialized<T>(Future<T> Function() action) {
    final prev = _queue;
    late final Future<T> next;
    next = prev.catchError((_) {}).then((_) => action());
    _queue = next.then((_) {}, onError: (_) {});
    return next;
  }

  File _clipFileFor(String normalizedWord, String normAccent) {
    final hash = wordCacheHash(normalizedWord);
    final bucket = hash.substring(0, 2);
    return File(p.join(rootDir.path, bucket, '${hash}_$normAccent.mp3'));
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    final indexFile = File(p.join(rootDir.path, _indexFileName));
    if (!indexFile.existsSync()) return;
    try {
      final decoded = json.decode(indexFile.readAsStringSync());
      if (decoded is! Map) return;
      final entries = decoded['entries'];
      if (entries is! List) return;
      for (final raw in entries) {
        if (raw is! Map) continue;
        final w = raw['w'];
        final a = raw['a'];
        if (w is! String || w.isEmpty || a is! Map) continue;
        final accents = <String, int>{};
        a.forEach((key, value) {
          if (key is String && value is num && value > 0) {
            accents[key] = value.toInt();
          }
        });
        if (accents.isNotEmpty) {
          _lru[w] = accents;
        }
      }
      if (_lru.length > maxWords) {
        _evictExcessSync();
        await _persistIndex();
      }
    } catch (_) {
      _lru.clear();
    }
  }

  Future<String?> getPath(String word, String accent) =>
      _serialized(() async {
        await _ensureLoaded();
        final key = normalizeWordCacheKey(word);
        if (key.isEmpty) return null;
        final normAccent = normalizeWordCacheAccent(accent);
        final accents = _lru[key];
        if (accents == null || !accents.containsKey(normAccent)) {
          return null;
        }

        final file = _clipFileFor(key, normAccent);
        if (!file.existsSync() || file.lengthSync() < 512) {
          accents.remove(normAccent);
          if (accents.isEmpty) {
            _lru.remove(key);
          }
          _dirty = true;
          return null;
        }

        // Touch word to MRU tail.
        _lru.remove(key);
        _lru[key] = accents;
        _dirty = true;
        return file.path;
      });

  Future<String?> put(String word, String accent, Uint8List bytes) =>
      _serialized(() async {
        if (!OnlineTts.looksLikeAudio(bytes)) return null;
        await _ensureLoaded();
        final key = normalizeWordCacheKey(word);
        if (key.isEmpty) return null;
        final normAccent = normalizeWordCacheAccent(accent);

        if (!rootDir.existsSync()) {
          rootDir.createSync(recursive: true);
        }
        final file = _clipFileFor(key, normAccent);
        if (!file.parent.existsSync()) {
          file.parent.createSync(recursive: true);
        }

        final tmp = File('${file.path}.tmp');
        try {
          await tmp.writeAsBytes(bytes, flush: true);
          if (file.existsSync()) file.deleteSync();
          tmp.renameSync(file.path);
        } on FileSystemException {
          try {
            if (tmp.existsSync()) tmp.deleteSync();
          } catch (_) {}
          await file.writeAsBytes(bytes, flush: true);
        }

        final accents = _lru.remove(key) ?? <String, int>{};
        accents[normAccent] = bytes.length;
        _lru[key] = accents;

        _evictExcessSync();
        await _persistIndex();
        return file.path;
      });

  void _evictExcessSync() {
    while (_lru.length > maxWords) {
      final oldestKey = _lru.keys.first;
      final accents = _lru.remove(oldestKey);
      if (accents != null) {
        for (final acc in accents.keys) {
          final file = _clipFileFor(oldestKey, acc);
          try {
            if (file.existsSync()) file.deleteSync();
          } catch (_) {}
        }
      }
      _dirty = true;
    }
  }

  Future<void> _persistIndex() async {
    if (!rootDir.existsSync()) {
      rootDir.createSync(recursive: true);
    }
    final payload = json.encode({
      'version': 1,
      'entries': [
        for (final e in _lru.entries)
          {
            'w': e.key,
            'a': e.value,
          },
      ],
    });
    final target = File(p.join(rootDir.path, _indexFileName));
    final tmp = File('${target.path}.tmp');
    try {
      await tmp.writeAsString(payload, flush: true);
      if (target.existsSync()) target.deleteSync();
      tmp.renameSync(target.path);
    } on FileSystemException {
      try {
        if (tmp.existsSync()) tmp.deleteSync();
      } catch (_) {}
      await target.writeAsString(payload, flush: true);
    }
    _dirty = false;
  }

  Future<void> flush() => _serialized(() async {
        if (!_loaded || !_dirty) return;
        await _persistIndex();
      });

  Future<WordAudioCacheStats> stats() => _serialized(() async {
        await _ensureLoaded();
        var clips = 0;
        var bytes = 0;
        for (final accents in _lru.values) {
          clips += accents.length;
          for (final size in accents.values) {
            bytes += size;
          }
        }
        return WordAudioCacheStats(
          wordCount: _lru.length,
          clipCount: clips,
          totalBytes: bytes,
          maxWords: maxWords,
        );
      });

  Future<void> clear() => _serialized(() async {
        _lru.clear();
        _loaded = true;
        _dirty = false;
        if (rootDir.existsSync()) {
          try {
            rootDir.deleteSync(recursive: true);
          } catch (_) {}
        }
      });
}
