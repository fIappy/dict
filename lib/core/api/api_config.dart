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

  static String get baseUrl => _baseUrl ??= _fallback();

  /// Joins the configured base with an API path.
  static Uri endpoint(String path, [Map<String, String>? query]) {
    final base = Uri.parse(baseUrl.endsWith('/') ? baseUrl : '$baseUrl/');
    return base.replace(
      path: path.replaceFirst(RegExp(r'^/'), ''),
      queryParameters: query,
    );
  }

  /// Picks up a runtime override from the URL, then from stored settings.
  static Future<void> resolve() async {
    if (_resolved) return;
    _resolved = true;

    if (kIsWeb) {
      final override = Uri.base.queryParameters['api'];
      if (override != null && override.trim().isNotEmpty) {
        _baseUrl = _normalize(override.trim());
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefsKey, _baseUrl!);
        return;
      }
    }

    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_prefsKey);
    if (stored != null && stored.trim().isNotEmpty) {
      _baseUrl = _normalize(stored.trim());
      return;
    }

    _baseUrl = _fallback();
  }

  static Future<void> setBaseUrl(String value) async {
    _baseUrl = _normalize(value.trim());
    _resolved = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, _baseUrl!);
  }

  static String _fallback() {
    if (compileTimeDefault.isNotEmpty) return _normalize(compileTimeDefault);
    if (kIsWeb) {
      final origin = Uri.base.origin;
      if (origin.isNotEmpty && origin != 'null') return origin;
    }
    return 'http://127.0.0.1:8080';
  }

  static String _normalize(String value) {
    var v = value;
    while (v.endsWith('/')) {
      v = v.substring(0, v.length - 1);
    }
    return v;
  }
}
