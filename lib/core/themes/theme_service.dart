import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// One facet of a scene — 人 / 事 / 物 / 动作 / 情况 / 虚拟.
class ThemeGroup {
  const ThemeGroup({required this.id, required this.label, required this.words});

  final String id;
  final String label;

  /// Words in COCA frequency order, most frequent first.
  final List<String> words;
}

/// A situation the vocabulary belongs to — 居家生活, 校园学习, 医疗健康…
class ThemeScene {
  const ThemeScene({
    required this.id,
    required this.label,
    required this.hint,
    required this.count,
    required this.groups,
  });

  final String id;
  final String label;
  final String hint;

  /// Number of word placements in this scene (a word may sit in several scenes,
  /// so this is not a count of distinct words).
  final int count;

  final List<ThemeGroup> groups;

  Iterable<String> get words sync* {
    for (final group in groups) {
      yield* group.words;
    }
  }
}

class ThemeFacet {
  const ThemeFacet({required this.id, required this.label});

  final String id;
  final String label;
}

/// Loads `assets/data/themes.json`, which `tool/build_themes.dart` builds from
/// the curated lexicon in `tool/themes_lexicon.json` and the COCA frequency list.
///
/// The build step validates every curated word against COCA and sorts each facet
/// by frequency, so this class only parses — no ordering happens here.
class ThemeService {
  static final ThemeService _instance = ThemeService._();
  factory ThemeService() => _instance;
  ThemeService._();

  List<ThemeScene> _scenes = const [];
  List<ThemeFacet> _facets = const [];
  String _source = '';
  bool _loaded = false;

  bool get isLoaded => _loaded;
  List<ThemeScene> get scenes => _scenes;
  List<ThemeFacet> get facets => _facets;

  /// Where the words came from, e.g. "COCA 20200 words" — shown in the UI so the
  /// list is never mistaken for something the dictionary supplied.
  String get source => _source;

  int get totalWords {
    var total = 0;
    for (final scene in _scenes) {
      total += scene.count;
    }
    return total;
  }

  Future<void> init() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final raw = await rootBundle.loadString('assets/data/themes.json');
      final data = jsonDecode(raw) as Map<String, dynamic>;
      _source = (data['source'] ?? '') as String;
      _facets = [
        for (final facet in (data['facets'] ?? const []) as List)
          ThemeFacet(id: facet['id'] as String, label: facet['label'] as String),
      ];
      _scenes = [
        for (final scene in (data['scenes'] ?? const []) as List)
          ThemeScene(
            id: scene['id'] as String,
            label: scene['label'] as String,
            hint: (scene['hint'] ?? '') as String,
            count: (scene['count'] ?? 0) as int,
            groups: [
              for (final group in (scene['groups'] ?? const []) as List)
                ThemeGroup(
                  id: group['id'] as String,
                  label: group['label'] as String,
                  words: [for (final word in group['words'] as List) word as String],
                ),
            ],
          ),
      ];
    } catch (e) {
      // A missing or malformed asset leaves the module empty rather than taking
      // the whole app down with it.
      debugPrint('Theme data failed to load: $e');
    }
  }
}
