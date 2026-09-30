import 'package:flutter/foundation.dart';

import '../api/dict_api_client.dart';
import '../models/dictionary_info.dart';

/// Web implementation of the dictionary registry.
///
/// The archive set is owned by the backend: it is discovered from the server's
/// dictionary directory, not from browser storage. Failures degrade to an empty
/// list so the rest of the app (IPA, alphabet, frequency) keeps working.
class DictionariesDao {
  final DictApiClient _api = DictApiClient();

  Future<List<DictionaryInfo>> getAll() async {
    try {
      final items = await _api.dictionaries();
      items.sort((a, b) {
        final byPriority = a.priority.compareTo(b.priority);
        return byPriority != 0 ? byPriority : a.createdAt.compareTo(b.createdAt);
      });
      return items;
    } catch (e) {
      debugPrint('Dictionary registry unavailable: $e');
      return const [];
    }
  }

  Future<List<DictionaryInfo>> getEnabled() async {
    final items = await getAll();
    return items.where((d) => d.isEnabled).toList();
  }

  Future<DictionaryInfo?> getById(String id) async {
    final items = await getAll();
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }

  /// Archives are added on the server; there is nothing to persist here.
  Future<void> insert(DictionaryInfo info) async {}

  Future<void> update(DictionaryInfo info) async {}

  Future<void> toggleEnabled(String id, bool isEnabled) async {
    await _api.setDictionaryEnabled(id, isEnabled);
  }

  /// Archives are removed by editing the server's dictionary directory.
  Future<void> delete(String id) async {}
}
