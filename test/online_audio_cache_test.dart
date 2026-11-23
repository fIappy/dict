import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_dict/core/audio/online_audio_cache.dart';
import 'package:local_dict/core/audio/online_audio_cache_core.dart';
import 'package:local_dict/core/audio/online_audio_cache_store_native.dart';
import 'package:local_dict/core/audio/speech_engine.dart';

Uint8List _clip(int seed, [int length = 700]) =>
    Uint8List.fromList(List<int>.generate(length, (i) => (seed + i) & 0xFF));

class _FakeStore implements OnlineAudioStore {
  final Map<String, Uint8List> clips = {};
  int reads = 0;
  int writes = 0;

  @override
  int get length => clips.length;

  @override
  Future<Uint8List?> read(String key) async {
    reads++;
    return clips[key];
  }

  @override
  Future<void> write(String key, Uint8List bytes) async {
    writes++;
    clips[key] = bytes;
  }

  @override
  Future<void> flush() async {}
}

class _BrokenStore implements OnlineAudioStore {
  @override
  int get length => 0;

  @override
  Future<Uint8List?> read(String key) async =>
      throw const FileSystemException('read-only');

  @override
  Future<void> write(String key, Uint8List bytes) async =>
      throw const FileSystemException('read-only');

  @override
  Future<void> flush() async => throw const FileSystemException('read-only');
}

