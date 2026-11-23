import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'online_audio_cache_core.dart';
import 'online_audio_cache_store.dart';
import 'online_tts.dart';
import 'speech_engine.dart';

/// The online voices' answer cache: a sentence the app has read before is
/// served from disk instead of the network.
///
/// It exists for the repeat costs of this app rather than for one word: a
/// passage drill reads the same thirty lines dozens of times, the reader
/// prefetches each line again after a stop, and two windows share the engine.
/// Every such replay used to be a fresh request.
///
/// The queue, its key and the eviction rule live in
/// `online_audio_cache_core.dart`; this class is the lookup and the store.
class OnlineAudioCache {
  OnlineAudioCache({
    OnlineAudioStore? store,
    OnlineSynthesizer? fetch,
  })  : _store = store ?? createOnlineAudioStore(),
        _fetch = fetch ?? OnlineTts.synthesize;

  /// The process-wide cache; callers get this one so the index is loaded once.
  static final OnlineAudioCache instance = OnlineAudioCache();

  final OnlineAudioStore _store;
  final OnlineSynthesizer _fetch;

  /// Requests already in flight, keyed like the cache.
  ///
  /// The reader renders ahead ([EntrySpeechProvider.prefetchWindow]); pressing
  /// play again while a line is still being fetched would otherwise start a
  /// second identical request.
  final Map<String, Future<Uint8List?>> _pending = {};

  /// MP3 for [text], from the cache when possible, else from [engine].
  ///
  /// The signature is [OnlineSynthesizer]'s on purpose: the providers take any
  /// synthesizer, and the default is this method.
  Future<Uint8List?> synthesize(
    SpeechEngine engine, {
    required String text,
    required String accent,
    double rate = 1.0,
    http.Client? client,
  }) {
    final trimmed = text.trim();
    if (!engine.isOnline || trimmed.isEmpty) {
      return _fetch(engine,
          text: trimmed, accent: accent, rate: rate, client: client);
    }
    final key = onlineAudioKey(engine, text: trimmed, accent: accent, rate: rate);
    final pending = _pending[key];
    if (pending != null) return pending;
    final future = _load(
      engine,
      key,
      text: trimmed,
      accent: accent,
      rate: rate,
      client: client,
    );
    _pending[key] = future;
    return future.whenComplete(() => _pending.remove(key));
  }

  Future<Uint8List?> _load(
    SpeechEngine engine,
    String key, {
    required String text,
    required String accent,
    required double rate,
    http.Client? client,
  }) async {
    // A cache is a speed-up, never a dependency: a read-only directory, a full
    // disk or an unwritable index must not cost the reader the line.
    Uint8List? cached;
    try {
      cached = await _store.read(key);
    } catch (_) {
      cached = null;
    }
    if (cached != null && cached.isNotEmpty) return cached;

    final bytes =
        await _fetch(engine, text: text, accent: accent, rate: rate, client: client);
    if (bytes != null && bytes.isNotEmpty) {
      try {
        await _store.write(key, bytes);
      } catch (_) {
        // Same rule as above: the audio already exists, the queue can wait.
      }
    }
    return bytes;
  }

  /// Writes the index out now; the store also does this on a timer.
  Future<void> flush() => _store.flush();

  int get length => _store.length;
}
