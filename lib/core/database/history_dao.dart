// Platform dispatch: sqflite on native targets, a JSON document store on the web.
export 'history_dao_web.dart' if (dart.library.io) 'history_dao_native.dart';
