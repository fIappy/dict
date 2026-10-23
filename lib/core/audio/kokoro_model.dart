/// The four pieces sherpa-onnx needs to speak with Kokoro.
///
/// Kokoro is an 82M-parameter model; the quantised English build runs at 24 kHz
/// and is read by the same library on Windows, Android and (as WebAssembly) in
/// the browser, so all three platforms use one voice.
class KokoroModelFiles {
  const KokoroModelFiles({
    required this.model,
    required this.voices,
    required this.tokens,
    required this.dataDir,
    required this.folder,
  });

  /// The `.onnx` model.
  final String model;

  /// `voices.bin`, the speaker embeddings.
  final String voices;

  /// `tokens.txt`.
  final String tokens;

  /// `espeak-ng-data/`, the grapheme-to-phoneme data.
  final String dataDir;

  /// The model's folder, for messages.
  final String folder;

  @override
  String toString() => 'KokoroModelFiles($folder)';
}

/// Where the model lives. One voice serves every accent:
///
///     tts-models/kokoro/model.onnx
///                      voices.bin
///                      tokens.txt
///                      espeak-ng-data/
///
/// The names are fixed rather than discovered because the browser cannot list a
/// directory: every platform addresses the same paths.
const String kokoroModelRoot = 'tts-models';
const String kokoroModelFolder = 'kokoro';
const String kokoroModelFile = 'model.onnx';
const String kokoroVoicesFile = 'voices.bin';
const String kokoroTokensFile = 'tokens.txt';
const String kokoroDataFolder = 'espeak-ng-data';

/// The file list the browser fetches: WebAssembly cannot list a directory.
/// `tool/fetch_kokoro_model.py` writes it.
const String kokoroManifest = 'files.txt';

/// Which Kokoro speaker reads. 0 is `af_heart`, the model's default voice.
const int kokoroSpeakerId = 0;

/// The accent label Kokoro reports in the UI. It speaks one English voice, so
/// both accents share it; the flag keeps the two call sites honest.
String kokoroAccentLabel(String accent) => accent == 'uk' ? '英音' : '美音';
