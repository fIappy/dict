import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// JSON document store backed by SharedPreferences (localStorage on web).
/// Used by the web build in place of the sqflite database.
class WebStore {
  const WebStore._();

  static Future<List<Map<String, dynamic>>> readList(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
    try {
      final decoded = json.decode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (_) {
      // Corrupt payload: treat as empty.
    }
    return <Map<String, dynamic>>[];
  }

  static Future<void> writeList(
    String key,
    List<Map<String, dynamic>> items,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, json.encode(items));
  }
}
