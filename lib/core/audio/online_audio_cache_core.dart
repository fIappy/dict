import 'dart:convert';
import 'dart:typed_data';

import 'online_tts.dart';
import 'speech_engine.dart';

/// Identity of one cached clip: the engine that will read the sentence, the
/// accent, the speed the service is asked for, and the sentence itself.
///
/// The sentence alone is not enough. The same line is Aria on Edge, Sonia on
/// Google's `en-GB`, and a different voice again on 百度; Edge and 百度 bake the
/// speed into the audio, Google ignores it. Keying by sentence would replay
/// another engine's voice for a line the reader asked for with a different one.
///
/// The digest is two 32-bit sdbm passes over UTF-8 — 16 hex characters, no
/// dependency, deterministic on the VM and under dart2js (every intermediate
/// stays below 2^49, where a double is still exact). A collision would hand a
/// sentence its own number but somebody else's audio; with a 64-bit key and
/// 1000 entries that is a ~3e-13 chance, far below the chance of a storage
/// error.
String onlineAudioKey(
  SpeechEngine engine, {
  required String text,
  required String accent,
  double rate = 1.0,
}) {
  // Ask each engine for exactly what it actually receives: 百度 maps the
  // slider onto seven integer speeds, Google has no speed knob at all.
  final speed = switch (engine) {
    SpeechEngine.edge => rate.toStringAsFixed(2),
    SpeechEngine.baidu => '${OnlineTts.baiduSpeed(rate)}',
    SpeechEngine.google => '-',
    SpeechEngine.kokoro || SpeechEngine.system => '-',
  };
  // 百度 always reads English (`lan=en`); accent does not reach the service.
  final voice = engine == SpeechEngine.baidu ? 'en' : accent;
  final bytes = utf8.encode('${engine.name}|$voice|$speed|${text.trim()}');
  return '${_sdbm(bytes, 0)}${_sdbm(bytes, 0x9E3779B9)}';
}

const int _mask32 = 0xFFFFFFFF;

