import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:local_dict/core/audio/audio_manager.dart';
import 'package:local_dict/core/audio/piper_voice.dart';
import 'package:local_dict/providers/entry_speech_provider.dart';

/// Runs the real audio stack on this machine: the platform voice probe, the
/// Piper model lookup, and both playback paths. It answers "does the app think
/// it spoke?" — which is the difference between a code bug and a mixer problem.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the platform voice can speak a sentence', (tester) async {
    final audio = AudioManager();
    final label = await audio.sentenceVoiceLabel('us');
    // ignore: avoid_print
    print('SENTENCE VOICE: $label');
    expect(label, isNotNull, reason: 'no English voice found by the app');

    final ok = await audio.speakSentence(
      'This sentence is spoken by the app.',
      accent: 'us',
      rate: 1.0,
    );
    // ignore: avoid_print
    print('SPEAK SENTENCE RETURNED: $ok');
    expect(ok, isTrue, reason: 'the speech path reported failure');
  });

  testWidgets('the piper model state', (tester) async {
    final piper = PiperVoice();
    final ready = await piper.isReady('us');
    final label = await piper.label('us');
    // ignore: avoid_print
    print('PIPER us READY: $ready label: $label');
  });

  testWidgets('a selection goes through the provider', (tester) async {
    final speech = EntrySpeechProvider();
    await speech.speakText('Reading a selected definition line.',
        rate: 1.0, accent: 'us');
    // ignore: avoid_print
    print('PROVIDER isPlaying after speakText: ${speech.isPlaying}');
    expect(speech.isPlaying, isFalse);
    speech.dispose();
  });
}
