import 'dart:io';

import 'sentence_voice_android.dart' as android;
import 'sentence_voice_windows.dart' as windows;
import 'voice_choice.dart';

// Platform dispatch for the native targets. Dart cannot tell Windows from
// Android at compile time (`dart.library.io` is true for both), so the choice is
// made here at runtime: Windows talks to OneCore/SAPI through a PowerShell
// helper, Android to its own TextToSpeech engine.

/// The voices the host offers. Anything else native answers "none" and the
/// module falls back to its recordings.
Future<List<SentenceVoice>> systemVoices() =>
    Platform.isAndroid ? android.systemVoices() : windows.systemVoices();

Future<SentenceVoice?> chosenSentenceVoice(String accent) async =>
    chooseSentenceVoice(await systemVoices(), accent);

/// Speaks [text] as one utterance, completing when it has finished sounding.
/// Returns false when the host has no usable voice; the caller then plays the
/// recorded words.
Future<bool> speakWithSystemVoice(
  String text,
  SentenceVoice voice, {
  double rate = 1.0,
  double volume = 1.0,
}) =>
    Platform.isAndroid
        ? android.speakWithSystemVoice(text, voice, rate: rate, volume: volume)
        : windows.speakWithSystemVoice(text, voice, rate: rate, volume: volume);

/// Renders [text] to a wav file, for the engines that cannot speak on demand.
/// Android's engine speaks directly, so it has nothing to render here.
Future<String?> synthesizeWithVoice(
  String text,
  SentenceVoice voice, {
  double rate = 1.0,
}) =>
    Platform.isAndroid
        ? android.synthesizeWithVoice(text, voice, rate: rate)
        : windows.synthesizeWithVoice(text, voice, rate: rate);

void cancelSystemVoice() {
  if (Platform.isAndroid) {
    android.cancelSystemVoice();
  } else {
    windows.cancelSystemVoice();
  }
}
