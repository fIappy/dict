import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'voice_choice.dart';

/// Android's own speech synthesis (`android.speech.tts.TextToSpeech`), reached
/// through the channel `MainActivity` sets up.
///
/// The engine is the device's default one — the same voice the system's own
/// accessibility read-aloud uses — so a number card is read as one utterance
/// instead of playing the module's word recordings back to back. Voices are the
/// engine's installed list; every one of them is on-device unless it reports
/// itself as needing the network.
const MethodChannel _channel = MethodChannel('local_dict/sentence_voice');

/// How long to wait for the engine to answer. An engine that never reports back
/// (some OEM builds go quiet after a while) must not freeze the drill: the
/// utterance was handed over, so the call answers "spoken" and the module moves
/// on rather than reading the sentence a second time as recordings.
const Duration _completionTimeout = Duration(seconds: 45);

/// An engine that never finishes initialising must not leave the probe hanging
/// either — the module then simply keeps using its recordings.
const Duration _probeTimeout = Duration(seconds: 5);

List<SentenceVoice>? _voices;

Future<List<SentenceVoice>> systemVoices() async {
  if (_voices != null) return _voices!;
  final found = <SentenceVoice>[];
  try {
    final probed = await _channel
        .invokeListMethod<Object?>('voices')
        .timeout(_probeTimeout, onTimeout: () => null);
    final raw = probed ?? const <Object?>[];
    for (final entry in raw) {
      final map = (entry as Map).cast<String, Object?>();
      final language = (map['language'] as String? ?? '').trim();
      if (language.isEmpty) continue;
      found.add(SentenceVoice(
        name: (map['name'] as String? ?? '').trim(),
        language: language,
        engine: VoiceEngine.androidTts,
        offline: map['offline'] as bool? ?? true,
      ));
    }
  } on PlatformException catch (e) {
    debugPrint('Android voice probe failed: $e');
  } on MissingPluginException {
    // Not the Android build (or the engine is gone): no voices, recordings take
    // over, which is exactly what the module did before this bridge existed.
  }
  return _voices = found;
}

Future<SentenceVoice?> chosenSentenceVoice(String accent) async =>
    chooseSentenceVoice(await systemVoices(), accent);

/// Speaks [text] as one utterance and completes when it has finished sounding,
/// so the drill keeps its pacing. Returns false when the engine refused it (or
/// could not be reached), and then the recorded words are used instead.
Future<bool> speakWithSystemVoice(
  String text,
  SentenceVoice voice, {
  double rate = 1.0,
}) async {
  try {
    final spoken = await _channel
        .invokeMethod<bool>('speak', <String, Object?>{
          'text': text,
          'voice': voice.name,
          'language': voice.language,
          'rate': rate,
        })
        .timeout(_completionTimeout, onTimeout: () => true);
    return spoken ?? false;
  } on PlatformException catch (e) {
    debugPrint('Android speech failed: $e');
    return false;
  } on MissingPluginException {
    return false;
  }
}

/// Android renders straight to the speaker; there is no file to hand back.
Future<String?> synthesizeWithVoice(
  String text,
  SentenceVoice voice, {
  double rate = 1.0,
}) async =>
    null;

void cancelSystemVoice() {
  _channel.invokeMethod<void>('stop').catchError((Object e) {
    debugPrint('Stopping the Android voice failed: $e');
  });
}
