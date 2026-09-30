// Platform dispatch: native playback with `.mdd` extraction and OS TTS,
// streaming playback on the web.
export 'audio_manager_web.dart' if (dart.library.io) 'audio_manager_native.dart';
