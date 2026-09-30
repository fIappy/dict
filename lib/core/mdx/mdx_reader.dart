// Platform dispatch: `dart:io` random-access files on native targets,
// an unsupported stub on the web.
export 'mdx_reader_web.dart' if (dart.library.io) 'mdx_reader_native.dart';
