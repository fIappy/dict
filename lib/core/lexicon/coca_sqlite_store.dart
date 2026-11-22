import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/lexeme_entry.dart';
import '../models/search_result.dart';

/// Pure-Dart read-only query layer for `coca_learn.db` (53,925 words).
///
/// Shared between desktop/mobile [CocaLexiconService] and `server/dict_server.dart`.
class CocaSqliteStore {
  CocaSqliteStore(this._db);

  static const String libraryId = 'coca_learn';
  static const String libraryName = 'COCA 5.4万 AI 学习库';

  final Database _db;
  Map<String, String>? _metaCache;

  /// Normalizes user queries (curly quotes & casing) for exact/prefix match.
  static String normalizeQuery(String raw) => raw
      .trim()
      .replaceAll('\u2019', "'")
      .replaceAll('\u2018', "'")
      .replaceAll("''", "'")
      .toLowerCase();

  /// Common British -> American spelling variants so British theme/input
  /// spellings resolve cleanly to US headwords in COCA.
  static const Map<String, String> ukToUs = {
    'dependant': 'dependent',
    'enquiry': 'inquiry',
    'colour': 'color',
    'favour': 'favor',
    'honour': 'honor',
    'labour': 'labor',
    'neighbour': 'neighbor',
    'behaviour': 'behavior',
    'glamour': 'glamor',
    'humour': 'humor',
    'rumour': 'rumor',
    'flavour': 'flavor',
    'savour': 'savor',
    'harbour': 'harbor',
    'vigour': 'vigor',
    'valour': 'valor',
    'centre': 'center',
    'metre': 'meter',
    'litre': 'liter',
    'theatre': 'theater',
    'fibre': 'fiber',
    'sombre': 'somber',
    'defence': 'defense',
    'offence': 'offense',
    'licence': 'license',
    'practise': 'practice',
    'organise': 'organize',
    'realise': 'realize',
    'analyse': 'analyze',
    'recognise': 'recognize',
    'apologise': 'apologize',
    'criticise': 'criticize',
    'emphasise': 'emphasize',
    'summarise': 'summarize',
    'prioritise': 'prioritize',
    'customise': 'customize',
    'minimise': 'minimize',
    'maximise': 'maximize',
    'visualise': 'visualize',
    'traveller': 'traveler',
    'counsellor': 'counselor',
    'jewellery': 'jewelry',
    'programme': 'program',
    'appal': 'appall',
    'catalogue': 'catalog',
    'dialogue': 'dialog',
    'monologue': 'monolog',
    'grey': 'gray',
    'tyre': 'tire',
    'cheque': 'check',
    'judgement': 'judgment',
    'modelling': 'modeling',
    'cancelled': 'canceled',
    'travelling': 'traveling',
    'plough': 'plow',
    'sceptical': 'skeptical',
    'encyclopaedia': 'encyclopedia',
    'paediatric': 'pediatric',
    'anaesthetic': 'anesthetic',
    'manoeuvre': 'maneuver',
  };

