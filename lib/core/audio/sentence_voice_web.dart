import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'voice_choice.dart';

/// The browser's own speech synthesis: `speechSynthesis` hands the sentence to
/// the operating system's voices, so "twenty-four" is read as one number instead
/// of the module playing the `twenty` and `four` recordings back to back.
///
/// Chrome fills `getVoices()` asynchronously (it fires `voiceschanged`), so the
/// first probe waits for it. A browser with no voice at all — or one that
/// refuses to speak without a user gesture — answers "none"/false and the module
/// keeps using its recordings, which is what it always did.
List<SentenceVoice>? _voices;
Future<List<SentenceVoice>>? _loading;

/// Long enough for any number card, short enough that a stuck engine cannot
/// freeze the drill.
const Duration _completionTimeout = Duration(seconds: 45);

/// How long to wait for the voice list before giving up on it.
const Duration _probeTimeout = Duration(seconds: 2);

Future<List<SentenceVoice>> systemVoices() {
  if (_voices != null) return Future.value(_voices!);
  return _loading ??= _loadVoices();
}

Future<List<SentenceVoice>> _loadVoices() async {
  try {
    final synth = web.window.speechSynthesis;
    var list = synth.getVoices().toDart;
    if (list.isEmpty) {
      await _voicesChanged(synth);
      list = synth.getVoices().toDart;
    }
    final found = <SentenceVoice>[];
    for (final voice in list) {
      final language = voice.lang.trim();
      if (language.isEmpty) continue;
      found.add(SentenceVoice(
        name: voice.name,
        language: language,
        engine: VoiceEngine.browser,
        // Cloud-backed voices ("Google US English") stop working offline, and
        // this module is meant to keep working with the network unplugged.
        offline: voice.localService,
      ));
    }
    return _voices = found;
  } catch (e) {
    // No speech support in this browser: recordings take over.
    return _voices = const [];
  }
}

/// Resolves on `voiceschanged`, or after [_probeTimeout] if it never fires.
Future<void> _voicesChanged(web.SpeechSynthesis synth) {
  final done = Completer<void>();
  synth.onvoiceschanged = ((web.Event _) {
    if (!done.isCompleted) done.complete();
  }).toJS;
  return done.future.timeout(_probeTimeout, onTimeout: () {});
}

Future<SentenceVoice?> chosenSentenceVoice(String accent) async =>
    chooseSentenceVoice(await systemVoices(), accent);

/// Speaks [text] as one utterance and completes when the browser says it has
/// finished, so the drill keeps its cadence.
///
/// Returns false when nothing was spoken: no voice, or the browser refused the
/// utterance (Chrome ignores `speak` on a page without a user gesture). The
/// caller then falls back to the recordings rather than staying silent.
Future<bool> speakWithSystemVoice(
  String text,
  SentenceVoice voice, {
  double rate = 1.0,
  double volume = 1.0,
}) async {
  final synth = web.window.speechSynthesis;
  try {
    synth.cancel();
    final utterance = web.SpeechSynthesisUtterance(text)
      ..lang = voice.language
      ..rate = rate
      ..volume = volume.clamp(0.0, 1.0);

    for (final candidate in synth.getVoices().toDart) {
      if (candidate.name == voice.name) {
        utterance.voice = candidate;
        break;
      }
    }

    final started = Completer<bool>();
    final finished = Completer<bool>();
    utterance.onstart = ((web.Event _) {
      if (!started.isCompleted) started.complete(true);
    }).toJS;
    utterance.onend = ((web.Event _) {
      if (!started.isCompleted) started.complete(true);
      if (!finished.isCompleted) finished.complete(true);
    }).toJS;
    utterance.onerror = ((web.Event _) {
      if (!started.isCompleted) started.complete(false);
      if (!finished.isCompleted) finished.complete(false);
    }).toJS;

    synth.speak(utterance);

    // "Did it get spoken" is the start; the end only paces the drill.
    final spoke = await started.future.timeout(
      const Duration(seconds: 3),
      onTimeout: () => false,
    );
    if (!spoke) {
      synth.cancel();
      return false;
    }
    await finished.future.timeout(_completionTimeout, onTimeout: () => true);
    return true;
  } catch (e) {
    return false;
  }
}

/// The browser speaks for itself; there is no file to hand back.
Future<String?> synthesizeWithVoice(
  String text,
  SentenceVoice voice, {
  double rate = 1.0,
}) async =>
    null;

void cancelSystemVoice() {
  try {
    web.window.speechSynthesis.cancel();
  } catch (_) {
    // Nothing to cancel.
  }
}
