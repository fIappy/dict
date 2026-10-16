/// The three pieces sherpa-onnx needs to speak with a Piper voice.
///
/// Piper is a small VITS text-to-speech model; the same model files are read by
/// the native build (Windows, Android) and by the WebAssembly build in the
/// browser, which is what makes all three say a number with one voice.
class PiperModelFiles {
  const PiperModelFiles({
    required this.model,
    required this.tokens,
    required this.dataDir,
    required this.folder,
  });

  /// The `.onnx` model.
  final String model;

  /// `tokens.txt`.
  final String tokens;

  /// `espeak-ng-data/`, the grapheme-to-phoneme data Piper needs.
  final String dataDir;

  /// The accent's folder, for messages ("已安装：…").
  final String folder;

  @override
  String toString() => 'PiperModelFiles($folder)';
}

/// Folder the models live in, one folder per accent inside it:
///
///     tts-models/piper/us/model.onnx   + tokens.txt + espeak-ng-data/
///     tts-models/piper/uk/model.onnx   + tokens.txt + espeak-ng-data/
///
/// The names are fixed rather than discovered because the browser cannot list a
/// directory: every platform addresses the same paths.
const String piperModelRoot = 'tts-models';
const String piperModelFolder = 'piper';
const String piperModelFile = 'model.onnx';
const String piperTokensFile = 'tokens.txt';
const String piperDataFolder = 'espeak-ng-data';

/// Lists every file of an accent folder, one relative path per line.
///
/// The browser build needs it to know what to fetch: WebAssembly cannot list a
/// directory. `tool/fetch_piper_models.py` writes it.
const String piperManifest = 'files.txt';

/// `uk` and `us` are the accents the module speaks; anything else falls back to
/// whichever of the two is installed.
String piperAccentFolder(String accent) => accent == 'uk' ? 'uk' : 'us';

/// The accents the module speaks, best first.
const List<String> accents = ['uk', 'us'];
