// Platform dispatch: sqflite on native targets, a JSON document store on the web.
export 'dictionaries_dao_web.dart'
    if (dart.library.io) 'dictionaries_dao_native.dart';
