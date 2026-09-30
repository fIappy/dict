import '../models/favorite_group.dart';
import '../models/favorite_item.dart';
import 'web_store.dart';

/// Web implementation of the favourites store.
/// Groups and items are persisted as JSON documents in SharedPreferences.
class FavoritesDao {
  static const String _groupsKey = 'web_favorite_groups';
  static const String _itemsKey = 'web_favorites';

  // --- Groups ---

  Future<void> _seedIfEmpty() async {
    final groups = await WebStore.readList(_groupsKey);
    if (groups.isNotEmpty) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    await WebStore.writeList(_groupsKey, [
      {
        'id': 'default',
        'name': '默认生词本',
        'description': '查词时随手收藏的词汇',
        'color': 0xFF3F51B5,
        'sort_order': 0,
        'created_at': now,
      },
      {
        'id': 'cet_core',
        'name': '四六级重点',
        'description': '大学英语四六级核心考点词',
        'color': 0xFF2E7D32,
        'sort_order': 1,
        'created_at': now + 1,
      },
      {
        'id': 'gre_ielts',
        'name': 'GRE / 雅思托福',
        'description': '留学出国与高级学术词汇',
        'color': 0xFFEF6C00,
        'sort_order': 2,
        'created_at': now + 2,
      },
      {
        'id': 'review',
        'name': '重点复习',
        'description': '易错易混需要反复强化的词汇',
        'color': 0xFFC2185B,
        'sort_order': 3,
        'created_at': now + 3,
      },
    ]);
  }

  Future<List<FavoriteGroup>> getAllGroups() async {
    await _seedIfEmpty();
    final groupRows = await WebStore.readList(_groupsKey);
    final itemRows = await WebStore.readList(_itemsKey);

    final counts = <String, int>{};
    for (final row in itemRows) {
      final gid = row['group_id'] as String? ?? 'default';
      counts[gid] = (counts[gid] ?? 0) + 1;
    }

    final groups = groupRows
        .map((m) => FavoriteGroup.fromMap(m, wordCount: counts[m['id']] ?? 0))
        .toList();
    groups.sort((a, b) {
      final byOrder = a.sortOrder.compareTo(b.sortOrder);
      return byOrder != 0 ? byOrder : a.createdAt.compareTo(b.createdAt);
    });
    return groups;
  }

  Future<FavoriteGroup?> getGroupById(String id) async {
    final groups = await getAllGroups();
    for (final g in groups) {
      if (g.id == id) return g;
    }
    return null;
  }

  Future<void> insertGroup(FavoriteGroup group) async {
    final rows = await WebStore.readList(_groupsKey);
    rows.removeWhere((m) => m['id'] == group.id);
    rows.add({...group.toMap(), 'word_count': group.wordCount});
    await WebStore.writeList(_groupsKey, rows);
  }

  Future<void> updateGroup(FavoriteGroup group) async {
    final rows = await WebStore.readList(_groupsKey);
    final index = rows.indexWhere((m) => m['id'] == group.id);
    final payload = {...group.toMap(), 'word_count': group.wordCount};
    if (index == -1) {
      rows.add(payload);
    } else {
      rows[index] = payload;
    }
    await WebStore.writeList(_groupsKey, rows);
  }

  Future<void> deleteGroup(String id) async {
    if (id == 'default') return; // Cannot delete default group
    final rows = await WebStore.readList(_groupsKey);
    rows.removeWhere((m) => m['id'] == id);
    await WebStore.writeList(_groupsKey, rows);

    // Reassign orphaned words to the default group.
    final items = await WebStore.readList(_itemsKey);
    final now = DateTime.now().millisecondsSinceEpoch;
    for (var i = 0; i < items.length; i++) {
      if (items[i]['group_id'] == id) {
        items[i] = {...items[i], 'group_id': 'default', 'updated_at': now};
      }
    }
    await WebStore.writeList(_itemsKey, items);
  }

  // --- Items ---

  Future<List<FavoriteItem>> getFavorites({
    String? groupId,
    String? query,
  }) async {
    final rows = await WebStore.readList(_itemsKey);
    final q = query?.trim().toLowerCase();

    final items = rows.where((row) {
      if (groupId != null && groupId.isNotEmpty && row['group_id'] != groupId) {
        return false;
      }
      if (q != null && q.isNotEmpty) {
        final word = (row['word'] as String? ?? '').toLowerCase();
        final def = (row['definition_snippet'] as String? ?? '').toLowerCase();
        final note = (row['note'] as String? ?? '').toLowerCase();
        if (!word.contains(q) && !def.contains(q) && !note.contains(q)) {
          return false;
        }
      }
      return true;
    }).map((m) => FavoriteItem.fromMap(m)).toList();

    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  Future<FavoriteItem?> getFavoriteByWord(String word) async {
    final target = word.trim().toLowerCase();
    final rows = await WebStore.readList(_itemsKey);
    for (final row in rows) {
      if ((row['word'] as String? ?? '').toLowerCase() == target) {
        return FavoriteItem.fromMap(row);
      }
    }
    return null;
  }

  Future<bool> isWordFavorited(String word) async {
    return await getFavoriteByWord(word) != null;
  }

  Future<void> addFavorite(FavoriteItem item) async {
    final rows = await WebStore.readList(_itemsKey);
    rows.removeWhere((m) => m['id'] == item.id);
    await WebStore.writeList(_itemsKey, [...rows, item.toMap()]);
  }

  Future<void> updateFavorite(FavoriteItem item) async {
    final rows = await WebStore.readList(_itemsKey);
    final index = rows.indexWhere((m) => m['id'] == item.id);
    if (index == -1) {
      rows.add(item.toMap());
    } else {
      rows[index] = item.toMap();
    }
    await WebStore.writeList(_itemsKey, rows);
  }

  Future<void> removeFavorite(String id) async {
    final rows = await WebStore.readList(_itemsKey);
    rows.removeWhere((m) => m['id'] == id);
    await WebStore.writeList(_itemsKey, rows);
  }

  Future<void> removeFavoriteByWord(String word) async {
    final target = word.trim().toLowerCase();
    final rows = await WebStore.readList(_itemsKey);
    rows.removeWhere(
      (m) => (m['word'] as String? ?? '').toLowerCase() == target,
    );
    await WebStore.writeList(_itemsKey, rows);
  }

  Future<void> moveWordToGroup(String word, String newGroupId) async {
    final target = word.trim().toLowerCase();
    final rows = await WebStore.readList(_itemsKey);
    final now = DateTime.now().millisecondsSinceEpoch;
    for (var i = 0; i < rows.length; i++) {
      if ((rows[i]['word'] as String? ?? '').toLowerCase() == target) {
        rows[i] = {
          ...rows[i],
          'group_id': newGroupId,
          'updated_at': now,
        };
      }
    }
    await WebStore.writeList(_itemsKey, rows);
  }
}
