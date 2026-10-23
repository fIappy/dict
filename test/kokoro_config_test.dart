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

    // Everything else must be the SDK default. `lang` is the one that broke
    // "four" (F1 989 Hz against 565 Hz); `lexicon` and `dictDir` swap the front
    // end the same way, so they are pinned too.
    const defaults = sherpa.OfflineTtsKokoroModelConfig();

    expect(config.lang, defaults.lang,
        reason: 'a lang override switches the front end and mispronounces words '
            'the model reads correctly by default');
    expect(config.lexicon, defaults.lexicon);
    expect(config.dictDir, defaults.dictDir);
    expect(config.lengthScale, defaults.lengthScale,
        reason: 'speed belongs to the request, not to the model');
  });
}
