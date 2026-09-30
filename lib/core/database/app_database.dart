import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class AppDatabase {
  static final AppDatabase _instance = AppDatabase._();
  factory AppDatabase() => _instance;
  AppDatabase._();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDatabase();
    return _db!;
  }

  Future<Database> _initDatabase() async {
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final docsDir = await getApplicationDocumentsDirectory();
    final dbDir = Directory(p.join(docsDir.path, 'local_dict'));
    if (!dbDir.existsSync()) {
      dbDir.createSync(recursive: true);
    }
    final dbPath = p.join(dbDir.path, 'dict_app.db');

    return await openDatabase(
      dbPath,
      version: 1,
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

  Future<void> close() async {
    if (_db != null) {
      await _db!.close();
      _db = null;
    }
  }
}
