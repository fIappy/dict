import 'dart:typed_data';

import 'online_audio_cache_core.dart';

/// The browser's queue: same policy, no files.
///
/// A page cannot reach the file system, and IndexedDB would add a dependency
/// for a cache the browser already keeps at the HTTP level — the clips survive
/// the tab through that cache, while the hit counts start over. The budget is
/// smaller because the bytes live in the tab's own memory.
class WebOnlineAudioStore implements OnlineAudioStore {
  WebOnlineAudioStore({int maxEntries = 1000, int maxBytes = 32 << 20})
      : _ledger = AudioCacheLedger(
          maxEntries: maxEntries,
          maxBytes: maxBytes,
        );

  final AudioCacheLedger _ledger;
  final Map<String, Uint8List> _clips = {};

  @override
  int get length => _ledger.length;

  @override
  Future<Uint8List?> read(String key) async {
    final clip = _clips[key];
    if (clip == null) {
      _ledger.remove(key);
      return null;
    }
    _ledger.heart(key);
    return clip;
  }

  @override
  Future<void> write(String key, Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > _ledger.maxBytes) return;
    for (final victim in _ledger.store(key, bytes.length)) {
      _clips.remove(victim);
    }
    // The ledger can drop the newcomer itself when the budget is too small to
    // hold it beside the clips that are already wanted more.
    if (_ledger.contains(key)) _clips[key] = bytes;
  }

  @override
  Future<void> flush() async {}
}

OnlineAudioStore createOnlineAudioStore() => WebOnlineAudioStore();
