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

  /// Speaks a whole sentence with the prosody of connected speech.
  ///
  /// Recorded words played back to back keep each word's citation form — its own
  /// final fall and its own pause — which is not how a person says
  /// "one thousand two hundred and thirty-four". Platforms with a usable speech
  /// voice therefore speak the sentence in one go; returning false means the
  /// caller falls back to the recorded words ([NumberSpeaker] does exactly that).
  Future<bool> speakSentence(
    String sentence, {
    String accent = 'us',
    double rate = 1.0,
  });

  /// Which voice [speakSentence] will use, for the UI to show; null when the
  /// platform has none (the recorded-word path is in use).
  Future<String?> sentenceVoiceLabel(String accent);

  /// Sets the output level (0–1) for everything this player sounds from now on.
  ///
  /// Sticky rather than per-clip: the reader sets it once in the settings panel,
  /// and every line after that is read at that level.
  Future<void> setVolume(double volume);

  /// Silences whatever is playing.
  Future<void> stop();
}
