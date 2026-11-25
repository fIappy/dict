import 'package:flutter/foundation.dart';

import '../core/providers/safe_change_notifier.dart';
import '../core/themes/theme_service.dart';
import '../core/ui/ui_memory.dart';

/// Broad macro-domain tabs grouping the curated COCA themes (`t01`–`t57`).
class ThemeDomain {
  const ThemeDomain({
    required this.id,
    required this.label,
    required this.minNumber,
    required this.maxNumber,
  });

  final String id;
  final String label;
  final int minNumber;
  final int maxNumber;

  bool containsSceneNumber(int? number) =>
      id == 'all' ||
      (number != null && number >= minNumber && number <= maxNumber);
}

/// State of the 主题 module: which scene is open, which domain/search filter is
/// active, and pagination inside a theme.
///
/// Only the open scene is persisted: the search box, domain filter, and paging
/// start fresh, because a filter restored behind the reader's back looks like a
/// missing scene.
class ThemesProvider extends ChangeNotifier with SafeChangeNotifier {
  static const List<ThemeDomain> domains = [
    ThemeDomain(id: 'all', label: '全部', minNumber: 0, maxNumber: 999),
    ThemeDomain(id: 'foundation', label: '语言基础', minNumber: 1, maxNumber: 8),
    ThemeDomain(id: 'action', label: '动作社交', minNumber: 9, maxNumber: 16),
    ThemeDomain(id: 'mind', label: '言谈心理', minNumber: 17, maxNumber: 24),
    ThemeDomain(id: 'life', label: '生活实用', minNumber: 25, maxNumber: 33),
    ThemeDomain(id: 'society', label: '职场社会', minNumber: 34, maxNumber: 41),
    ThemeDomain(id: 'culture', label: '文教体史', minNumber: 42, maxNumber: 49),
    ThemeDomain(id: 'nature', label: '自然时空', minNumber: 50, maxNumber: 57),
  ];

  /// The id of the synthetic "every theme" scene the drill and AI pages offer.
  static const String anySceneId = '__all__';

  /// Scenes longer than this page at [facetPageSize] words so large themes
  /// render crisply in one viewport.
  static const int facetPageThreshold = 50;

  /// Words per page for scenes above [facetPageThreshold].
  static const int facetPageSize = 50;

  final ThemeService _service = ThemeService();

  bool _isLoading = true;
  String? _sceneId;
  String _query = '';
  String _domainId = 'all';

  /// Expanded facets when a scene carries multiple sub-groups.
  final Set<String> _expandedFacets = {};
  final Map<String, int> _facetPages = {};

  bool get isLoading => _isLoading;
  String get query => _query;
  String get domainId => _domainId;
  String get source => _service.source;
  int get sceneCount => _service.scenes.length;
  int get totalWords => _service.totalWords;
  List<ThemeScene> get scenes => _service.scenes;

  static int? sceneNumberOf(ThemeScene scene) {
    final m = RegExp(r'^t(\d+)$').firstMatch(scene.id);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  ThemeDomain get _activeDomain {
    for (final d in domains) {
      if (d.id == _domainId) return d;
    }
    return domains.first;
  }

  /// Scenes matching the active domain filter (before text search).
  List<ThemeScene> get domainScenes {
    final domain = _activeDomain;
    if (domain.id == 'all') return _service.scenes;
    return [
      for (final scene in _service.scenes)
        if (domain.containsSceneNumber(sceneNumberOf(scene))) scene,
    ];
  }

  ThemeScene? _anyScene;

  /// Every theme as one list, for the 背词 / AI 练习 picker's 不限 option.
  ///
  /// A word may sit in several themes, so the union is deduplicated in theme
  /// order (t01 → t57), which keeps thematically related words together.
  ThemeScene? get anyScene {
    final scenes = _service.scenes;
    if (scenes.isEmpty) return null;
    final cached = _anyScene;
    if (cached != null) return cached;
    final seen = <String>{};
    final words = <String>[];
    final glosses = <String, String>{};
    for (final scene in scenes) {
      for (final group in scene.groups) {
        for (final word in group.words) {
          if (seen.add(word)) words.add(word);
        }
        for (final entry in group.glosses.entries) {
          glosses.putIfAbsent(entry.key, () => entry.value);
        }
      }
    }
    return _anyScene = ThemeScene(
      id: anySceneId,
      label: '不限',
      hint: '全部 ${scenes.length} 个主题',
      count: words.length,
      groups: [
        ThemeGroup(
          id: 'any',
          label: '全部主题',
          words: words,
          glosses: glosses,
        ),
      ],
    );
  }

  ThemeScene? get selectedScene {
    final id = _sceneId;
    if (id == null) return null;
    for (final scene in _service.scenes) {
      if (scene.id == id) return scene;
    }
    return null;
  }

  /// The scenes as the list shows them: narrowed by domain and search box, so
  /// a word can be found without knowing which scene holds it.
  List<ThemeScene> get visibleScenes {
    final base = domainScenes;
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return base;
    return [
      for (final scene in base)
        if (scene.label.toLowerCase().contains(query) ||
            scene.hint.toLowerCase().contains(query) ||
            scene.words.any((word) => word.contains(query)))
          scene,
    ];
  }

  void setDomain(String id) {
    if (_domainId == id) return;
    _domainId = domains.any((d) => d.id == id) ? id : 'all';
    notifyListeners();
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
            glosses: group.glosses,
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
    // Reopen the scene that was on screen, unless the library dropped it.
    final remembered = await UiMemory.readString(UiMemory.themeScene);
    if (remembered != null &&
        remembered.isNotEmpty &&
        _service.scenes.any((scene) => scene.id == remembered)) {
      _sceneId = remembered;
    }
    _isLoading = false;
    notifyListeners();
  }

  void select(String sceneId) {
    if (_sceneId == sceneId) return;
    _sceneId = sceneId;
    UiMemory.writeString(UiMemory.themeScene, sceneId);
    _query = '';
    _expandedFacets.clear();
    _facetPages.clear();
    notifyListeners();
  }

  void backToScenes() {
    if (_sceneId == null) return;
    _sceneId = null;
    UiMemory.writeString(UiMemory.themeScene, '');
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
