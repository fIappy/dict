// Loading the ONNX Runtime beside the executable is a desktop concern; the
// browser build has no file system and no dynamic libraries.
export 'sherpa_runtime_web.dart'
    if (dart.library.io) 'sherpa_runtime_native.dart';
