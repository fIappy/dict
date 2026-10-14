// Platform dispatch: the machine's own voices on native, none on the web.
export 'sentence_voice_web.dart' if (dart.library.io) 'sentence_voice_native.dart';
export 'voice_choice.dart';
