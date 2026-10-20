import 'package:flutter/foundation.dart';

import '../core/themes/theme_service.dart';

/// State of the 主题 module: which scene is open and what the search box holds.
///
/// Nothing here is persisted — the scene list is meant to be browsed, and coming
/// back to the top-level list on restart is the sane default.
class ThemesProvider extends ChangeNotifier {
  final ThemeService _service = ThemeService();

  bool _isLoading = true;
  String? _sceneId;
  String _query = '';

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
  /// facets that end up empty.
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

  int get visibleWordCount {
    var total = 0;
    for (final group in visibleGroups) {
      total += group.words.length;
    }
    return total;
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
    notifyListeners();
  }

  void backToScenes() {
    if (_sceneId == null) return;
    _sceneId = null;
    _query = '';
    notifyListeners();
  }

  void setQuery(String value) {
    if (_query == value) return;
    _query = value;
    notifyListeners();
  }
}
