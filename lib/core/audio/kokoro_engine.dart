// Where the actual inference runs. Native platforms use a long-lived worker
// isolate (ONNX blocks the thread it runs on, and blocking the UI thread is what
// made every click during playback feel slow); the browser has no isolates and
// runs it inline.
export 'kokoro_engine_web.dart'
    if (dart.library.io) 'kokoro_engine_native.dart';
