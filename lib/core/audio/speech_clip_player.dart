import 'dart:typed_data';

/// The single audio operation the number module needs from [AudioManager]:
/// play one bundled clip and complete when it has finished sounding.
///
/// Kept as an interface so [NumberSpeaker] can be driven by a recorder in tests —
/// the word order, the phone-group pauses and the interval between numbers are
/// logic worth asserting, and none of it needs a sound card.
abstract class SpeechClipPlayer {
  /// Plays [assetPath] (an `assets/`-relative path) to completion.
  Future<void> playSpeechClip(String assetPath, {double rate = 1.0});

  /// Plays one in-memory WAV buffer to completion.
  ///
  /// The engines that build a sentence themselves — splicing the recorded words,
  /// or the bundled Piper voice — hand their audio over here instead of writing
  /// it to a file first, so nothing touches the filesystem on any platform.
  /// Answers whether the clip actually sounded — a silent player must let the
  /// caller fall back to another engine instead of leaving dead air.
  Future<bool> playAudioBytes(Uint8List bytes, {double rate = 1.0});

  /// Silences whatever is playing.
  Future<void> stop();
}
