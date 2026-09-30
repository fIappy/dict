import '../models/history_item.dart';
import 'web_store.dart';

/// Web implementation of the lookup history store.
class HistoryDao {
  static const String _key = 'web_history';
  static const int _maxItems = 200;

  Future<List<HistoryItem>> getRecentHistory({int limit = 50}) async {
    final rows = await WebStore.readList(_key);
    final items = rows.map((m) => HistoryItem.fromMap(m)).toList();
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (items.length > limit) {
      return items.sublist(0, limit);
    }
    return items;
  }

  Future<void> addHistory(HistoryItem item) async {
    final rows = await WebStore.readList(_key);
    final target = item.word.trim().toLowerCase();
    rows.removeWhere(
      (m) => (m['word'] as String? ?? '').toLowerCase() == target,
    );
    rows.add(item.toMap());

    // Sort newest first and bound the history length.
    rows.sort((a, b) {
      final av = a['created_at'] as int? ?? 0;
      final bv = b['created_at'] as int? ?? 0;
      return bv.compareTo(av);
    });
    final trimmed = rows.length > _maxItems
        ? rows.sublist(0, _maxItems)
        : rows;
    await WebStore.writeList(_key, trimmed);
  }

  Future<void> deleteHistoryItem(String id) async {
    final rows = await WebStore.readList(_key);
    rows.removeWhere((m) => m['id'] == id);
    await WebStore.writeList(_key, rows);
  }

  Future<void> clearHistory() async {
    await WebStore.writeList(_key, []);
  }
}
