import '../models/history_item.dart';
import 'app_database.dart';

class HistoryDao {
  final AppDatabase _appDb = AppDatabase();

  Future<List<HistoryItem>> getRecentHistory({int limit = 50}) async {
    final db = await _appDb.database;
    final maps = await db.query(
      'history',
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return maps.map((m) => HistoryItem.fromMap(m)).toList();
  }

  Future<void> addHistory(HistoryItem item) async {
    final db = await _appDb.database;
    // Remove if already exists so it jumps to the top
    await db.delete(
      'history',
      where: 'LOWER(word) = ?',
      whereArgs: [item.word.trim().toLowerCase()],
    );

    await db.insert('history', item.toMap());

    // Keep history bounded to 200 items
    await db.execute('''
      DELETE FROM history WHERE id NOT IN (
        SELECT id FROM history ORDER BY created_at DESC LIMIT 200
      )
    ''');
  }

  Future<void> deleteHistoryItem(String id) async {
    final db = await _appDb.database;
    await db.delete(
      'history',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> clearHistory() async {
    final db = await _appDb.database;
    await db.delete('history');
  }
}
