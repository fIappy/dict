// Platform dispatch: filesystem-backed MDict loading on native targets,
// a no-op service on the web.
export 'dictionary_service_web.dart'
    if (dart.library.io) 'dictionary_service_native.dart';
