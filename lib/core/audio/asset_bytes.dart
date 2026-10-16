import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

/// The bytes of one bundled asset, read once and kept.
///
/// The number module splices whole sentences out of the same handful of clips,
/// so a drill that plays a hundred numbers re-reads the same twenty files a
/// hundred times; the cache is bounded by that vocabulary, not by the drill
/// length.
final Map<String, Uint8List> _cache = {};

/// Bytes of `assets/[assetPath]`, or null when the asset is not in the bundle.
///
/// A missing clip is not an error: the caller says the number without that word,
/// exactly as it does when a word has no clip at all.
Future<Uint8List?> loadAssetBytes(String assetPath) async {
  final cached = _cache[assetPath];
  if (cached != null) return cached;
  try {
    final data = await rootBundle.load('assets/$assetPath');
    final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    return _cache[assetPath] = bytes;
  } catch (_) {
    return null;
  }
}

/// Forgets everything [loadAssetBytes] cached; the asset bundle can change
/// between tests.
void forgetAssetBytes() => _cache.clear();
