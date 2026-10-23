import 'package:flutter_test/flutter_test.dart';
import 'package:local_dict/core/audio/kokoro_model.dart';
import 'package:local_dict/core/audio/kokoro_voice.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

const _files = KokoroModelFiles(
  model: 'tts-models/kokoro/model.onnx',
  voices: 'tts-models/kokoro/voices.bin',
  tokens: 'tts-models/kokoro/tokens.txt',
  dataDir: 'tts-models/kokoro/espeak-ng-data',
  folder: 'tts-models/kokoro',
);

void main() {
  test('the model runs on its documented defaults, nothing else', () {
    final config = kokoroConfigFor(_files);

    expect(config.model, _files.model);
    expect(config.voices, _files.voices);
    expect(config.tokens, _files.tokens);
    expect(config.dataDir, _files.dataDir);

    // The v1.x multi-lingual bundle needs a language; everything else stays at
    // the SDK default.
    const defaults = sherpa.OfflineTtsKokoroModelConfig();

    expect(config.lang, 'en',
        reason: 'the multi-lingual model refuses to load without it');
    expect(config.lexicon, defaults.lexicon);
    expect(config.dictDir, defaults.dictDir);
    expect(config.lengthScale, defaults.lengthScale,
        reason: 'speed belongs to the request, not to the model');
  });
}
