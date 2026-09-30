// Platform dispatch: `dart:io` random-access files on native targets,
// an unsupported stub on the web.
export 'mdd_reader_web.dart' if (dart.library.io) 'mdd_reader_native.dart';
