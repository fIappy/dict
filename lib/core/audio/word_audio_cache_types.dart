import 'dart:convert';

class WordAudioCacheStats {
  const WordAudioCacheStats({
    required this.wordCount,
    required this.clipCount,
    required this.totalBytes,
    required this.maxWords,
  });

  final int wordCount;
  final int clipCount;
  final int totalBytes;
  final int maxWords;
}

String normalizeWordCacheKey(String word) => word
    .trim()
    .replaceAll('\u2019', "'")
    .replaceAll('\u2018', "'")
    .replaceAll("''", "'")
    .toLowerCase();

String normalizeWordCacheAccent(String accent) =>
    accent.trim().toLowerCase() == 'uk' ? 'uk' : 'us';

/// Deterministic 64-bit hex hash computed in pure 32-bit halves (identical
/// across VM and JS) so Windows reserved filenames (`con`, `aux`, `prn`, `nul`)
/// never hit the filesystem.
String wordCacheHash(String normalizedWord) {
  String fnv32(int seed) {
    var hash = seed & 0xFFFFFFFF;
    for (final unit in utf8.encode(normalizedWord)) {
      hash ^= unit;
      // Multiply cleanly modulo 2^32 using 16-bit halves for web/VM parity.
      final low = (hash & 0xFFFF) * 0x0193;
      final high = (((hash >> 16) & 0xFFFF) * 0x0193 +
              (hash & 0xFFFF) * 0x0100) &
          0xFFFF;
      hash = (low + (high << 16)) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  return '${fnv32(0x811c9dc5)}${fnv32(0x9e3779b9)}';
}
