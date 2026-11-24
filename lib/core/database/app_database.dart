import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class AppDatabase {
  static final AppDatabase _instance = AppDatabase._();
  factory AppDatabase() => _instance;
  AppDatabase._();

  Database? _db;
  Future<Database>? _opening;

  /// Cached as a future, not a completed value: three providers ask for the
  /// database during startup, and assigning `_db` only after the await let all
  /// three run `openDatabase` on the same file.
  Future<Database> get database {
    final open = _db;
    if (open != null) return Future<Database>.value(open);
    final existing = _opening;
    if (existing != null) return existing;
    late final Future<Database> opening;
    opening = _initDatabase().then(
      (db) {
        if (identical(_opening, opening)) {
          _db = db;
        }
        return db;
      },
      onError: (Object error, StackTrace stack) {
        if (identical(_opening, opening)) {
          _opening = null;
        }
        Error.throwWithStackTrace(error, stack);
      },
    );
    _opening = opening;
    return opening;
  }

  Future<Database> _initDatabase() async {
    final isTest = Platform.environment['FLUTTER_TEST'] == 'true';
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final String dbPath;
    if (isTest) {
      dbPath = inMemoryDatabasePath;
    } else {
      // App data lives in the app support folder. Documents is not guaranteed to
      // exist or be writable — on Windows it can be redirected to OneDrive or
      // locked down by policy, where `createSync` fails with "path not found"
      // and every provider that touches the registry dies on startup.
      final supportDir = await getApplicationSupportDirectory();
      final dbDir = Directory(p.join(supportDir.path, 'local_dict'));
      if (!dbDir.existsSync()) {
        dbDir.createSync(recursive: true);
      }
      dbPath = p.join(dbDir.path, 'dict_app.db');
      await _adoptLegacyDatabase(dbPath);
    }

    return await openDatabase(
      dbPath,
      version: 1,
      onConfigure: (db) async {
        // Two windows share this file; WAL + a busy timeout is what stops them
        // from failing with SQLITE_BUSY the moment both write at once.
        if (!isTest) {
          // rawQuery, not execute: Android's execSQL refuses a statement that
          // returns a row, and PRAGMA journal_mode answers with the mode it
          // settled on. That refusal aborted every history/favorite read at
          // startup on the phone.
          await db.rawQuery('PRAGMA journal_mode = WAL');
        }
        await db.rawQuery('PRAGMA busy_timeout = 5000');
        await db.rawQuery('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE dictionaries (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            mdx_path TEXT NOT NULL,
            mdd_path TEXT,
            css_path TEXT,
            is_enabled INTEGER NOT NULL DEFAULT 1,
            priority INTEGER NOT NULL DEFAULT 0,
            entry_count INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE favorite_groups (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            description TEXT,
            color INTEGER NOT NULL DEFAULT 4282337717,
            icon TEXT,
            sort_order INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE favorites (
            id TEXT PRIMARY KEY,
            word TEXT NOT NULL,
            group_id TEXT NOT NULL,
            phonetic TEXT,
            definition_snippet TEXT,
            examples_snippet TEXT,
            note TEXT,
            dict_source TEXT,
            tags TEXT,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            FOREIGN KEY (group_id) REFERENCES favorite_groups(id) ON DELETE CASCADE
          )
        ''');

        await db.execute('''
          CREATE TABLE history (
            id TEXT PRIMARY KEY,
            word TEXT NOT NULL,
            dict_source TEXT,
            phonetic TEXT,
            created_at INTEGER NOT NULL
          )
        ''');

        await db.execute('CREATE INDEX idx_favorites_word ON favorites(word)');
        await db.execute('CREATE INDEX idx_favorites_group ON favorites(group_id)');
        await db.execute('CREATE INDEX idx_history_created ON history(created_at DESC)');

        // Seed default favorite groups
        final now = DateTime.now().millisecondsSinceEpoch;
        await db.insert('favorite_groups', {
          'id': 'default',
          'name': '默认生词本',
          'description': '查词时随手收藏的词汇',
          'color': 0xFF3F51B5,
          'sort_order': 0,
          'created_at': now,
        });
        await db.insert('favorite_groups', {
          'id': 'cet_core',
          'name': '四六级重点',
          'description': '大学英语四六级核心考点词',
          'color': 0xFF2E7D32,
          'sort_order': 1,
          'created_at': now + 1,
        });
        await db.insert('favorite_groups', {
          'id': 'gre_ielts',
          'name': 'GRE / 雅思托福',
          'description': '留学出国与高级学术词汇',
          'color': 0xFFEF6C00,
          'sort_order': 2,
          'created_at': now + 2,
        });
        await db.insert('favorite_groups', {
          'id': 'review',
          'name': '重点复习',
          'description': '易错易混需要反复强化的词汇',
          'color': 0xFFC2185B,
          'sort_order': 3,
          'created_at': now + 3,
        });
      },
    );
  }

  /// Earlier versions kept the database under Documents; bring that file along
  /// once so favorites, history and the dictionary registry are not lost.
  static Future<void> _adoptLegacyDatabase(String dbPath) async {
    if (File(dbPath).existsSync()) return;

    final File legacy;
    try {
      legacy = File(p.join(
        (await getApplicationDocumentsDirectory()).path,
        'local_dict',
        'dict_app.db',
      ));
    } on Exception {
      return; // No readable Documents folder: nothing to adopt.
    }
    if (!legacy.existsSync()) return;

    try {
      legacy.renameSync(dbPath);
    } on FileSystemException {
      try {
        legacy.copySync(dbPath);
      } on FileSystemException catch (e) {
        debugPrint('Could not bring the previous database to $dbPath: $e');
      }
    }
  }

  Future<void> close() async {
    final pending = _opening;
    _opening = null;
    Database? db = _db;
    if (db == null && pending != null) {
      try {
        db = await pending;
      } catch (_) {}
    }
    _db = null;
    if (db != null) {
      await db.close();
    }
  }
}
