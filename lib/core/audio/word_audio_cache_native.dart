import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'disk_word_audio_cache.dart';

export 'word_audio_cache_types.dart';

/// Persistent 10,000-word LRU cache for online word pronunciations on native
/// platforms, completely independent of [EntrySpeechProvider]'s sentence cache.
class WordAudioCache {
  static final WordAudioCache _instance = WordAudioCache._();
  factory WordAudioCache() => _instance;

  WordAudioCache._() : _maxWords = DiskWordAudioCache.defaultMaxWords;

  WordAudioCache.atDirectory(
    Directory rootDir, {
    int maxWords = DiskWordAudioCache.defaultMaxWords,
  })  : _maxWords = maxWords,
        _disk = DiskWordAudioCache(rootDir, maxWords: maxWords);

  final int _maxWords;
  DiskWordAudioCache? _disk;
  Future<DiskWordAudioCache>? _opening;

  Future<DiskWordAudioCache> _ensureDisk() {
    final existing = _disk;
    if (existing != null) return Future<DiskWordAudioCache>.value(existing);
    return _opening ??= _openDisk().whenComplete(() {
      _opening = null;
    });
  }

  Future<DiskWordAudioCache> _openDisk() async {
    Directory? baseDir;
    try {
      final support = await getApplicationSupportDirectory();
      baseDir = Directory(p.join(support.path, 'local_dict', 'word_audio_cache'));
    } catch (_) {
      baseDir = Directory(
        p.join(Directory.systemTemp.path, 'local_dict_word_audio_cache'),
      );
    }
    return _disk = DiskWordAudioCache(baseDir, maxWords: _maxWords);
  }

  Future<String?> getPath(String word, String accent) async {
    final disk = await _ensureDisk();
    return disk.getPath(word, accent);
  }

  Future<String?> put(String word, String accent, Uint8List bytes) async {
    final disk = await _ensureDisk();
    return disk.put(word, accent, bytes);
  }

  Future<WordAudioCacheStats> stats() async {
    final disk = await _ensureDisk();
    return disk.stats();
  }

  Future<void> clear() async {
    final disk = await _ensureDisk();
    await disk.clear();
  }

  Future<void> flush() async {
    final disk = await _ensureDisk();
    await disk.flush();
  }
}
