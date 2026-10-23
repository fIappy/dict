import 'package:flutter_test/flutter_test.dart';
import 'package:local_dict/core/audio/kokoro_model.dart';
import 'package:local_dict/core/audio/kokoro_voice.dart';

const _files = KokoroModelFiles(
  model: 'tts-models/kokoro/model.onnx',
  voices: 'tts-models/kokoro/voices.bin',
  tokens: 'tts-models/kokoro/tokens.txt',
  dataDir: 'tts-models/kokoro/espeak-ng-data',
  folder: 'tts-models/kokoro',
);

void main() {
  test('the model is configured without a language override', () {
    final config = kokoroConfigFor(_files);

    expect(config.lang, isEmpty,
        reason: 'lang="en" reads "four" as "fa" (F1 989 Hz against 565 Hz) — '
            'the espeak-ng default is the pronunciation the model was trained on');
    expect(config.model, _files.model);
    expect(config.voices, _files.voices);
    expect(config.tokens, _files.tokens);
    expect(config.dataDir, _files.dataDir);
  });
}
