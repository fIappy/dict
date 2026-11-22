import '../custom/custom_text.dart';
import '../mdx/entry_speech.dart';

class LexemeSentence {
  const LexemeSentence({
    required this.text,
    required this.translation,
    this.phrases = const [],
  });

  final String text;
  final String translation;
  final List<String> phrases;

  Map<String, dynamic> toJson() => {
        'text': text,
        'translation': translation,
        'phrases': phrases,
      };

  factory LexemeSentence.fromJson(Map<String, dynamic> json) => LexemeSentence(
        text: json['text'] as String? ?? '',
        translation: json['translation'] as String? ?? '',
        phrases: (json['phrases'] as List<dynamic>? ?? const [])
            .map((e) => e.toString())
            .toList(),
      );
}

class LexemePassage {
  const LexemePassage({
    required this.title,
    required this.text,
    this.phrases = const [],
  });

  final String title;
  final String text;
  final List<String> phrases;

  Map<String, dynamic> toJson() => {
        'title': title,
        'text': text,
        'phrases': phrases,
      };

  factory LexemePassage.fromJson(Map<String, dynamic> json) => LexemePassage(
        title: json['title'] as String? ?? '',
        text: json['text'] as String? ?? '',
        phrases: (json['phrases'] as List<dynamic>? ?? const [])
            .map((e) => e.toString())
            .toList(),
      );
}

/// Structured AI vocabulary learning entry stored in the 53,925-word
/// cleaned COCA learning database (`coca_learn.db`).
class LexemeEntry {
  const LexemeEntry({
    required this.rank,
    required this.cocaRank,
    required this.word,
    required this.freq,
    this.pos = const [],
    this.themeId,
    this.themeGloss,
    this.register = 'standard',
    this.meaningZh = '',
    this.usageZh = '',
    this.collocations = const [],
    this.patterns = const [],
    this.expressions = const [],
    this.sentences = const [],
    this.passage,
    this.matchedFrom,
  });

  final int rank;
  final int cocaRank;
  final String word;
  final int freq;
  final List<String> pos;
  final String? themeId;
  final String? themeGloss;
  final String register;
  final String meaningZh;
  final String usageZh;
  final List<String> collocations;
  final List<String> patterns;
  final List<String> expressions;
  final List<LexemeSentence> sentences;
  final LexemePassage? passage;
  final String? matchedFrom;

  /// Short Chinese gloss shown in search previews, favorites, and headers.
  String get briefZh {
    final gloss = themeGloss?.trim();
    if (gloss != null && gloss.isNotEmpty) return gloss;
    final clean = meaningZh.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.isEmpty) return '';
    final parts = clean.split(RegExp(r'[。；]'));
    final first = parts.firstWhere(
      (part) => part.trim().isNotEmpty,
      orElse: () => clean,
    ).trim();
    if (first.length <= 60) return first;
    return '${first.substring(0, 60)}…';
  }

  /// Speakable sequence for [EntrySpeechProvider]: example sentences followed
  /// by passage sentences, each tagged so the UI highlights the active line.
  List<EntryUtterance> toUtterances() {
    final out = <EntryUtterance>[];
    for (var i = 0; i < sentences.length; i++) {
      final line = sentences[i].text.trim();
      if (line.isEmpty) continue;
      out.add(EntryUtterance(
        text: line,
        isPhrase: false,
        itemId: 'lexeme_sent_$i',
        sentenceIndex: 0,
      ));
    }
    final psg = passage;
    if (psg != null && psg.text.trim().isNotEmpty) {
      final passageLines = splitSentences(psg.text);
      for (var i = 0; i < passageLines.length; i++) {
        final line = passageLines[i].trim();
        if (line.isEmpty) continue;
        out.add(EntryUtterance(
          text: line,
          isPhrase: false,
          itemId: 'lexeme_passage',
          sentenceIndex: i,
        ));
      }
    }
    return List<EntryUtterance>.unmodifiable(out);
  }

  Map<String, dynamic> toJson() => {
        'rank': rank,
        'cocaRank': cocaRank,
        'word': word,
        'freq': freq,
        'pos': pos,
        'themeId': themeId,
        'themeGloss': themeGloss,
        'register': register,
        'meaningZh': meaningZh,
        'usageZh': usageZh,
        'collocations': collocations,
        'patterns': patterns,
        'expressions': expressions,
        'sentences': sentences.map((s) => s.toJson()).toList(),
        'passage': passage?.toJson(),
        if (matchedFrom != null) 'matchedFrom': matchedFrom,
      };

  factory LexemeEntry.fromJson(Map<String, dynamic> json) => LexemeEntry(
        rank: (json['rank'] as num?)?.toInt() ?? 0,
        cocaRank: (json['cocaRank'] as num?)?.toInt() ?? 0,
        word: json['word'] as String? ?? '',
        freq: (json['freq'] as num?)?.toInt() ?? 0,
        pos: (json['pos'] as List<dynamic>? ?? const [])
            .map((e) => e.toString())
            .toList(),
        themeId: json['themeId'] as String?,
        themeGloss: json['themeGloss'] as String?,
        register: json['register'] as String? ?? 'standard',
        meaningZh: json['meaningZh'] as String? ?? '',
        usageZh: json['usageZh'] as String? ?? '',
        collocations: (json['collocations'] as List<dynamic>? ?? const [])
            .map((e) => e.toString())
            .toList(),
        patterns: (json['patterns'] as List<dynamic>? ?? const [])
            .map((e) => e.toString())
            .toList(),
        expressions: (json['expressions'] as List<dynamic>? ?? const [])
            .map((e) => e.toString())
            .toList(),
        sentences: (json['sentences'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(LexemeSentence.fromJson)
            .toList(),
        passage: json['passage'] is Map<String, dynamic>
            ? LexemePassage.fromJson(json['passage'] as Map<String, dynamic>)
            : null,
        matchedFrom: json['matchedFrom'] as String?,
      );
}
