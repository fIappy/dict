import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
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
  static int _writeSeq = 0;
  static final Map<String, Future<void>> _writeQueues = {};

  static Future<T> _serialized<T>(String name, Future<T> Function() action) {
    final prev = _writeQueues[name] ?? Future<void>.value();
    final completer = Completer<T>();
    late final Future<void> queued;
    queued = prev.catchError((_) {}).then((_) async {
      try {
        final result = await action();
        if (identical(_writeQueues[name], queued)) {
          unawaited(_writeQueues.remove(name));
        }
        completer.complete(result);
      } catch (e, s) {
        if (identical(_writeQueues[name], queued)) {
          unawaited(_writeQueues.remove(name));
        }
        completer.completeError(e, s);
      }
    });
    _writeQueues[name] = queued;
    return completer.future;
  }

  static Future<Directory?> _directory() async {
    // `dart:io` compiles for the web but throws at the first call: Platform and
    // Directory do not exist there. Check before touching either.
    if (kIsWeb) {
      _available = false;
      return null;
    }
    if (_available == false) return null;
    // The widget tests have no plugin host: a channel call there never
    // completes inside the fake async zone, and the library lives in the
    // mocked preferences anyway.
    try {
      if (Platform.environment['FLUTTER_TEST'] == 'true') {
        _available = false;
        return null;
      }
    } on UnsupportedError {
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

  static Future<String?> _read(String name) => _serialized(name, () async {
        final directory = await _directory();
        if (directory == null) return null;
        final path = '${directory.path}${Platform.pathSeparator}$name';
        try {
          final file = File(path);
          if (await file.exists()) {
            return await file.readAsString();
          }
          // Recover from `.bak` if a crash happened between moving target to
          // `.bak` and renaming the temporary file into place.
          final backup = File('$path.bak');
          if (await backup.exists()) {
            await backup.rename(path);
            return await file.readAsString();
          }
          return null;
        } catch (_) {
          return null;
        }
      });

  static Future<bool> _write(String name, String raw) =>
      _serialized(name, () async {
        final directory = await _directory();
        if (directory == null) return false;
        final path = '${directory.path}${Platform.pathSeparator}$name';
        final temporary = File(
          '$path.$pid.${DateTime.now().microsecondsSinceEpoch}.${_writeSeq++}.tmp',
        );
        try {
          // Write beside the target and swap under a per-file queue. The flush
          // puts the bytes on disk before the rename, and the previous file is
          // kept as `.bak` until the swap completes (or restored if it fails).
          await temporary.writeAsString(raw, flush: true);
          final target = File(path);
          final backup = File('$path.bak');
          if (await backup.exists()) await backup.delete();
          if (await target.exists()) await target.rename(backup.path);
          try {
            await temporary.rename(path);
          } catch (_) {
            if (!await target.exists() && await backup.exists()) {
              await backup.rename(path);
            }
            rethrow;
          }
          if (await backup.exists()) await backup.delete();
          return true;
        } catch (_) {
          try {
            if (await temporary.exists()) await temporary.delete();
          } catch (_) {}
          return false;
        }
      });

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
