import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/database/favorites_dao.dart';
import '../core/models/favorite_group.dart';
import '../core/models/favorite_item.dart';
import '../core/ui/ui_memory.dart';

class FavoritesProvider extends ChangeNotifier {
  final FavoritesDao _dao = FavoritesDao();

  List<FavoriteGroup> _groups = [];
  List<FavoriteItem> _favorites = [];
  String? _selectedGroupId;
  String _filterQuery = '';
  bool _isLoading = false;

  List<FavoriteGroup> get groups => _groups;
  List<FavoriteItem> get favorites => _favorites;
  String? get selectedGroupId => _selectedGroupId;
  String get filterQuery => _filterQuery;
  bool get isLoading => _isLoading;

  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();
    await refreshGroups();
    // Reopen the group that was on screen; one deleted meanwhile falls back to
    // 全部 rather than to a filter that can never match.
    final remembered = await UiMemory.readString(UiMemory.favoriteGroup);
    if (remembered != null &&
        remembered.isNotEmpty &&
        _groups.any((group) => group.id == remembered)) {
      _selectedGroupId = remembered;
    }
    await refreshFavorites();
    _isLoading = false;
    notifyListeners();
  }

  /// Version of the shipped vocabulary library already merged.
  static const String _seedVersionKey = 'favorites_seed_version';
  static const String _seedAsset = 'assets/seed/favorites.json';

  /// Merges the vocabulary that ships with the app.
  ///
  /// Runs when the library's `version` is newer than the one already merged:
  /// groups and words that are missing are copied into the database, and a word
  /// the reader already has keeps its own note/group. `python
  /// tool/publish_library.py` writes that file from the live database.
  Future<void> ensureSeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final merged = prefs.getInt(_seedVersionKey) ?? 0;
    try {
      final raw = await rootBundle.loadString(_seedAsset);
      final data = jsonDecode(raw);
      if (data is! Map) return;
      final version = (data['version'] as num?)?.toInt() ?? 0;
      if (version <= merged) return;

      final groups = data['groups'];
      if (groups is List) {
        final known = {for (final group in await _dao.getAllGroups()) group.id};
        for (final entry in groups) {
          if (entry is! Map) continue;
          final group = FavoriteGroup.fromMap(entry.cast<String, dynamic>());
          if (!known.add(group.id)) continue;
          await _dao.insertGroup(group);
        }
      }

      final items = data['items'];
      if (items is List) {
        final known = {
          for (final favorite in await _dao.getFavorites())
            favorite.word.toLowerCase(),
        };
        for (final entry in items) {
          if (entry is! Map) continue;
          final item = FavoriteItem.fromMap(entry.cast<String, dynamic>());
          if (!known.add(item.word.toLowerCase())) continue;
          await _dao.addFavorite(item);
        }
      }

      await prefs.setInt(_seedVersionKey, version);
      await refreshGroups();
      await refreshFavorites();
    } catch (e) {
      debugPrint('favorites seed import failed: $e');
    }
  }

  Future<void> refreshGroups() async {
    _groups = await _dao.getAllGroups();
    notifyListeners();
  }

  Future<void> refreshFavorites() async {
    _favorites = await _dao.getFavorites(
      groupId: _selectedGroupId,
      query: _filterQuery,
    );
    notifyListeners();
  }

  void selectGroup(String? groupId) {
    _selectedGroupId = groupId;
    UiMemory.writeString(UiMemory.favoriteGroup, groupId ?? '');
    refreshFavorites();
  }

  void setFilterQuery(String query) {
    _filterQuery = query;
    refreshFavorites();
  }

  Future<FavoriteItem?> getFavoriteForWord(String word) async {
    return await _dao.getFavoriteByWord(word);
  }

  Future<bool> isWordFavorited(String word) async {
    return await _dao.isWordFavorited(word);
  }

  Future<void> addOrUpdateFavorite({
    required String word,
    required String groupId,
    String? phonetic,
    String? definitionSnippet,
    String? examplesSnippet,
    String? note,
    String? dictSource,
    List<String> tags = const [],
  }) async {
    final existing = await _dao.getFavoriteByWord(word);
    final now = DateTime.now();

    if (existing != null) {
      final updated = existing.copyWith(
        groupId: groupId,
        note: note,
        phonetic: phonetic ?? existing.phonetic,
        definitionSnippet: definitionSnippet ?? existing.definitionSnippet,
        examplesSnippet: examplesSnippet ?? existing.examplesSnippet,
        updatedAt: now,
      );
      await _dao.updateFavorite(updated);
    } else {
      final item = FavoriteItem(
        id: 'fav_${DateTime.now().millisecondsSinceEpoch}',
        word: word,
        groupId: groupId,
        phonetic: phonetic,
        definitionSnippet: definitionSnippet,
        examplesSnippet: examplesSnippet,
        note: note,
        dictSource: dictSource,
        tags: tags,
        createdAt: now,
        updatedAt: now,
      );
      await _dao.addFavorite(item);
    }

    await refreshGroups();
    await refreshFavorites();
  }

  Future<void> removeFavorite(String word) async {
    await _dao.removeFavoriteByWord(word);
    await refreshGroups();
    await refreshFavorites();
  }

  Future<FavoriteGroup> createGroup(String name, int color, {String? description}) async {
    final group = FavoriteGroup(
      id: 'grp_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      color: color,
      description: description,
      sortOrder: _groups.length,
      createdAt: DateTime.now(),
    );
    await _dao.insertGroup(group);
    await refreshGroups();
    return group;
  }

  Future<void> updateGroup(FavoriteGroup group) async {
    await _dao.updateGroup(group);
    await refreshGroups();
  }

  Future<void> deleteGroup(String groupId) async {
    await _dao.deleteGroup(groupId);
    if (_selectedGroupId == groupId) {
      _selectedGroupId = null;
      UiMemory.writeString(UiMemory.favoriteGroup, '');
    }
    await refreshGroups();
    await refreshFavorites();
  }
}
