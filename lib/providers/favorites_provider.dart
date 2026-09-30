import 'package:flutter/material.dart';
import '../core/database/favorites_dao.dart';
import '../core/models/favorite_group.dart';
import '../core/models/favorite_item.dart';

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
    await refreshFavorites();
    _isLoading = false;
    notifyListeners();
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
    }
    await refreshGroups();
    await refreshFavorites();
  }
}
