import 'voice_choice.dart';

/// The browser build speaks the module's recorded words; no local voice is wired
/// up. Browser `speechSynthesis` could fill this in later — until then every
/// lookup answers "none" and the recordings are used, which keeps the app working
/// offline exactly as before.
Future<List<SentenceVoice>> systemVoices() async => const [];

Future<SentenceVoice?> chosenSentenceVoice(String accent) async => null;

/// Nothing to speak with; the caller plays the recordings.
Future<String?> synthesizeWithVoice(String text, SentenceVoice voice, {double rate = 1.0}) async => null;

/// Nothing to speak with.
Future<bool> speakWithSapi(String text, SentenceVoice voice, {double rate = 1.0}) async => false;

void cancelSystemVoice() {}