  /// Conservative inflection candidates tried only after exact & UK->US fail.
  static List<String> lemmaCandidates(String word) {
    final out = <String>[];
    void add(String candidate) {
      if (candidate.length >= 2 && candidate != word && !out.contains(candidate)) {
        out.add(candidate);
      }
    }

    if (word.endsWith('ies') && word.length > 4) {
      add('${word.substring(0, word.length - 3)}y');
    }
    if (word.endsWith('ves') && word.length > 4) {
      add('${word.substring(0, word.length - 3)}f');
      add('${word.substring(0, word.length - 3)}fe');
    }
    if (word.endsWith('es') && word.length > 3) {
      add(word.substring(0, word.length - 2));
      add(word.substring(0, word.length - 1));
    } else if (word.endsWith('s') && !word.endsWith('ss') && word.length > 3) {
      add(word.substring(0, word.length - 1));
    }

    if (word.endsWith('ied') && word.length > 4) {
      add('${word.substring(0, word.length - 3)}y');
    }
    if (word.endsWith('ed') && word.length > 4) {
      final stem = word.substring(0, word.length - 2);
      add(stem);
      add(word.substring(0, word.length - 1));
      if (stem.length >= 3 && stem[stem.length - 1] == stem[stem.length - 2]) {
        add(stem.substring(0, stem.length - 1));
      }
    }

    if (word.endsWith('ing') && word.length > 5) {
      final stem = word.substring(0, word.length - 3);
      add(stem);
      add('${stem}e');
      if (stem.length >= 3 && stem[stem.length - 1] == stem[stem.length - 2]) {
        add(stem.substring(0, stem.length - 1));
      }
    }

    if (word.endsWith('iest') && word.length > 5) {
      add('${word.substring(0, word.length - 4)}y');
    }
    if (word.endsWith('est') && word.length > 4) {
      final stem = word.substring(0, word.length - 3);
      add(stem);
      add('${stem}e');
      if (stem.length >= 3 && stem[stem.length - 1] == stem[stem.length - 2]) {
        add(stem.substring(0, stem.length - 1));
      }
    }
    if (word.endsWith('ier') && word.length > 4) {
      add('${word.substring(0, word.length - 3)}y');
    }
    if (word.endsWith('er') && word.length > 4) {
      final stem = word.substring(0, word.length - 2);
      add(stem);
      add('${stem}e');
      if (stem.length >= 3 && stem[stem.length - 1] == stem[stem.length - 2]) {
        add(stem.substring(0, stem.length - 1));
      }
    }
    if (word.endsWith('e') && word.length > 3) {
      add('${word}d');
    }

    return out;
  }

  Future<Map<String, String>> loadMeta() async {
    if (_metaCache != null) return _metaCache!;
    final rows = await _db.query('meta', columns: const ['key', 'value']);
    final map = <String, String>{};
    for (final row in rows) {
      final k = row['key'] as String?;
      final v = row['value'] as String?;
      if (k != null && v != null) map[k] = v;
    }
    return _metaCache = Map<String, String>.unmodifiable(map);
  }

  Future<int> countEntries() async {
    final meta = await loadMeta();
    final metaCount = int.tryParse(meta['entry_count'] ?? '');
    if (metaCount != null && metaCount > 0) return metaCount;
    final rows = await _db.rawQuery('SELECT COUNT(*) AS cnt FROM lexemes');
    if (rows.isEmpty) return 0;
    return (rows.first['cnt'] as num?)?.toInt() ?? 0;
  }

  Future<LexemeEntry?> lookup(String word) async {
    final norm = normalizeQuery(word);
    if (norm.isEmpty) return null;

    var matchedFrom = null as String?;
    var lexRow = await _queryLexemeRow(norm);

    if (lexRow == null) {
      final usVariant = ukToUs[norm];
      if (usVariant != null) {
        lexRow = await _queryLexemeRow(usVariant);
        if (lexRow != null) matchedFrom = norm;
      }
    }

    if (lexRow == null) {
      final candidates = lemmaCandidates(norm);
      if (candidates.isNotEmpty) {
        final placeholders = List<String>.filled(candidates.length, '?').join(',');
        final rows = await _db.rawQuery(
          'SELECT * FROM lexemes WHERE word IN ($placeholders) ORDER BY rank ASC LIMIT 1',
          candidates,
        );
        if (rows.isNotEmpty) {
          lexRow = rows.first;
          matchedFrom = norm;
        }
      }
    }

    if (lexRow == null) return null;

    final rank = (lexRow['rank'] as num).toInt();
    final chunksRows = await _db.query(
      'chunks',
      columns: const ['kind', 'text'],
      where: 'word_rank = ?',
      whereArgs: [rank],
      orderBy: 'id ASC',
    );
    final sentRows = await _db.query(
      'sentences',
      columns: const ['text', 'translation', 'phrases_json'],
      where: 'word_rank = ?',
      whereArgs: [rank],
      orderBy: 'seq ASC',
    );
    final psgRows = await _db.query(
      'passages',
      columns: const ['title', 'text', 'phrases_json'],
      where: 'word_rank = ?',
      whereArgs: [rank],
      limit: 1,
    );

    final collocations = <String>[];
    final patterns = <String>[];
    final expressions = <String>[];
    for (final row in chunksRows) {
      final kind = row['kind'] as String? ?? '';
      final text = row['text'] as String? ?? '';
      if (text.isEmpty) continue;
      switch (kind) {
        case 'collocation':
          collocations.add(text);
          break;
        case 'pattern':
          patterns.add(text);
          break;
        case 'expression':
          expressions.add(text);
          break;
      }
    }

    final sentences = <LexemeSentence>[
      for (final row in sentRows)
        LexemeSentence(
          text: row['text'] as String? ?? '',
          translation: row['translation'] as String? ?? '',
          phrases: _decodeStringList(row['phrases_json'] as String?),
        ),
    ];

    LexemePassage? passage;
    if (psgRows.isNotEmpty) {
      final row = psgRows.first;
      passage = LexemePassage(
        title: row['title'] as String? ?? '',
        text: row['text'] as String? ?? '',
        phrases: _decodeStringList(row['phrases_json'] as String?),
      );
    }

    final posRaw = (lexRow['pos'] as String? ?? '').trim();
    return LexemeEntry(
      rank: rank,
      cocaRank: (lexRow['coca_rank'] as num?)?.toInt() ?? rank,
      word: lexRow['word'] as String? ?? norm,
      freq: (lexRow['freq'] as num?)?.toInt() ?? 0,
      pos: posRaw.isEmpty
          ? const []
          : posRaw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
      themeId: lexRow['theme_id'] as String?,
      themeGloss: lexRow['theme_gloss'] as String?,
      register: lexRow['register'] as String? ?? 'standard',
      meaningZh: lexRow['meaning_zh'] as String? ?? '',
      usageZh: lexRow['usage_zh'] as String? ?? '',
      collocations: collocations,
      patterns: patterns,
      expressions: expressions,
      sentences: sentences,
      passage: passage,
      matchedFrom: matchedFrom,
    );
  }