String _sdbm(List<int> bytes, int seed) {
  var hash = seed & _mask32;
  for (final byte in bytes) {
    hash = (byte + (hash << 6) + (hash << 16) - hash) & _mask32;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

/// One clip's standing in the queue.
class AudioCacheEntry {
  const AudioCacheEntry({
    required this.hits,
    required this.seq,
    required this.bytes,
  });

  /// How many times this clip was read back from the cache.
  final int hits;

  /// Insertion order. Never refreshed on a hit: equal-hit clips leave oldest
  /// first, which is the FIFO tie-break the queue is specified with.
  final int seq;

  final int bytes;
}

/// Which clips the cache keeps when it is full.
///
/// The rule is frequency first, age second: the clip read the fewest times is
/// dropped; among clips read equally often, the one that entered first goes.
/// [maxBytes] is a second ceiling because an entry count alone says nothing
/// about disk use — a thousand long sentences can run into gigabytes.
class AudioCacheLedger {
  AudioCacheLedger({
    this.maxEntries = 1000,
    this.maxBytes = 96 << 20,
    Map<String, AudioCacheEntry>? seed,
  }) : _entries = {...?seed} {
    _totalBytes = _entries.values.fold(0, (sum, e) => sum + e.bytes);
    _nextSeq = _entries.values.fold(0, (max, e) => e.seq >= max ? e.seq + 1 : max);
  }

  factory AudioCacheLedger.fromJson(
    Object? json, {
    int maxEntries = 1000,
    int maxBytes = 96 << 20,
  }) {
    if (json is! Map<String, dynamic>) {
      return AudioCacheLedger(maxEntries: maxEntries, maxBytes: maxBytes);
    }
    final raw = json['entries'];
    final seed = <String, AudioCacheEntry>{};
    if (raw is Map) {
      raw.forEach((key, value) {
        if (key is! String || value is! List || value.length < 3) return;
        final hits = value[0];
        final seq = value[1];
        final bytes = value[2];
        if (hits is! int || seq is! int || bytes is! int) return;
        if (bytes <= 0) return;
        seed[key] = AudioCacheEntry(hits: hits, seq: seq, bytes: bytes);
      });
    }
    return AudioCacheLedger(
      maxEntries: maxEntries,
      maxBytes: maxBytes,
      seed: seed,
    );
  }

  final int maxEntries;
  final int maxBytes;
  final Map<String, AudioCacheEntry> _entries;
  int _nextSeq = 0;
  int _totalBytes = 0;

  int get length => _entries.length;
  int get totalBytes => _totalBytes;
  Iterable<String> get keys => _entries.keys;
  AudioCacheEntry? operator [](String key) => _entries[key];
  bool contains(String key) => _entries.containsKey(key);

  /// A clip was read back: it moves ahead of every clip with fewer hits.
  void heart(String key) {
    final entry = _entries[key];
    if (entry == null) return;
    _entries[key] = AudioCacheEntry(
      hits: entry.hits + 1,
      seq: entry.seq,
      bytes: entry.bytes,
    );
  }

  /// Adds [key] (a new clip or a repeat) and returns the clips to delete.
  ///
  /// The newcomer counts as one read, so a clip that comes back after eviction
  /// is not immediately the least wanted one.
  List<String> store(String key, int bytes) {
    final entry = _entries[key];
    if (entry != null) {
      heart(key);
      return const [];
    }
    _entries[key] = AudioCacheEntry(hits: 1, seq: _nextSeq++, bytes: bytes);
    _totalBytes += bytes;
    return trim();
  }

  /// Adopts a file the index lost (a crash between writing the clip and the
  /// index), so the queue does not grow past its bounds after one bad exit.
  void adopt(String key, int bytes) {
    if (_entries.containsKey(key) || bytes <= 0) return;
    _entries[key] = AudioCacheEntry(hits: 1, seq: _nextSeq++, bytes: bytes);
    _totalBytes += bytes;
  }

  bool remove(String key) {
    final entry = _entries.remove(key);
    if (entry == null) return false;
    _totalBytes -= entry.bytes;
    return true;
  }

  /// Drops clips over either ceiling; returns what the caller must delete.
  List<String> trim() {
    final evicted = <String>[];
    while (_entries.length > maxEntries || _totalBytes > maxBytes) {
      String? victim;
      AudioCacheEntry? worst;
      for (final item in _entries.entries) {
        final e = item.value;
        if (worst == null || e.hits < worst.hits ||
            (e.hits == worst.hits && e.seq < worst.seq)) {
          worst = e;
          victim = item.key;
        }
      }
      // A single clip larger than the whole budget is refused by the store
      // before it gets here; this only guards against a loop that never ends.
      if (victim == null) break;
      _entries.remove(victim);
      _totalBytes -= worst!.bytes;
      evicted.add(victim);
    }
    return evicted;
  }

  /// Compact form for the index file: `{"entries":{"<key>":[hits,seq,bytes]}}`.
  Map<String, Object?> toJson() => {
        'entries': {
          for (final item in _entries.entries)
            item.key: [item.value.hits, item.value.seq, item.value.bytes],
        },
      };
}

/// Where the audio bytes and their standing live.
///
/// Native targets keep clips and the index under the app's support directory;
/// the browser keeps them for the life of the tab (no file system, and the
/// browser's own HTTP cache already helps across reloads).
abstract class OnlineAudioStore {
  /// The cached clip for [key], or null. Counts as a read.
  Future<Uint8List?> read(String key);

  /// Keeps [bytes] under [key] and evicts whatever the queue no longer holds.
  Future<void> write(String key, Uint8List bytes);

  /// Writes the index out now; the native store otherwise debounces it.
  Future<void> flush();

  /// Clips currently held — for diagnostics and tests.
  int get length;
}
