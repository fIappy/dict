import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/lexeme_entry.dart';
import '../models/search_result.dart';
import 'coca_sqlite_store.dart';

const MethodChannel _bundledAssets = MethodChannel('local_dict/bundled_models');

/// Desktop/mobile 53,925-word COCA AI learning corpus lookup service.
class CocaLexiconService {
  static final CocaLexiconService _instance = CocaLexiconService._();
  factory CocaLexiconService() => _instance;

  CocaLexiconService._([this._explicitDbPath]);

  /// Isolated instance pointing at an explicit `coca_learn.db` path (for tests).
  factory CocaLexiconService.forPath(String dbPath) =>
      CocaLexiconService._(dbPath);

  final String? _explicitDbPath;
  CocaSqliteStore? _store;
  Future<void>? _initializing;
  String? _databasePath;
  String? _initError;
  int _entryCount = 0;

  bool get isReady => _store != null;
  int get entryCount => _entryCount;
  String? get databasePath => _databasePath;
  String? get initError => _initError;
  String get libraryName => CocaSqliteStore.libraryName;

  Future<void> initialize() {
    if (_store != null) return Future<void>.value();
    return _initializing ??= _doInitialize().whenComplete(() {
      _initializing = null;
    });
  }

  Future<void> _doInitialize() async {
    // Widget tests wrap startup in FakeAsync, where opening an external 145 MB
    // database over FFI isolate channels can stall frames; explicit `forPath`
    // instances opt in deliberately.
    if (_explicitDbPath == null &&
        Platform.environment['FLUTTER_TEST'] == 'true') {
      return;
    }

    final path = await _resolveDatabasePath();
    if (path == null) {
      _initError = '未找到 coca_learn.db';
      return;
    }

    try {
      final Database db;
      if (Platform.isWindows || Platform.isLinux) {
        sqfliteFfiInit();
        db = await databaseFactoryFfi.openDatabase(
          path,
          options: OpenDatabaseOptions(readOnly: true),
        );
      } else {
        db = await sqflite.openReadOnlyDatabase(path);
      }
      final store = CocaSqliteStore(db);
      final count = await store.countEntries();
      _store = store;
      _databasePath = path;
      _entryCount = count;
      _initError = null;
    } catch (e) {
      _initError = e.toString();
    }
  }

  Future<String?> _resolveDatabasePath() async {
    final explicit = _explicitDbPath?.trim();
    if (explicit != null && explicit.isNotEmpty) {
      final f = File(explicit);
      if (f.existsSync()) return f.absolute.path;
      return null;
    }

    final candidates = <String>[];
    final envPath = Platform.environment['COCA_DB_PATH']?.trim();
    if (envPath != null && envPath.isNotEmpty) {
      candidates.add(envPath);
    }

    try {
      final exeDir = File(Platform.resolvedExecutable).parent;
      candidates.add(p.join(exeDir.path, 'coca_learn.db'));
      candidates.add(p.join(exeDir.path, 'data', 'coca_learn.db'));
    } catch (_) {}

    try {
      final supportDir = await getApplicationSupportDirectory();
      candidates.add(p.join(supportDir.path, 'local_dict', 'coca_learn.db'));
    } catch (_) {}

    void addAncestorProbes(Directory start) {
      Directory cur = start;
      for (var i = 0; i < 6; i++) {
        candidates.add(p.join(cur.path, 'content', 'coca-ai', 'pack', 'coca_learn.db'));
        candidates.add(p.join(cur.path, 'coca_learn.db'));
        final parent = cur.parent;
        if (parent.path == cur.path) break;
        cur = parent;
      }
    }

    addAncestorProbes(Directory.current);
    try {
      addAncestorProbes(File(Platform.resolvedExecutable).parent);
    } catch (_) {}

    for (final candidate in candidates) {
      final file = File(candidate);
      if (file.existsSync() && file.lengthSync() > 0) {
        return file.absolute.path;
      }
    }

    // Android carries the database inside the APK (Gradle copies it when
    // content/coca-ai exists). Nothing on disk means this is the first launch,
    // so ask the platform to unpack it once and probe again.
    if (Platform.isAndroid) {
      try {
        final installed =
            await _bundledAssets.invokeMethod<bool>('installLexicon');
        if (installed == true) {
          final dir = await getApplicationSupportDirectory();
          final file = File(p.join(dir.path, 'local_dict', 'coca_learn.db'));
          if (file.existsSync() && file.lengthSync() > 0) {
            return file.absolute.path;
          }
        }
      } on PlatformException {
        // An older APK without the asset: the caller reports the missing
        // database, which is the honest state.
      }
    }
    return null;
  }

  Future<LexemeEntry?> lookup(String word) async {
    if (_store == null) await initialize();
    final store = _store;
    if (store == null) return null;
    return store.lookup(word);
  }

  Future<List<SearchResult>> search(String query, {int limit = 60}) async {
    if (_store == null) await initialize();
    final store = _store;
    if (store == null) return const [];
    return store.search(query, limit: limit);
  }

  Future<void> close() async {
    final store = _store;
    _store = null;
    _databasePath = null;
    _entryCount = 0;
    if (store != null) {
      await store.close();
    }
  }
}
