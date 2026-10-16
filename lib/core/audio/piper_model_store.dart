// Where the Piper voice models are looked for: real folders on Windows and
// Android, HTTP paths in the browser. Both implementations expose the same
// functions, so the engine above them does not know which one it got.
export 'piper_model_store_web.dart'
    if (dart.library.io) 'piper_model_store_native.dart';
export 'piper_model.dart';
