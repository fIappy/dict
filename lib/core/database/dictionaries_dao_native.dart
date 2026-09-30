import 'package:sqflite/sqflite.dart';
import '../models/dictionary_info.dart';
import 'app_database.dart';

class DictionariesDao {
  final AppDatabase _appDb = AppDatabase();

  Future<List<DictionaryInfo>> getAll() async {
    final db = await _appDb.database;
    final maps = await db.query(
      'dictionaries',
      orderBy: 'priority ASC, created_at ASC',
    );
    return maps.map((m) => DictionaryInfo.fromMap(m)).toList();
  }

  Future<List<DictionaryInfo>> getEnabled() async {
    final db = await _appDb.database;
    final maps = await db.query(
      'dictionaries',
      where: 'is_enabled = 1',
      orderBy: 'priority ASC, created_at ASC',
    );
    return maps.map((m) => DictionaryInfo.fromMap(m)).toList();
  }

  Future<DictionaryInfo?> getById(String id) async {
    final db = await _appDb.database;
    final maps = await db.query(
      'dictionaries',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return DictionaryInfo.fromMap(maps.first);
  }

  Future<void> insert(DictionaryInfo info) async {
    final db = await _appDb.database;
    await db.insert(
      'dictionaries',
      info.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> update(DictionaryInfo info) async {
    final db = await _appDb.database;
    await db.update(
      'dictionaries',
      info.toMap(),
      where: 'id = ?',
      whereArgs: [info.id],
    );
  }

  Future<void> toggleEnabled(String id, bool isEnabled) async {
    final db = await _appDb.database;
    await db.update(
      'dictionaries',
      {'is_enabled': isEnabled ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> delete(String id) async {
    final db = await _appDb.database;
    await db.delete(
      'dictionaries',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
