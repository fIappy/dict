import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Resolves the base URL of the local dictionary backend.
///
/// Precedence: `?api=` query parameter (persisted) > stored preference >
/// compile-time `--dart-define=DICT_API_BASE=...` > page origin on web >
/// `http://127.0.0.1:8080`.
///
/// The page-origin fallback lets a single-origin deployment (nginx serving the
/// bundle and proxying `/api/`) work with no configuration at all.
class ApiConfig {
  ApiConfig._();

  static const String _prefsKey = 'dict_api_base';

  /// Empty by default so the page-origin fallback can apply.
  static const String compileTimeDefault = String.fromEnvironment(
    'DICT_API_BASE',
    defaultValue: '',
  );

  static String? _baseUrl;
  static bool _resolved = false;
  static Future<void>? _resolving;

  static String get baseUrl => _baseUrl ??= _fallback();

  /// Joins the configured base with an API path, preserving any base subpath
  /// when hosted behind a reverse-proxy prefix.
  static Uri endpoint(String path, [Map<String, String>? query]) {
    final normalized = _normalize(baseUrl) ?? _fallback();
    final base = Uri.parse(normalized.endsWith('/') ? normalized : '$normalized/');
    final relative = path.replaceFirst(RegExp(r'^/+'), '');
    final joined = base.resolve(relative);
    return query == null ? joined : joined.replace(queryParameters: query);
  }

  /// Picks up a runtime override from the URL, then from stored settings.
  static Future<void> resolve() {
    if (_resolved) return Future<void>.value();
    return _resolving ??= _resolveImpl().whenComplete(() {
      _resolving = null;
    });
  }

  static Future<void> _resolveImpl() async {
    if (kIsWeb) {
      final override = Uri.base.queryParameters['api'];
      if (override != null && override.trim().isNotEmpty) {
        final safe = _normalize(override.trim());
        if (safe != null) {
          // Session-scoped override only: do not permanently overwrite stored
          // backend configuration from a link query parameter.
          _baseUrl = safe;
          _resolved = true;
          return;
        }
      }
    }

    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_prefsKey);
    if (stored != null && stored.trim().isNotEmpty) {
      final safe = _normalize(stored.trim());
      if (safe != null) {
        _baseUrl = safe;
        _resolved = true;
        return;
      }
    }

    _baseUrl = _fallback();
    _resolved = true;
  }

  static Future<void> setBaseUrl(String value) async {
    final safe = _normalize(value.trim());
    if (safe == null) {
      throw ArgumentError.value(value, 'value', 'Expected http or https URL');
    }
    _baseUrl = safe;
    _resolved = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, safe);
  }

  static Future<void> resetBaseUrl() async {
    _baseUrl = _fallback();
    _resolved = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }

  static String _fallback() {
    if (compileTimeDefault.isNotEmpty) {
      final safe = _normalize(compileTimeDefault);
      if (safe != null) return safe;
    }
    if (kIsWeb) {
      final origin = Uri.base.origin;
      if (origin.isNotEmpty && origin != 'null') return origin;
    }
    return 'http://127.0.0.1:8080';
  }

  static String? _normalize(String value) {
    var v = value.trim();
    while (v.endsWith('/')) {
      v = v.substring(0, v.length - 1);
    }
    final uri = Uri.tryParse(v);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    return v;
  }
}