  Future<List<SearchResult>> search(String query, {int limit = 60}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    final safeLimit = limit.clamp(1, 200);

    final results = <SearchResult>[];
    final seen = <String>{};

    void addRow(
      Map<String, Object?> row,
      SearchMatchType matchType, {
      String? customBrief,
    }) {
      final word = (row['word'] as String? ?? '').trim();
      if (word.isEmpty) return;
      final key = word.toLowerCase();
      if (!seen.add(key)) return;
      final rank = (row['rank'] as num?)?.toInt();
      final themeGloss = (row['theme_gloss'] as String?)?.trim();
      final meaning = (row['meaning_zh'] as String?) ?? '';
      final brief = customBrief ??
          ((themeGloss != null && themeGloss.isNotEmpty)
              ? themeGloss
              : _firstClause(meaning));
      results.add(SearchResult(
        word: word,
        matchType: matchType,
        dictionaryId: libraryId,
        dictionaryName: libraryName,
        briefDefinition: brief.isEmpty ? null : brief,
        frequencyBadge: rank != null ? 'COCA #$rank' : null,
      ));
    }

    // CJK query searches theme gloss & Chinese definitions ordered by frequency.
    if (RegExp(r'[\u4e00-\u9fff]').hasMatch(trimmed)) {
      final like = '%${_escapeLike(trimmed)}%';
      final rows = await _db.rawQuery(
        'SELECT word, rank, theme_gloss, meaning_zh FROM lexemes '
        r"WHERE theme_gloss LIKE ? ESCAPE '\' OR meaning_zh LIKE ? ESCAPE '\' "
        'ORDER BY CASE '
        r"WHEN theme_gloss LIKE ? ESCAPE '\' THEN 0 ELSE 1 END, rank ASC "
        'LIMIT ?',
        [like, like, like, safeLimit],
      );
      for (final row in rows) {
        addRow(row, SearchMatchType.substring);
      }
      return results;
    }

    final norm = normalizeQuery(trimmed);
    if (norm.isEmpty) return const [];

    // 1. Exact headword match (+ UK -> US spelling normalization).
    final exactRow = await _queryLexemeBriefRow(norm);
    if (exactRow != null) {
      addRow(exactRow, SearchMatchType.exact);
    }
    final usVariant = ukToUs[norm];
    if (usVariant != null && results.length < safeLimit) {
      final usRow = await _queryLexemeBriefRow(usVariant);
      if (usRow != null) {
        addRow(usRow, SearchMatchType.exact);
      }
    }

    // 2. Prefix headword range scan (uses UNIQUE word index on lexemes(word)).
    if (results.length < safeLimit) {
      final upper = _prefixUpperBound(norm);
      final remaining = safeLimit - results.length;
      final prefixRows = upper != null
          ? await _db.rawQuery(
              'SELECT word, rank, theme_gloss, meaning_zh FROM lexemes '
              'WHERE word >= ? AND word < ? ORDER BY rank ASC LIMIT ?',
              [norm, upper, remaining + seen.length],
            )
          : await _db.rawQuery(
              'SELECT word, rank, theme_gloss, meaning_zh FROM lexemes '
              r"WHERE word LIKE ? ESCAPE '\' ORDER BY rank ASC LIMIT ?",
              ['${_escapeLike(norm)}%', remaining + seen.length],
            );
      for (final row in prefixRows) {
        if (results.length >= safeLimit) break;
        addRow(row, SearchMatchType.prefix);
      }
    }

    // 3. Substring headword match (for partial middle matches).
    if (results.length < safeLimit && norm.length >= 2) {
      final remaining = safeLimit - results.length;
      final subRows = await _db.rawQuery(
        'SELECT word, rank, theme_gloss, meaning_zh FROM lexemes '
        r"WHERE word LIKE ? ESCAPE '\' ORDER BY rank ASC LIMIT ?",
        ['%${_escapeLike(norm)}%', remaining + seen.length],
      );
      for (final row in subRows) {
        if (results.length >= safeLimit) break;
        addRow(row, SearchMatchType.substring);
      }
    }

    // 4. Chunk match across collocations / patterns / expressions.
    if (results.length < safeLimit && norm.length >= 2) {
      final remaining = safeLimit - results.length;
      final like = '%${_escapeLike(norm)}%';
      final chunkRows = await _db.rawQuery(
        'SELECT l.word, l.rank, l.theme_gloss, l.meaning_zh, c.text AS chunk_text '
        'FROM chunks c JOIN lexemes l ON l.rank = c.word_rank '
        r"WHERE c.text LIKE ? ESCAPE '\' "
        'ORDER BY l.rank ASC LIMIT ?',
        [like, (remaining + seen.length) * 2],
      );
      for (final row in chunkRows) {
        if (results.length >= safeLimit) break;
        final chunk = (row['chunk_text'] as String? ?? '').trim();
        final gloss = (row['theme_gloss'] as String?)?.trim();
        final base = (gloss != null && gloss.isNotEmpty)
            ? gloss
            : _firstClause(row['meaning_zh'] as String? ?? '');
        final customBrief = chunk.isEmpty
            ? base
            : (base.isEmpty ? '「$chunk」' : '「$chunk」· $base');
        addRow(row, SearchMatchType.substring, customBrief: customBrief);
      }
    }

    return results;
  }

