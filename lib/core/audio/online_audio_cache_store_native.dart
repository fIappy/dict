import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'online_audio_cache_core.dart';

/// Clip files plus their index under the app's own storage.
///
/// `index.json` is rewritten on a short debounce rather than on every line:
/// playing a passage touches the index once per sentence, and a synchronous
/// file write per sentence would put disk latency in the middle of playback.
/// A crash between a clip write and the next flush is healed on the next start
/// by adopting the files the index does not know.
class NativeOnlineAudioStore implements OnlineAudioStore {
  NativeOnlineAudioStore({
    Directory? root,
    int maxEntries = 1000,
    int maxBytes = 96 << 20,
  })  : _rootOverride = root,
        _maxEntries = maxEntries,
        _maxBytes = maxBytes;

  final Directory? _rootOverride;
  final int _maxEntries;
  final int _maxBytes;

  Directory? _dir;
  late AudioCacheLedger _ledger = AudioCacheLedger(
    maxEntries: _maxEntries,
    maxBytes: _maxBytes,
  );
  Future<void>? _ready;

  /// Every file operation runs after the previous one: a passage's prefetch
  /// renders several lines at once, and two of them must not interleave a
  /// `readAsBytes` with an eviction.
  Future<void> _io = Future<void>.value();

  Timer? _flushTimer;

  @override
  int get length => _ledger.length;

  @override
  Future<Uint8List?> read(String key) => _serialized(() async {
        await _ensureReady();
        final file = _fileFor(key);
        if (!await file.exists()) {
          if (_ledger.remove(key)) _scheduleFlush();
          return null;
        }
        final bytes = await file.readAsBytes();
        if (bytes.isEmpty) {
          await _delete(key);
          return null;
        }
        // Only reachable if an index write failed while a clip did not: the
        // clip is real, so take it into the queue rather than leak it.
        if (!_ledger.contains(key)) _ledger.adopt(key, bytes.length);
        _ledger.heart(key);
        _scheduleFlush();
        return bytes;
      });

  @override
  Future<void> write(String key, Uint8List bytes) => _serialized(() async {
        await _ensureReady();
        // One clip that cannot fit the whole budget is not worth evicting
        // everything else for.
        if (bytes.isEmpty || bytes.length > _maxBytes) return;
        final victims = _ledger.store(key, bytes.length);
        if (!_ledger.contains(key)) return; // Evicted on arrival: over budget.
        await _fileFor(key).writeAsBytes(bytes, flush: true);
        for (final victim in victims) {
          try {
            await _fileFor(victim).delete();
          } on FileSystemException {
            // Already gone, or locked by a player: the index has forgotten it,
            // and the next start adopts and trims it.
          }
        }
        _scheduleFlush();
      });

  @override
  Future<void> flush() => _serialized(() async {
        await _ensureReady();
        _flushTimer?.cancel();
        _flushTimer = null;
        await _writeIndexNow();
      });

  Future<void> dispose() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    if (_dir != null) await _serialized(_writeIndexNow);
  }

  File _fileFor(String key) => File(p.join(_dir!.path, '$key.mp3'));

  Future<void> _delete(String key) async {
    try {
      await _fileFor(key).delete();
    } on FileSystemException {
      // Missing is the state we wanted.
    }
    _ledger.remove(key);
    _scheduleFlush();
  }

  Future<void> _ensureReady() => _ready ??= _load();

  Future<void> _load() async {
    final base = _rootOverride ?? await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'online_audio'));
    await dir.create(recursive: true);
    _dir = dir;

    final index = File(p.join(dir.path, 'index.json'));
    if (await index.exists()) {
      try {
        _ledger = AudioCacheLedger.fromJson(
          jsonDecode(await index.readAsString()),
          maxEntries: _maxEntries,
          maxBytes: _maxBytes,
        );
      } on FormatException {
        _ledger = AudioCacheLedger(
          maxEntries: _maxEntries,
          maxBytes: _maxBytes,
        );
      }
    }

    final present = <String>{};
    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.endsWith('.mp3')) continue;
      final key = p.basenameWithoutExtension(entity.path);
      final length = await entity.length();
      if (length <= 0) {
        try {
          await entity.delete();
        } on FileSystemException {
          // Left for the next start.
        }
        continue;
      }
      present.add(key);
      if (!_ledger.contains(key)) _ledger.adopt(key, length);
    }

    for (final key in _ledger.keys.toList()) {
      if (!present.contains(key)) _ledger.remove(key);
    }
    for (final victim in _ledger.trim()) {
      try {
        await File(p.join(dir.path, '$victim.mp3')).delete();
      } on FileSystemException {
        // Next start adopts it again and trims once more.
      }
    }
    await _writeIndexNow();
  }

  void _scheduleFlush() {
    _flushTimer?.cancel();
    _flushTimer = Timer(const Duration(milliseconds: 600), () {
      _flushTimer = null;
      unawaited(_serialized(_writeIndexNow));
    });
  }

  /// Runs inside [_serialized]; never call it from a serialized body.
  Future<void> _writeIndexNow() async {
    final dir = _dir;
    if (dir == null) return;
    final file = File(p.join(dir.path, 'index.json'));
    final temp = File('${file.path}.tmp');
    try {
      await temp.writeAsString(jsonEncode(_ledger.toJson()), flush: true);
      await temp.rename(file.path);
    } on FileSystemException {
      // A rename can lose to a reader holding the old file open. The clips stay
      // usable without an index; the next start adopts them.
      try {
        await file.writeAsString(jsonEncode(_ledger.toJson()), flush: true);
      } on FileSystemException {
        // Nothing more to do here.
      }
    }
  }

  Future<T> _serialized<T>(Future<T> Function() body) {
    final next = _io.then((_) => body());
    _io = next.then((_) {}, onError: (_) {});
    return next;
  }
}

OnlineAudioStore createOnlineAudioStore() => NativeOnlineAudioStore();
