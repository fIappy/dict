import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/favorite_group.dart';
import '../models/favorite_item.dart';
import 'app_database.dart';

class FavoritesDao {
  final AppDatabase _appDb = AppDatabase();

  // --- Favorite Groups ---

  Future<List<FavoriteGroup>> getAllGroups() async {
    final db = await _appDb.database;
    final results = await db.rawQuery('''
      SELECT g.*, COUNT(f.id) AS word_count
      FROM favorite_groups g
      LEFT JOIN favorites f ON g.id = f.group_id
      GROUP BY g.id
      ORDER BY g.sort_order ASC, g.created_at ASC
    ''');
    return results.map((m) => FavoriteGroup.fromMap(m)).toList();
  }

  Future<FavoriteGroup?> getGroupById(String id) async {
    final db = await _appDb.database;
    final results = await db.rawQuery('''
      SELECT g.*, COUNT(f.id) AS word_count
      FROM favorite_groups g
      LEFT JOIN favorites f ON g.id = f.group_id
      WHERE g.id = ?
      GROUP BY g.id
      LIMIT 1
    ''', [id]);
    if (results.isEmpty) return null;
    return FavoriteGroup.fromMap(results.first);
  }

  Future<void> insertGroup(FavoriteGroup group) async {
    final db = await _appDb.database;
    await db.insert(
      'favorite_groups',
      group.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateGroup(FavoriteGroup group) async {
    final db = await _appDb.database;
    await db.update(
      'favorite_groups',
      group.toMap(),
      where: 'id = ?',
      whereArgs: [group.id],
    );
  }

  Future<void> deleteGroup(String id) async {
    if (id == 'default') return; // Cannot delete default group
    final db = await _appDb.database;
    await db.transaction((txn) async {
      // Reassign words in this group to 'default' group
      await txn.update(
        'favorites',
        {'group_id': 'default'},
        where: 'group_id = ?',
        whereArgs: [id],
      );
      await txn.delete(
        'favorite_groups',
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  // --- Favorite Items ---

  Future<List<FavoriteItem>> getFavorites({String? groupId, String? query}) async {
    final db = await _appDb.database;
    String whereClause = '';
    final whereArgs = <dynamic>[];

    if (groupId != null && groupId.isNotEmpty) {
      whereClause = 'group_id = ?';
      whereArgs.add(groupId);
    }

    if (query != null && query.trim().isNotEmpty) {
      final q = '%${query.trim().toLowerCase()}%';
      if (whereClause.isNotEmpty) {
        whereClause += ' AND (LOWER(word) LIKE ? OR LOWER(definition_snippet) LIKE ? OR LOWER(note) LIKE ?)';
      } else {
        whereClause = '(LOWER(word) LIKE ? OR LOWER(definition_snippet) LIKE ? OR LOWER(note) LIKE ?)';
      }
      whereArgs.addAll([q, q, q]);
    }

    final maps = await db.query(
      'favorites',
      where: whereClause.isNotEmpty ? whereClause : null,
      whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
      orderBy: 'created_at DESC',
    );
    return maps.map((m) => FavoriteItem.fromMap(m)).toList();
  }

  Future<FavoriteItem?> getFavoriteByWord(String word) async {
    final db = await _appDb.database;
    final maps = await db.query(
      'favorites',
      where: 'LOWER(word) = ?',
      whereArgs: [word.trim().toLowerCase()],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return FavoriteItem.fromMap(maps.first);
  }

  Future<bool> isWordFavorited(String word) async {
    final item = await getFavoriteByWord(word);
    return item != null;
  }

  Future<void> addFavorite(FavoriteItem item) async {
    final db = await _appDb.database;
    await db.insert(
      'favorites',
      item.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateFavorite(FavoriteItem item) async {
    final db = await _appDb.database;
    await db.update(
      'favorites',
      item.toMap(),
      where: 'id = ?',
      whereArgs: [item.id],
    );
  }

  Future<void> removeFavorite(String id) async {
    final db = await _appDb.database;
    await db.delete(
      'favorites',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> removeFavoriteByWord(String word) async {
    final db = await _appDb.database;
    await db.delete(
      'favorites',
      where: 'LOWER(word) = ?',
      whereArgs: [word.trim().toLowerCase()],
    );
  }

  Future<void> moveWordToGroup(String word, String newGroupId) async {
    final db = await _appDb.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.update(
      'favorites',
      {
        'group_id': newGroupId,
        'updated_at': now,
      },
      where: 'LOWER(word) = ?',
      whereArgs: [word.trim().toLowerCase()],
    );
  }
}