  Future<Map<String, Object?>?> _queryLexemeRow(String normWord) async {
    final rows = await _db.query(
      'lexemes',
      where: 'word = ?',
      whereArgs: [normWord],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<Map<String, Object?>?> _queryLexemeBriefRow(String normWord) async {
    final rows = await _db.query(
      'lexemes',
      columns: const ['word', 'rank', 'theme_gloss', 'meaning_zh'],
      where: 'word = ?',
      whereArgs: [normWord],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  static List<String> _decodeStringList(String? rawJson) {
    if (rawJson == null || rawJson.isEmpty) return const [];
    try {
      final decoded = json.decode(rawJson);
      if (decoded is List) {
        return decoded.map((e) => e.toString()).toList();
      }
    } catch (_) {}
    return const [];
  }

  static String _escapeLike(String value) => value
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');

  static String? _prefixUpperBound(String prefix) {
    if (prefix.isEmpty) return null;
    final units = prefix.codeUnits.toList();
    for (var i = units.length - 1; i >= 0; i--) {
      if (units[i] < 0xFFFF) {
        units[i]++;
        return String.fromCharCodes(units.sublist(0, i + 1));
      }
    }
    return null;
  }

  static String _firstClause(String meaning) {
    final clean = meaning.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.isEmpty) return '';
    final parts = clean.split(RegExp(r'[。；]'));
    final first = parts.firstWhere(
      (part) => part.trim().isNotEmpty,
      orElse: () => clean,
    ).trim();
    if (first.length <= 60) return first;
    return '${first.substring(0, 60)}…';
  }

  Future<void> close() async {
    _metaCache = null;
    await _db.close();
  }
}
