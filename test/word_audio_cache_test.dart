import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_dict/core/audio/disk_word_audio_cache.dart';
import 'package:local_dict/providers/entry_speech_provider.dart';
import 'package:path/path.dart' as p;

Uint8List _fakeMp3([int seed = 1]) {
  final bytes = Uint8List(768);
  bytes[0] = 0x49; // 'I'
  bytes[1] = 0x44; // 'D'
  bytes[2] = 0x33; // '3'
  for (var i = 3; i < bytes.length; i++) {
    bytes[i] = (seed + i) & 0xFF;
  }
  return bytes;
}

void main() {
  group('DiskWordAudioCache (independent 10,000-word LRU)', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('word_audio_cache_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('uses default capacity of 10,000 words independent of sentence cache', () {
      expect(DiskWordAudioCache.defaultMaxWords, 10000);
      expect(EntrySpeechProvider.clipCacheSize, 32);
    });

    test('stores hashed clips safely, counts US+UK as one word, and normalizes keys',
        () async {
      final cache = DiskWordAudioCache(tempDir, maxWords: 10);

      final conPath = await cache.put('con', 'us', _fakeMp3(10));
      expect(conPath, isNotNull);
      expect(File(conPath!).existsSync(), isTrue);
      expect(p.basename(conPath), isNot('con.mp3'));

      // Curly apostrophe and uppercase resolve to the same word slot.
      await cache.put('Don’t', 'uk', _fakeMp3(11));
      final hitDon = await cache.getPath("don't", 'uk');
      expect(hitDon, isNotNull);

      // Same word with both US and UK clips counts as 1 word, 2 clips.
      await cache.put('con', 'uk', _fakeMp3(12));
      final stats = await cache.stats();
      expect(stats.wordCount, 2);
      expect(stats.clipCount, 3);
      expect(stats.totalBytes, 768 * 3);
      expect(stats.maxWords, 10);

      // Reopening from disk preserves persisted index & stats.
      final reopened = DiskWordAudioCache(tempDir, maxWords: 10);
      final reopenedStats = await reopened.stats();
      expect(reopenedStats.wordCount, 2);
      expect(reopenedStats.clipCount, 3);
      expect(await reopened.getPath('CON', 'us'), conPath);
    });

    test('rejects HTML error responses and tiny payloads', () async {
      final cache = DiskWordAudioCache(tempDir, maxWords: 10);

      expect(await cache.put('bad1', 'us', Uint8List.fromList([0x49, 0x44, 0x33, 0])), isNull);
      final html = Uint8List.fromList('<html><body>502</body></html>'.padRight(800, ' ').codeUnits);
      expect(await cache.put('bad2', 'us', html), isNull);

      final stats = await cache.stats();
      expect(stats.wordCount, 0);
      expect(stats.clipCount, 0);
    });

    test('evicts LRU word and deletes its audio files when exceeding maxWords', () async {
      final cache = DiskWordAudioCache(tempDir, maxWords: 5);

      final pathW1Us = await cache.put('w1', 'us', _fakeMp3(1));
      final pathW1Uk = await cache.put('w1', 'uk', _fakeMp3(2));
      final pathW2 = await cache.put('w2', 'us', _fakeMp3(3));
      await cache.put('w3', 'us', _fakeMp3(4));
      await cache.put('w4', 'us', _fakeMp3(5));
      await cache.put('w5', 'us', _fakeMp3(6));

      // Touch w1 so w2 becomes the oldest LRU word, then insert w6 & w7.
      expect(await cache.getPath('w1', 'us'), pathW1Us);
      await cache.put('w6', 'us', _fakeMp3(7));
      await cache.put('w7', 'us', _fakeMp3(8));

      final stats = await cache.stats();
      expect(stats.wordCount, 5);

      // w1 survived (both US & UK), while w2 and w3 were evicted & unlinked.
      expect(await cache.getPath('w1', 'uk'), pathW1Uk);
      expect(await cache.getPath('w2', 'us'), isNull);
      expect(await cache.getPath('w3', 'us'), isNull);
      expect(File(pathW2!).existsSync(), isFalse);
      await cache.flush();

      // Persisted state reflects eviction after reopen.
      final reopened = DiskWordAudioCache(tempDir, maxWords: 5);
      expect((await reopened.stats()).wordCount, 5);
      expect(await reopened.getPath('w2', 'us'), isNull);
      expect(await reopened.getPath('w7', 'us'), isNotNull);

      // Clearing deletes everything cleanly.
      await reopened.clear();
      final emptyStats = await reopened.stats();
      expect(emptyStats.wordCount, 0);
      expect(emptyStats.clipCount, 0);
      expect(emptyStats.totalBytes, 0);
    });
  });
}
