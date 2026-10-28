import 'dart:typed_data';

/// A word's audio, resolved but not yet played.
///
/// Resolving (reading the `.mdd`, downloading a clip) is the slow half of a
/// pronunciation; separating it lets the drill fill a queue ahead of time so the
/// gap between words is the gap the reader configured.
class PreparedPronunciation {
  const PreparedPronunciation({
    required this.word,
    this.path,
    this.bytes,
    this.url,
  });

  final String word;

  /// A playable file: an archive clip written to temp, or a cached download.
  final String? path;

  /// Raw audio for platforms that play bytes directly.
  final Uint8List? bytes;

  /// A streamed source (web: the backend's clip, or the online voice).
  final String? url;

  bool get hasAudio => path != null || bytes != null || url != null;
}
