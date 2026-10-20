import 'package:flutter/foundation.dart';

import '../core/themes/theme_service.dart';

/// State of the 主题 module: which scene is open and what the search box holds.
///
/// Nothing here is persisted — the scene list is meant to be browsed, and coming
/// back to the top-level list on restart is the sane default.
class ThemesProvider extends ChangeNotifier {
  /// Scenes longer than this are paged; shorter ones render in one go.
  static const int pageWordThreshold = 500;

  /// Words per page for scenes above [pageWordThreshold]. 通用高频 holds ~9.7k
  /// words, and handing all of them to a `Wrap` on open is a visible stall.
  static const int pageSize = 300;

  final ThemeService _service = ThemeService();

  bool _isLoading = true;
  String? _sceneId;
  String _query = '';
  int _page = 0;

  bool get isLoading => _isLoading;
  String get query => _query;
  String get source => _service.source;
  int get sceneCount => _service.scenes.length;
  int get totalWords => _service.totalWords;
  List<ThemeScene> get scenes => _service.scenes;

  ThemeScene? get selectedScene {
    final id = _sceneId;
    if (id == null) return null;
    for (final scene in _service.scenes) {
      if (scene.id == id) return scene;
    }
    return null;
  }

  /// The scenes as the list shows them: filtered by the search box when one is
  /// open, so a word can be found without knowing which scene holds it.
  List<ThemeScene> get visibleScenes {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return _service.scenes;
    return [
      for (final scene in _service.scenes)
        if (scene.label.toLowerCase().contains(query) ||
            scene.hint.toLowerCase().contains(query) ||
            scene.words.any((word) => word.contains(query)))
          scene,
    ];
  }

  /// The open scene's facets with the words the search box keeps, dropping
  /// facets that end up empty. Not paged — [visibleGroups] is the paged view.
  List<ThemeGroup> get _filteredGroups {
    final scene = selectedScene;
    if (scene == null) return const [];
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return scene.groups;
    return [
      for (final group in scene.groups)
        if (group.words.any((word) => word.contains(query)))
          ThemeGroup(
            id: group.id,
            label: group.label,
            words: [for (final word in group.words) if (word.contains(query)) word],
          ),
    ];
  }

  /// Every matching word in the open scene, across all pages.
  int get visibleWordCount {
    var total = 0;
    for (final group in _filteredGroups) {
      total += group.words.length;
    }
    return total;
  }

  int get pageCount {
    final total = visibleWordCount;
    if (total <= pageWordThreshold) return 1;
    return (total + pageSize - 1) ~/ pageSize;
  }

  int get page {
    final last = pageCount - 1;
    if (last < 0) return 0;
    return _page > last ? last : _page;
  }

  /// The current page of the open scene, still grouped, still in frequency
  /// order. A facet can continue onto the next page, so [groupTotalWords] is not
  /// always `words.length` — the facet header shows both.
  List<ThemeGroup> get visibleGroups {
    final groups = _filteredGroups;
    if (pageCount <= 1) return groups;
    final start = page * pageSize;
    return _slice(groups, start, start + pageSize);
  }

  /// The facet's full size under the current filter — [visibleGroups] may carry
  /// only the part of it that lands on the current page.
  int groupTotalWords(String id) {
    for (final group in _filteredGroups) {
      if (group.id == id) return group.words.length;
    }
    return 0;
  }

  static List<ThemeGroup> _slice(List<ThemeGroup> groups, int start, int end) {
    final page = <ThemeGroup>[];
    var offset = 0;
    for (final group in groups) {
      final groupStart = offset;
      final groupEnd = groupStart + group.words.length;
      offset = groupEnd;
      if (groupEnd <= start) continue;
      if (groupStart >= end) break;
      final from = start > groupStart ? start - groupStart : 0;
      final to = end < groupEnd ? end - groupStart : group.words.length;
      page.add(ThemeGroup(
        id: group.id,
        label: group.label,
        words: group.words.sublist(from, to),
      ));
    }
    return page;
  }

  Future<void> initialize() async {
    await _service.init();
    _isLoading = false;
    notifyListeners();
  }

  void select(String sceneId) {
    if (_sceneId == sceneId) return;
    _sceneId = sceneId;
    _query = '';
    _page = 0;
    notifyListeners();
  }

  void backToScenes() {
    if (_sceneId == null) return;
    _sceneId = null;
    _query = '';
    _page = 0;
    notifyListeners();
  }

  void setQuery(String value) {
    if (_query == value) return;
    _query = value;
    // A narrower result set may have fewer pages than the one we were on.
    _page = 0;
    notifyListeners();
  }

  void setPage(int page) {
    final next = page < 0 ? 0 : (page > pageCount - 1 ? pageCount - 1 : page);
    if (next == _page) return;
    _page = next;
    notifyListeners();
  }
}
