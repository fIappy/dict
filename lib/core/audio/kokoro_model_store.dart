// Where the Kokoro model is looked for: real folders on Windows and Android,
// HTTP paths in the browser. Both implementations expose the same functions, so
// the engine above them does not know which one it got.
export 'kokoro_model_store_web.dart'
    if (dart.library.io) 'kokoro_model_store_native.dart';
export 'kokoro_model.dart';
