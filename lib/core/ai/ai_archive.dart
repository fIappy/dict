import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme_agent.dart';

enum AiItemKind { sentences, passage }

/// One saved generation: either the example sentences written for a word, or a
/// passage written for a theme.
///
/// Stored under the theme it was generated in, which is the only organising
/// axis the reader asked for — "翻看复习" means opening a theme and reading what
/// was produced for it.
class AiArchiveItem {
  const AiArchiveItem({
    required this.id,
    required this.sceneId,
    required this.sceneLabel,
    required this.kind,
    required this.level,
    required this.createdAt,
    required this.model,
    this.word,
    this.title = '',
    this.lines = const [],
    this.text = '',
    this.phrases = const [],
    this.words = const [],
    this.length = 0,
    this.style = '',
    this.reasoning = '',
  });

  final String id;
  final String sceneId;
  final String sceneLabel;
  final AiItemKind kind;
  final PracticeLevel level;
  final int createdAt;
  final String model;

  /// The word the sentences were written for; null for a passage.
  final String? word;

  /// Passage title (empty for sentences).
  final String title;

  /// The example sentences, in generation order.
  final List<GeneratedSentence> lines;

  /// The passage body (empty for sentences).
  final String text;

  /// Collocations flagged in [text] or in [lines] when it was generated.
  final List<String> phrases;

  /// The theme words the passage was asked to use.
  final List<String> words;

  /// Requested length in words, when the item is a passage.
  final int length;

  /// Passage style name, when the item is a passage.
  final String style;

  /// The model's reasoning for this generation, when the endpoint exposed it.
  final String reasoning;

  DateTime get created => DateTime.fromMillisecondsSinceEpoch(createdAt);

  Map<String, dynamic> toJson() => {
    'id': id,
    'sceneId': sceneId,
    'sceneLabel': sceneLabel,
    'kind': kind.name,
    'level': level.name,
    'createdAt': createdAt,
    'model': model,
    if (word != null) 'word': word,
    if (title.isNotEmpty) 'title': title,
    if (lines.isNotEmpty) 'lines': [for (final l in lines) l.toJson()],
    if (text.isNotEmpty) 'text': text,
    if (phrases.isNotEmpty) 'phrases': phrases,
    if (words.isNotEmpty) 'words': words,
    if (length > 0) 'length': length,
    if (style.isNotEmpty) 'style': style,
    if (reasoning.isNotEmpty) 'reasoning': reasoning,
  };

  static AiArchiveItem? fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString();
    final sceneId = json['sceneId']?.toString();
    if (id == null || id.isEmpty || sceneId == null || sceneId.isEmpty) {
      return null;
    }
    final kind = AiItemKind.values.firstWhere(
      (k) => k.name == json['kind'],
      orElse: () => AiItemKind.sentences,
    );
    final level = PracticeLevel.values.firstWhere(
      (l) => l.name == json['level'],
      orElse: () => PracticeLevel.medium,
    );
    final rawLines = json['lines'];
    return AiArchiveItem(
      id: id,
      sceneId: sceneId,
      sceneLabel: json['sceneLabel']?.toString() ?? '',
      kind: kind,
      level: level,
      createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
      model: json['model']?.toString() ?? '',
      word: json['word']?.toString(),
      title: json['title']?.toString() ?? '',
      lines: [
        if (rawLines is List)
          for (final line in rawLines)
            if (line is Map)
              GeneratedSentence.fromJson(line.cast<String, dynamic>()),
      ],
      text: json['text']?.toString() ?? '',
      phrases: readPhraseList(json['phrases']),
      words: readPhraseList(json['words']),
      length: (json['length'] as num?)?.toInt() ?? 0,
      style: json['style']?.toString() ?? '',
      reasoning: json['reasoning']?.toString() ?? '',
    );
  }
}

/// The archive, kept in shared preferences as one JSON document.
///
/// Shared preferences rather than a table on purpose: it exists on every target
/// this app ships to (including the web build, where the SQLite layer is
/// replaced by a document store), and the payload is a few hundred short texts,
/// not a table that needs querying.
class AiArchiveStore {
  static const String _key = 'ai_archive_v1';
  static const String _seedKey = 'ai_seed_v1';
  static const String _seedAsset = 'assets/seed/ai_archive.json';

  /// Newest first; older items fall off the end so the document cannot grow
  /// without bound.
  static const int maxItems = 300;

  Future<List<AiArchiveItem>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final items = <AiArchiveItem>[];
      for (final entry in decoded) {
        if (entry is! Map) continue;
        final item = AiArchiveItem.fromJson(entry.cast<String, dynamic>());
        if (item != null) items.add(item);
      }
      items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return items;
    } on FormatException {
      // A corrupted document must not take the archive UI down with it.
      return const [];
    }
  }

  /// One-time import of the generations that ship with the app.
  ///
  /// Runs only when the reader's archive is still empty, and only once — a
  /// later launch that cleared the archive on purpose must stay cleared.
  Future<List<AiArchiveItem>> ensureSeeded() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_seedKey) ?? false) return load();
    await prefs.setBool(_seedKey, true);
    if ((await load()).isNotEmpty) return load();
    try {
      final raw = await rootBundle.loadString(_seedAsset);
      final data = jsonDecode(raw);
      final items = data is Map ? data['items'] : data;
      if (items is! List) return await load();
      final seeded = <AiArchiveItem>[];
      for (final entry in items) {
        if (entry is! Map) continue;
        final item = AiArchiveItem.fromJson(entry.cast<String, dynamic>());
        if (item != null) seeded.add(item);
      }
      if (seeded.isEmpty) return await load();
      seeded.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      await _write(seeded);
      return seeded;
    } catch (e) {
      debugPrint('archive seed import failed: $e');
      return load();
    }
  }

  Future<List<AiArchiveItem>> add(AiArchiveItem item) async {
    final items = [item, ...await load()];
    final trimmed = items.length > maxItems
        ? items.sublist(0, maxItems)
        : items;
    await _write(trimmed);
    return trimmed;
  }

  Future<List<AiArchiveItem>> remove(String id) async {
    final items = (await load()).where((entry) => entry.id != id).toList();
    await _write(items);
    return items;
  }

  Future<void> _write(List<AiArchiveItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode([for (final item in items) item.toJson()]),
    );
  }
}
