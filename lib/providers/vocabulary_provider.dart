import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How the drill narrows the word list by star count.
enum StarFilter {
  /// Every word of the theme.
  all('不限'),

  /// Any word with at least one star.
  starred('只看带星'),

  /// Exactly [VocabularyProvider.filterStars] stars.
  exact('恰好'),

  /// [VocabularyProvider.filterStars] stars or more.
  atLeast('至少');

  const StarFilter(this.label);

  final String label;

  static StarFilter byName(String? name) {
    for (final filter in values) {
      if (filter.name == name) return filter;
    }
    return all;
  }
}

/// State of the 背词 window: how many stars each word carries, which glosses
/// the reader has peeled back, and how the list is filtered.
///
/// Stars are keyed by the word itself, not by (theme, word): a word belongs to
/// one theme in the taxonomy, and a reader who starred `hospital` does not want
/// to star it twice if the taxonomy ever splits.
class VocabularyProvider extends ChangeNotifier {
  static const String _starsKey = 'vocab_stars_v1';
  static const String _filterKey = 'vocab_filter_v1';
  static const String _accentKey = 'vocab_accent_v1';
  static const String _seedVersionKey = 'vocab_stars_seed_version';
  static const String _seedAsset = 'assets/seed/vocab_stars.json';
  static const int maxStars = 5;

  final Map<String, int> _stars = {};
  final Set<String> _revealed = {};

  StarFilter _filter = StarFilter.all;
  int _filterStars = 2;
  bool _revealAll = false;
  bool _initialized = false;

  /// Pronunciation accent for the drill: 'us' (default) or 'uk'.
  String _accent = 'us';

  /// Whether the list is shown in the shuffled order the reader asked for.
  bool _shuffled = false;

  /// Position of each word in that shuffled order; words added later (a filter
  /// change never adds any, but the scene could) sort to the end.
  Map<String, int> _shuffleRank = const {};

  bool get isInitialized => _initialized;
  String get accent => _accent;
  String get accentLabel => _accent == 'uk' ? '英音' : '美音';
  bool get isShuffled => _shuffled;
  StarFilter get filter => _filter;
  int get filterStars => _filterStars;
  bool get revealAll => _revealAll;

  /// Words carrying at least one star, for the toolbar count.
  int get starredCount => _stars.values.where((value) => value > 0).length;

  int starsOf(String word) => _stars[word] ?? 0;

