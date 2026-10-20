import 'package:flutter/foundation.dart';

import '../core/themes/theme_service.dart';

/// State of the 主题 module: which scene is open, what the search box holds, and
/// which facets (人 / 事 / 物 …) the reader has opened.
///
/// Nothing here is persisted — the scene list is meant to be browsed, and coming
/// back to the top-level list on restart is the sane default.
class ThemesProvider extends ChangeNotifier {
  /// Facets longer than this page; shorter ones render in one go. 通用高频's
  /// 情况 facet holds ~3.4k words, and handing that to a single `Wrap` stalls.
  static const int facetPageThreshold = 500;

  /// Words per page for facets above [facetPageThreshold].
  static const int facetPageSize = 300;

  final ThemeService _service = ThemeService();

  bool _isLoading = true;
  String? _sceneId;
  String _query = '';

  /// Facets the reader opened. Everything starts folded so a scene's six facet
  /// headers are visible at once instead of 人 filling the whole viewport.
  final Set<String> _expandedFacets = {};
  final Map<String, int> _facetPages = {};

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
  /// facets that end up empty. Words are complete here — [facetWords] is the
  /// paged view of one facet.
  List<ThemeGroup> get visibleGroups {
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

  /// Every matching word in the open scene, across all facets.
  int get visibleWordCount {
    var total = 0;
    for (final group in visibleGroups) {
      total += group.words.length;
    }
    return total;
  }

  bool isFacetExpanded(String facetId) => _expandedFacets.contains(facetId);

  void toggleFacet(String facetId) {
    if (!_expandedFacets.remove(facetId)) _expandedFacets.add(facetId);
    notifyListeners();
  }

  int facetPageCount(ThemeGroup group) {
    final total = group.words.length;
    if (total <= facetPageThreshold) return 1;
    return (total + facetPageSize - 1) ~/ facetPageSize;
  }

  int facetPage(ThemeGroup group) {
    final stored = _facetPages[group.id] ?? 0;
    final last = facetPageCount(group) - 1;
    return stored > last ? last : stored;
  }

  /// The slice of [group] to render: the whole facet, or its current page.
  List<String> facetWords(ThemeGroup group) {
    if (facetPageCount(group) <= 1) return group.words;
    final start = facetPage(group) * facetPageSize;
    final end = start + facetPageSize;
    return group.words.sublist(start, end < group.words.length ? end : group.words.length);
  }

  void setFacetPage(ThemeGroup group, int page) {
    final last = facetPageCount(group) - 1;
    final next = page < 0 ? 0 : (page > last ? last : page);
    if ((_facetPages[group.id] ?? 0) == next) return;
    _facetPages[group.id] = next;
    notifyListeners();
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
    _expandedFacets.clear();
    _facetPages.clear();
    notifyListeners();
  }

  void backToScenes() {
    if (_sceneId == null) return;
    _sceneId = null;
    _query = '';
    _expandedFacets.clear();
    _facetPages.clear();
    notifyListeners();
  }

  void setQuery(String value) {
    if (_query == value) return;
    _query = value;
    _facetPages.clear();
    // Reveal what matched — a hit hidden behind a folded header reads as no hit.
    if (value.trim().isNotEmpty) {
      for (final group in visibleGroups) {
        _expandedFacets.add(group.id);
      }
    }
    notifyListeners();
  }
}
