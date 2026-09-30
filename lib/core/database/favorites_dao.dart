// Platform dispatch: sqflite on native targets, a JSON document store on the web.
export 'favorites_dao_web.dart'
    if (dart.library.io) 'favorites_dao_native.dart';