  bool isRevealed(String word) => _revealAll || _revealed.contains(word);

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_starsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final data = jsonDecode(raw);
        if (data is Map) {
          for (final entry in data.entries) {
            final value = entry.value;
            if (entry.key is String && value is num) {
              final stars = value.toInt().clamp(0, maxStars);
              if (stars > 0) _stars[entry.key as String] = stars;
            }
          }
        }
      } on FormatException {
        // Corrupted stars must not take the drill down: start unstarred.
      }
    }
    _accent = prefs.getString(_accentKey) == 'uk' ? 'uk' : 'us';
    final saved = prefs.getString(_filterKey);
    if (saved != null && saved.isNotEmpty) {
      final parts = saved.split(':');
      _filter = StarFilter.byName(parts.first);
      if (parts.length > 1) {
        _filterStars = (int.tryParse(parts[1]) ?? _filterStars).clamp(1, maxStars);
      }
    }
    notifyListeners();
  }

  /// Switches between 美音 ('us') and 英音 ('uk'), remembered across launches.
  Future<void> setAccent(String accent) async {
    final next = accent == 'uk' ? 'uk' : 'us';
    if (next == _accent) return;
    _accent = next;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accentKey, next);
  }

  Future<void> toggleAccent() => setAccent(_accent == 'uk' ? 'us' : 'uk');

  /// Shuffles [words] once and keeps that order until [restoreOrder].
  void shuffle(Iterable<String> words, {Random? random}) {
    final list = [...words]..shuffle(random ?? Random());
    _shuffleRank = {
      for (var i = 0; i < list.length; i++) list[i]: i,
    };
    _shuffled = true;
    notifyListeners();
  }

  /// Back to the theme's own order (COCA frequency inside the file).
  void restoreOrder() {
    if (!_shuffled) return;
    _shuffled = false;
    notifyListeners();
  }

  /// [words] in the order the list should show: shuffled when the reader asked
  /// for it, otherwise untouched.
  List<String> arrange(Iterable<String> words) {
    final list = [...words];
    if (!_shuffled) return list;
    list.sort((a, b) {
      final left = _shuffleRank[a] ?? 1 << 30;
      final right = _shuffleRank[b] ?? 1 << 30;
      return left.compareTo(right);
    });
    return list;
  }

  /// Sets the star count of [word], clamped to 0…[maxStars]; 0 forgets it.
  /// Merges the stars shipped with the app (`tool/build_themes.py` writes them
  /// from the `*` marks in the theme files).
  ///
  /// Runs once per asset version, and only fills words the reader has not rated
  /// yet — a star changed here stays changed. A word the reader deliberately
  /// cleared can therefore come back with a future library version; that is the
  /// price of the seed being the source of truth for curated ratings.
  Future<void> ensureSeeded() async {
    try {
      final raw = await rootBundle.loadString(_seedAsset);
      final data = jsonDecode(raw);
      if (data is! Map) return;
      final version = (data['version'] as num?)?.toInt() ?? 0;
      final prefs = await SharedPreferences.getInstance();
      if ((prefs.getInt(_seedVersionKey) ?? 0) >= version) return;

      final stars = <String, int>{};
      final rawStars = data['stars'];
      if (rawStars is Map) {
        for (final entry in rawStars.entries) {
          final value = entry.value;
          if (entry.key is String && value is num) {
            stars[entry.key as String] = value.toInt().clamp(1, maxStars);
          }
        }
      }
      final added = mergeSeed(stars);
      await prefs.setInt(_seedVersionKey, version);
      if (added > 0) {
        notifyListeners();
        await _persistStars();
      }
    } on Exception catch (e) {
      // A missing or malformed seed leaves the reader's own stars alone.
      debugPrint('Vocabulary star seed not merged: $e');
    }
  }

  /// Fills the unrated words from [stars]; returns how many it added.
  @visibleForTesting
  int mergeSeed(Map<String, int> stars) {
    var added = 0;
    for (final entry in stars.entries) {
      if (entry.value <= 0) continue;
      if (_stars.containsKey(entry.key)) continue;
      _stars[entry.key] = entry.value.clamp(1, maxStars);
      added++;
    }
    return added;
  }

  Future<void> setStars(String word, int value) async {
    final stars = value.clamp(0, maxStars);
    if (stars == starsOf(word)) return;
    if (stars == 0) {
      _stars.remove(word);
    } else {
      _stars[word] = stars;
    }
    notifyListeners();
    await _persistStars();
  }

  Future<void> addStar(String word) => setStars(word, starsOf(word) + 1);

  Future<void> removeStar(String word) => setStars(word, starsOf(word) - 1);

  void toggleGloss(String word) {
    if (!_revealed.remove(word)) _revealed.add(word);
    notifyListeners();
  }

  /// The one-click switch: reveal every gloss, or hide them all again.
  void setRevealAll(bool value) {
    if (_revealAll == value) return;
    _revealAll = value;
    _revealed.clear();
    notifyListeners();
  }

  void toggleRevealAll() => setRevealAll(!_revealAll);

  Future<void> setFilter(StarFilter filter, {int? stars}) async {
    final next = stars?.clamp(1, maxStars) ?? _filterStars;
    if (filter == _filter && next == _filterStars) return;
    _filter = filter;
    _filterStars = next;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_filterKey, '${filter.name}:$_filterStars');
  }

  /// [words] narrowed by the star filter, order kept.
  List<String> filtered(Iterable<String> words) {
    switch (_filter) {
      case StarFilter.all:
        return [...words];
      case StarFilter.starred:
        return [for (final word in words) if (starsOf(word) > 0) word];
      case StarFilter.exact:
        return [for (final word in words) if (starsOf(word) == _filterStars) word];
      case StarFilter.atLeast:
        return [for (final word in words) if (starsOf(word) >= _filterStars) word];
    }
  }

  Future<void> _persistStars() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_starsKey, jsonEncode(_stars));
  }
}