void main() {
  group('key', () {
    test('is stable and short enough for a file name', () {
      final a = onlineAudioKey(SpeechEngine.edge,
          text: 'I just got back.', accent: 'us', rate: 1.0);
      final b = onlineAudioKey(SpeechEngine.edge,
          text: '  I just got back.  ', accent: 'us', rate: 1.0);
      expect(a, b);
      expect(a, matches(RegExp(r'^[0-9a-f]{16}$')));
    });

    test('separates engines, accents and the rates they actually receive', () {
      String key(SpeechEngine engine, {String accent = 'us', double rate = 1.0}) =>
          onlineAudioKey(engine,
              text: 'Good morning.', accent: accent, rate: rate);

      expect(key(SpeechEngine.edge), isNot(key(SpeechEngine.google)));
      expect(key(SpeechEngine.edge, accent: 'uk'),
          isNot(key(SpeechEngine.edge, accent: 'us')));
      expect(key(SpeechEngine.edge, rate: 1.0),
          isNot(key(SpeechEngine.edge, rate: 0.8)));

      // Google's endpoint has no speed parameter: one clip serves every rate.
      expect(key(SpeechEngine.google, rate: 0.5),
          key(SpeechEngine.google, rate: 1.5));
      // 百度 always reads English; the accent never reaches it.
      expect(key(SpeechEngine.baidu, accent: 'uk'),
          key(SpeechEngine.baidu, accent: 'us'));
      // Its speed knob is seven steps, so neighbouring rates share a clip.
      final slow = onlineAudioKey(SpeechEngine.baidu,
          text: 'Good morning.', accent: 'us', rate: 0.55);
      final slower = onlineAudioKey(SpeechEngine.baidu,
          text: 'Good morning.', accent: 'us', rate: 0.56);
      expect(slow, slower);
    });
  });

  group('ledger', () {
    test('drops the least-read clip, oldest first on a tie', () {
      final ledger = AudioCacheLedger(maxEntries: 3);
      expect(ledger.store('a', 100), isEmpty);
      expect(ledger.store('b', 100), isEmpty);
      expect(ledger.store('c', 100), isEmpty);
      ledger.heart('a');
      ledger.heart('a');

      // b and c have one read each; b entered first, so b leaves.
      expect(ledger.store('d', 100), ['b']);
      expect(ledger.contains('a'), isTrue);
      expect(ledger.contains('b'), isFalse);
      expect(ledger.length, 3);
    });

    test('a re-read clip outranks a fresh one', () {
      final ledger = AudioCacheLedger(maxEntries: 2);
      ledger.store('a', 10);
      ledger.store('b', 10);
      ledger.heart('a'); // a: 2 reads, b: 1
      expect(ledger.store('c', 10), ['b']);
      expect(ledger.contains('a'), isTrue);
    });

    test('byte ceiling evicts even under the entry count', () {
      final ledger = AudioCacheLedger(maxEntries: 100, maxBytes: 100);
      ledger.store('a', 60);
      expect(ledger.totalBytes, 60);
      expect(ledger.store('b', 60), ['a']);
      expect(ledger.totalBytes, 60);
      expect(ledger.length, 1);
    });

    test('survives a round trip through the index file', () {
      final ledger = AudioCacheLedger(maxEntries: 5);
      ledger.store('a', 100);
      ledger.store('b', 200);
      ledger.heart('a');

      final restored = AudioCacheLedger.fromJson(
        // ignore: avoid_dynamic_calls
        ledger.toJson(),
        maxEntries: 5,
      );
      expect(restored.length, 2);
      expect(restored['a']!.hits, 2);
      expect(restored['b']!.bytes, 200);
      // The next insert must get a sequence number beyond the restored ones.
      restored.store('c', 100);
      expect(restored['c']!.seq, greaterThan(restored['a']!.seq));
    });

    test('adopts files the index lost, then trims as usual', () {
      final ledger = AudioCacheLedger(maxEntries: 2);
      ledger.adopt('a', 10);
      ledger.adopt('b', 10);
      ledger.adopt('c', 10);
      // The store adopts every orphan and trims once, instead of re-scanning
      // the whole map after each file.
      expect(ledger.trim(), ['a']);
      expect(ledger.length, 2);
    });
  });

  group('native store', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('audio_cache_test');
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    test('round-trips a clip through the disk', () async {
      final store = NativeOnlineAudioStore(root: root);
      final bytes = _clip(1);
      await store.write('abc123', bytes);
      await store.flush();

      final file = File('${root.path}/online_audio/abc123.mp3');
      expect(await file.exists(), isTrue);
      expect(await file.length(), bytes.length);
      expect(File('${root.path}/online_audio/index.json').existsSync(), isTrue);

      expect(await store.read('abc123'), bytes);
      expect(await store.read('missing'), isNull);
    });

    test('eviction deletes the file, not just the row', () async {
      final store = NativeOnlineAudioStore(root: root, maxEntries: 2);
      await store.write('a', _clip(1));
      await store.write('b', _clip(2));
      await store.read('a'); // a: two reads, b: one
      await store.write('c', _clip(3));

      expect(store.length, 2);
      expect(File('${root.path}/online_audio/b.mp3').existsSync(), isFalse);
      expect(File('${root.path}/online_audio/a.mp3').existsSync(), isTrue);
      expect(File('${root.path}/online_audio/c.mp3').existsSync(), isTrue);
    });

    test('keeps the hit counts across a restart', () async {
      final store = NativeOnlineAudioStore(root: root, maxEntries: 2);
      await store.write('a', _clip(1));
      await store.read('a');
      await store.read('a'); // a: 3 reads, b: 1
      await store.write('b', _clip(2));
      await store.flush();

      final index = File('${root.path}/online_audio/index.json');
      expect(index.existsSync(), isTrue);
      expect(await index.length(), greaterThan(20));

      final reopened = NativeOnlineAudioStore(root: root, maxEntries: 2);
      await reopened.write('c', _clip(3));
      expect(File('${root.path}/online_audio/a.mp3').existsSync(), isTrue);
      expect(File('${root.path}/online_audio/b.mp3').existsSync(), isFalse);
    });

    test('a clip over the whole budget is refused', () async {
      final store = NativeOnlineAudioStore(root: root, maxBytes: 500);
      await store.write('big', _clip(1, 900));
      expect(store.length, 0);
      expect(File('${root.path}/online_audio/big.mp3').existsSync(), isFalse);
    });

    test('heals a crash between a clip write and the index', () async {
      final dir = Directory('${root.path}/online_audio');
      await dir.create(recursive: true);
      final orphan = File('${dir.path}/deadbeef.mp3');
      await orphan.writeAsBytes(_clip(9));

      final store = NativeOnlineAudioStore(root: root, maxEntries: 10);
      expect(await store.read('deadbeef'), _clip(9));
      await store.flush();

      // The adopted clip is in the index now, so a fresh store still sees it.
      final reopened = NativeOnlineAudioStore(root: root, maxEntries: 10);
      expect(await reopened.read('deadbeef'), _clip(9));
    });

    test('drops rows whose file vanished', () async {
      final store = NativeOnlineAudioStore(root: root, maxEntries: 10);
      await store.write('a', _clip(1));
      await store.write('b', _clip(2));
      await store.flush();
      await File('${root.path}/online_audio/a.mp3').delete();

      final reopened = NativeOnlineAudioStore(root: root, maxEntries: 10);
      expect(await reopened.read('a'), isNull);
      expect(await reopened.read('b'), _clip(2));
    });
  });

  group('cache', () {
    test('serves the second read from the queue instead of the network',
        () async {
      final store = _FakeStore();
      var fetches = 0;
      final cache = OnlineAudioCache(
        store: store,
        fetch: (engine, {required text, required accent, rate = 1.0, client}) async {
          fetches++;
          return _clip(fetches);
        },
      );
      final first = await cache.synthesize(SpeechEngine.edge,
          text: 'I just got back.', accent: 'us');
      final second = await cache.synthesize(SpeechEngine.edge,
          text: 'I just got back.', accent: 'us');
      expect(fetches, 1);
      expect(second, first);
      expect(store.writes, 1);
    });

    test('the same sentence in another voice is another clip', () async {
      final store = _FakeStore();
      var fetches = 0;
      final cache = OnlineAudioCache(
        store: store,
        fetch: (engine, {required text, required accent, rate = 1.0, client}) async {
          fetches++;
          return _clip(fetches);
        },
      );
      await cache.synthesize(SpeechEngine.edge,
          text: 'Good morning.', accent: 'us');
      await cache.synthesize(SpeechEngine.edge,
          text: 'Good morning.', accent: 'uk');
      expect(fetches, 2);
      expect(store.length, 2);
    });

    test('local engines never touch the queue', () async {
      final store = _FakeStore();
      var fetches = 0;
      final cache = OnlineAudioCache(
        store: store,
        fetch: (engine, {required text, required accent, rate = 1.0, client}) async {
          fetches++;
          return null;
        },
      );
      await cache.synthesize(SpeechEngine.kokoro, text: 'Hello', accent: 'us');
      await cache.synthesize(SpeechEngine.system, text: 'Hello', accent: 'us');
      expect(fetches, 2);
      expect(store.reads, 0);
      expect(store.writes, 0);
    });

    test('a sentence being fetched is not fetched twice', () async {
      final store = _FakeStore();
      var fetches = 0;
      final gate = Completer<void>();
      final cache = OnlineAudioCache(
        store: store,
        fetch: (engine, {required text, required accent, rate = 1.0, client}) async {
          fetches++;
          await gate.future;
          return _clip(7);
        },
      );
      final one = cache.synthesize(SpeechEngine.google,
          text: 'Let me try.', accent: 'us');
      final two = cache.synthesize(SpeechEngine.google,
          text: 'Let me try.', accent: 'us');
      gate.complete();
      expect(await one, await two);
      expect(fetches, 1);
    });

    test('a failing disk never costs the line', () async {
      var fetches = 0;
      final cache = OnlineAudioCache(
        store: _BrokenStore(),
        fetch: (engine, {required text, required accent, rate = 1.0, client}) async {
          fetches++;
          return _clip(fetches);
        },
      );
      final first = await cache.synthesize(SpeechEngine.edge,
          text: 'I just got back.', accent: 'us');
      expect(first, isNotNull);
      final second = await cache.synthesize(SpeechEngine.edge,
          text: 'I just got back.', accent: 'us');
      expect(second, isNotNull);
      expect(fetches, 2);
    });

    test('network failures are not cached', () async {
      final store = _FakeStore();
      var fetches = 0;
      final cache = OnlineAudioCache(
        store: store,
        fetch: (engine, {required text, required accent, rate = 1.0, client}) async {
          fetches++;
          return null;
        },
      );
      expect(await cache.synthesize(SpeechEngine.baidu, text: 'Hi', accent: 'us'),
          isNull);
      expect(await cache.synthesize(SpeechEngine.baidu, text: 'Hi', accent: 'us'),
          isNull);
      expect(fetches, 2);
      expect(store.writes, 0);
    });
  });
}
