import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The 自定义 library — megabytes of passages — on the filesystem.
///
/// It used to live in `shared_preferences`, next to flags like the window frame
/// and the split position. That plugin rewrites its whole JSON document on
/// every `set*`, and its document held these megabytes: saving the window frame
/// after each drag therefore re-encoded and rewrote every stored passage. That
/// is ~300 ms of UI-isolate work per save, and it is what made resizing the
/// window stutter.
///
/// Files here, flags in preferences. Small captures the answer, the library
/// goes to its own JSON, so a flag write touches a few hundred bytes.
///
/// Everything falls back to preferences when the platform has no writable
/// support directory (the widget tests run without a plugin host): reads check
/// the files first and the old keys second, writes put the library in
/// preferences only when the file write failed.
class TextLibraryStore {
  static const String _textsFile = 'custom_texts.json';
  static const String _groupsFile = 'custom_groups.json';

  /// The keys the library had while it lived in preferences.
  static const String legacyTextsKey = 'custom_texts';
  static const String legacyGroupsKey = 'custom_groups';

  static bool? _available;

  static Future<Directory?> _directory() async {
    if (_available == false) return null;
    // The widget tests have no plugin host: a channel call there never
    // completes inside the fake async zone, and the library lives in the
    // mocked preferences anyway.
    if (Platform.environment['FLUTTER_TEST'] == 'true') {
      _available = false;
      return null;
    }
    try {
      final directory = await getApplicationSupportDirectory();
      await directory.create(recursive: true);
      _available = true;
      return directory;
    } catch (_) {
      _available = false;
      return null;
    }
  }

  static Future<String?> _read(String name) async {
    final directory = await _directory();
    if (directory == null) return null;
    try {
      final file = File('${directory.path}${Platform.pathSeparator}$name');
      if (!await file.exists()) return null;
      return await file.readAsString();
    } catch (_) {
      return null;
    }
  }

  static Future<bool> _write(String name, String raw) async {
    final directory = await _directory();
    if (directory == null) return false;
    final path = '${directory.path}${Platform.pathSeparator}$name';
    try {
      // Write beside the target and swap: a crash mid-write leaves the old
      // library intact instead of a truncated one.
      final temporary = File('$path.tmp');
      await temporary.writeAsString(raw, flush: false);
      final target = File(path);
      if (await target.exists()) await target.delete();
      await temporary.rename(path);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<String?> readTexts() => _read(_textsFile);

  static Future<String?> readGroups() => _read(_groupsFile);

  static Future<bool> writeTexts(String raw) => _write(_textsFile, raw);

  static Future<bool> writeGroups(String raw) => _write(_groupsFile, raw);

  /// Moves a library that still lives in preferences onto disk.
  ///
  /// Runs once per install; afterwards the two keys are gone and preferences
  /// are back to a few kilobytes.
  static Future<void> migrate(SharedPreferences prefs) async {
    final hasTexts = prefs.containsKey(legacyTextsKey);
    final hasGroups = prefs.containsKey(legacyGroupsKey);
    if (!hasTexts && !hasGroups) return;
    if (await _directory() == null) return;
    if (hasTexts) {
      final raw = prefs.getString(legacyTextsKey);
      if (raw != null && await writeTexts(raw)) await prefs.remove(legacyTextsKey);
    }
    if (hasGroups) {
      final raw = prefs.getString(legacyGroupsKey);
      if (raw != null && await writeGroups(raw)) {
        await prefs.remove(legacyGroupsKey);
      }
    }
  }
}
