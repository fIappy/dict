import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// One slice of a scene. The curated COCA taxonomy is flat, so a scene holds a
/// single group; the type stays because the JSON contract carries groups and a
/// future taxonomy may split a theme again.
class ThemeGroup {
  const ThemeGroup({
    required this.id,
    required this.label,
    required this.words,
    this.glosses = const {},
  });

  final String id;
  final String label;

  /// Words in COCA frequency order, most frequent first.
  final List<String> words;

  /// Chinese gloss per word, for the 背词 window. Empty when the asset carries
  /// none (older data); the drill then shows a dash instead of a meaning.
  final Map<String, String> glosses;
}

/// A theme the vocabulary belongs to — 通用, 动作与变化, 科学与技术…
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

/// Loads `assets/data/themes.json`, which `tool/build_themes.py` builds from the
/// curated files in `tool/coca_theme/` and the COCA frequency list.
///
/// The build step validates every curated word against COCA and writes each
/// theme in frequency order, so this class only parses — no ordering happens
/// here.
class ThemeService {
  static final ThemeService _instance = ThemeService._();
  factory ThemeService() => _instance;
  ThemeService._();

  List<ThemeScene> _scenes = const [];
  String _source = '';
  bool _loaded = false;

  bool get isLoaded => _loaded;
  List<ThemeScene> get scenes => _scenes;

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
                  glosses: {
                    for (final entry
                        in ((group['glosses'] ?? const {}) as Map).entries)
                      entry.key as String: entry.value as String,
                  },
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
