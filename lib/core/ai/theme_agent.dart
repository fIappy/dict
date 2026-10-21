import 'dart:convert';

import 'ai_config.dart';
import 'openai_client.dart';
import 'passage_style.dart';

/// How hard the generated English should be.
/// How demanding the writing itself is — sentence patterns and how deep the
/// content goes. Which words must appear is a separate setting (the frequency
/// band), so this no longer says anything about vocabulary.
enum PracticeLevel { starter, easy, medium, hard, expert }

extension PracticeLevelLabel on PracticeLevel {
  String get label => switch (this) {
    PracticeLevel.starter => '易',
    PracticeLevel.easy => '较易',
    PracticeLevel.medium => '中',
    PracticeLevel.hard => '较难',
    PracticeLevel.expert => '难',
  };

  /// The word the model is given; prompts are written in English.
  String get promptName => switch (this) {
    PracticeLevel.starter => 'starter',
    PracticeLevel.easy => 'easy',
    PracticeLevel.medium => 'medium',
    PracticeLevel.hard => 'hard',
    PracticeLevel.expert => 'expert',
  };
}

/// A word with its COCA rank; 1 is the most frequent.
class RankedWord {
  const RankedWord(this.word, this.rank);

  final String word;
  final int rank;
}

class GeneratedSentence {
  const GeneratedSentence({
    required this.text,
    this.translation,
    this.phrases = const [],
  });

  final String text;
  final String? translation;

  /// Fixed collocations the model found in [text], verbatim.
  final List<String> phrases;

  Map<String, dynamic> toJson() => {
        'text': text,
        if (translation != null) 'translation': translation,
        if (phrases.isNotEmpty) 'phrases': phrases,
      };

  factory GeneratedSentence.fromJson(Map<String, dynamic> json) =>
      GeneratedSentence(
        text: (json['text'] ?? '').toString().trim(),
        translation: (json['translation'] ?? '').toString().trim().isEmpty
            ? null
            : (json['translation'] as String).trim(),
        phrases: readPhraseList(json['phrases']),
      );
}

/// Reads a phrase list, ignoring anything that is not a non-empty string.
List<String> readPhraseList(Object? raw) => [
      if (raw is List)
        for (final item in raw)
          if (item is String && item.trim().isNotEmpty) item.trim(),
    ];

class GeneratedPassage {
  const GeneratedPassage({
    required this.title,
    required this.text,
    this.phrases = const [],
  });

  final String title;
  final String text;

  /// Fixed collocations the model found in [text], verbatim.
  final List<String> phrases;

  /// English words in [text], the number the reader asked about.
  int get wordCount =>
      RegExp(r"[A-Za-z][A-Za-z'’-]*").allMatches(text).length;

  Map<String, dynamic> toJson() =>
      {'title': title, 'text': text, if (phrases.isNotEmpty) 'phrases': phrases};

  factory GeneratedPassage.fromJson(Map<String, dynamic> json) =>
      GeneratedPassage(
        title: (json['title'] ?? '').toString().trim(),
        text: (json['text'] ?? '').toString().trim(),
        phrases: readPhraseList(json['phrases']),
      );
}

/// Turns a theme's vocabulary into a prompt and the answer into text.
///
/// The theme side is what makes this more than a generic chat box: the prompt
/// names the exact words of the chosen frequency band instead of the whole
/// vocabulary, so the model is not handed a word list it cannot use.
class ThemeAgent {
  ThemeAgent({required OpenAiClient client}) : _client = client;

  final OpenAiClient _client;
  Future<({List<GeneratedSentence> items, String reasoning})> sentences({
    required String word,
    required int count,
    required PracticeLevel level,
    String? sceneLabel,
  }) async {
    final reply = await _client.complete(
      system: _sentenceSystem,
      user: _sentenceUser(
        word: word,
        count: count,
        level: level,
        sceneLabel: sceneLabel,
      ),
      temperature: 0.6,
      maxTokens: 1200,
    );
    final parsed = parseSentences(reply.text);
    if (parsed.isEmpty) {
      throw const AiException('模型没有返回可用的句子');
    }
    return (items: parsed, reasoning: reply.reasoning ?? '');
  }

  Future<({GeneratedPassage passage, String reasoning})> passage({
    required String sceneLabel,
    required String sceneHint,
    required List<String> words,
    required PracticeLevel level,
    PassageStyle style = PassageStyle.descriptive,
    int length = 140,
    String wordsNote = '',
    String extra = '',
  }) async {
    if (words.isEmpty) {
      throw const AiException('这个主题里没有可用于生成短文的词');
    }
    final reply = await _client.complete(
      system: _passageSystem,
      user: _passageUser(
        sceneLabel: sceneLabel,
        sceneHint: sceneHint,
        words: words,
        level: level,
        style: style,
        length: length,
        wordsNote: wordsNote,
        extra: extra,
      ),
      temperature: 0.75,
      // Roughly two tokens per English word plus the JSON scaffolding; a long
      // passage also needs a longer deadline than the client's default.
      maxTokens: (length * 2 + 600).clamp(800, 8000),
      timeout: _passageTimeout(length),
    );
    final parsed = parsePassage(reply.text);
    if (parsed.text.isEmpty) {
      throw const AiException('模型没有返回可用的短文');
    }
    return (passage: parsed, reasoning: reply.reasoning ?? '');
  }

  /// A reasoning model spends minutes thinking before it writes: a 1000-word
  /// request on DeepSeek produced ~29k characters of reasoning, so a flat
  /// deadline would turn every long passage into a timeout.
  Duration _passageTimeout(int length) {
    final base = 30 + length / 6;
    final factor = switch (_client.config.reasoningEffort) {
      AiReasoningEffort.none => 1.0,
      AiReasoningEffort.minimal => 1.5,
      AiReasoningEffort.low => 2.0,
      AiReasoningEffort.medium => 3.0,
      AiReasoningEffort.high => 4.0,
    };
    return Duration(seconds: (base * factor).round().clamp(90, 3600));
  }

  // ------------------------------------------------------------------ prompts

  static const String _sentenceSystem =
      'You are an experienced English teacher and lexicographer writing '
      'example sentences for Chinese learners of English.\n'
      'Rules:\n'
      '- Every sentence must be idiomatic modern English with correct grammar, '
      'punctuation and logic.\n'
      '- Never invent a meaning the target word does not have.\n'
      '- Reply with JSON only: no prose, no code fences.';

  /// What a sentence should look like at each rung of the ladder.
  static String _sentenceShape(PracticeLevel level) => switch (level) {
    PracticeLevel.starter => '5-9 words, one clause, present or past simple',
    PracticeLevel.easy => '7-13 words, one clause plus at most one short phrase',
    PracticeLevel.medium =>
      '10-16 words, one subordinate clause or a participial phrase',
    PracticeLevel.hard =>
      '13-21 words, subordination, passives or nominalisation',
    PracticeLevel.expert =>
      '16-28 words, embedded or cleft structures, precise register',
  };

  static String _sentenceUser({
    required String word,
    required int count,
    required PracticeLevel level,
    String? sceneLabel,
  }) {
    final theme = sceneLabel == null ? '' : '\nLearner\'s theme: $sceneLabel';
    return 'Target word: "$word"$theme\n'
        'Write exactly $count example sentences that use "$word" in its real '
        'senses; inflected forms are fine.\n'
        'Order them from easiest to hardest and from shortest to longest '
        '(level: ${level.promptName}).\n'
        'Sentence length and pattern by level: '
        '${_sentenceShape(level)}.\n'
        'Every sentence must be self-contained, use natural collocations, and '
        'show a different grammatical pattern from the others.\n'
        'No two sentences may be paraphrases of each other.\n'
        'For each sentence list 0-3 fixed collocations or set phrases that appear '
        'verbatim in it (e.g. "take care of", "in charge of"); use an empty list '
        'when there is none.\n'
        'Return this JSON shape:\n'
        '{"sentences":[{"text":"<English sentence>","translation":"<简体中文翻译>",'
        '"phrases":["<verbatim collocation>"]}]}';
  }

  static const String _passageSystem =
      'You are an experienced English teacher writing short reading passages '
      'for Chinese learners of English.\n'
      'Rules:\n'
      '- The passage must be coherent: one topic, a logical progression, no '
      'contradictions or non sequiturs.\n'
      '- Grammar, collocations and punctuation must be flawless, and the English '
      'must sound native rather than translated.\n'
      '- Reply with JSON only: no prose, no code fences.';

  static String _passageUser({
    required String sceneLabel,
    required String sceneHint,
    required List<String> words,
    required PracticeLevel level,
    required PassageStyle style,
    required int length,
    String wordsNote = '',
    String extra = '',
  }) {
    final levelRules = switch (level) {
      PracticeLevel.starter =>
        '- starter syntax: one clause per sentence (subject + verb + object), '
            'present or past simple only, no subordination, no passives.\n'
            '- depth: name what happened and who was there; no analysis, no '
            'opinions, no metaphors.',
      PracticeLevel.easy =>
        '- easy syntax: mostly short sentences, coordinating words (and, but, '
            'so, because), a few simple past/present perfect forms.\n'
        '- depth: one concrete situation told in order; at most one sentence of '
            'comment.',
      PracticeLevel.medium =>
        '- medium syntax: a mix of simple and complex sentences, one subordinate '
            'clause at a time, occasional passive voice.\n'
        '- depth: describe and explain — say how something works or why it '
            'matters, with a clear opening, body and close.',
      PracticeLevel.hard =>
        '- hard syntax: subordinate and relative clauses, participial phrases, '
            'nominalisation, varied sentence length.\n'
        '- depth: interpret rather than only report — connect cause and effect, '
            'weigh two readings of the same event, use precise register.',
      PracticeLevel.expert =>
        '- expert syntax: dense, embedded clauses; inversion, cleft sentences '
            'and ellipsis used deliberately; no filler.\n'
        '- depth: make a claim, support it with evidence from the scene, '
            'acknowledge a counterpoint, and land on a conclusion that is more '
            'than a summary.',
    };
    final note = wordsNote.isEmpty ? '' : '\n$wordsNote';
    // One 1000-word block is where models drift short; explicit per-paragraph
    // budgets hold much better than a single total.
    final paragraphs = length >= 400 ? (length / 200).ceil().clamp(2, 10) : 0;
    final plan = paragraphs == 0
        ? ''
        : '- Write exactly $paragraphs paragraphs of about '
            '${(length / paragraphs).round()} words each, and do not stop early.\n';
    final extraRules = extra.trim().isEmpty
        ? ''
        : '\nAdditional requirements from the learner — follow them unless they '
            'contradict a rule above:\n${extra.trim()}\n';
    return 'Theme: $sceneLabel — $sceneHint\n'
        'Style: ${style.label} — ${style.prompt}\n'
        'Length: about $length words (within 10%).\n'
        'Level: ${level.promptName}\n'
        'Required words (each must appear at least once, in a correct and '
        'natural sense): ${words.join(', ')}$note\n\n'
        'Write ONE passage of about $length words.\n'
        '$levelRules\n'
        'Content rules:\n'
        '$plan'
        '- Use every required word.\n'
        '- Keep exactly one topic and the requested style throughout.\n'
        '- No grammar, collocation or logic errors.\n'
        '$extraRules'
        'Also list 5-10 fixed collocations or set phrases that appear verbatim in '
        'the passage.\n'
        'Return this JSON shape:\n'
        '{"title":"<short English title>","text":"<the passage>",'
        '"phrases":["<verbatim collocation>"]}';
  }

  // ------------------------------------------------------------------ parsing

  /// Decodes the model's answer.
  ///
  /// Servers are far less obedient than the prompt: reasoning models narrate
  /// before answering, some wrap the JSON in code fences, some answer with two
  /// objects, and prose can hold braces of its own. Every balanced `{…}` /
  /// `[…]` span is tried in order instead of the old "first brace to last
  /// brace" guess, which fell over the moment a brace appeared in the intro.
  static Object? _decode(String raw) {
    for (final candidate in _candidates(raw)) {
      try {
        return jsonDecode(candidate);
      } on FormatException {
        continue;
      }
    }
    throw AiException('模型返回的内容不是合法 JSON（开头：${_snippet(raw)}）');
  }

  /// Ordered guesses: the whole text, each fenced block, then every balanced
  /// brace/bracket span. Full-width punctuation is mapped first — a model that
  /// writes `｛` is not giving us JSON, whatever else it got right.
  static Iterable<String> _candidates(String raw) sync* {
    final text = raw
        .replaceAll('｛', '{')
        .replaceAll('｝', '}')
        .replaceAll('［', '[')
        .replaceAll('］', ']')
        .replaceAll('＂', '"')
        .trim();
    if (text.isEmpty) return;
    yield text;
    for (final match in RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```').allMatches(text)) {
      final inner = match.group(1)!.trim();
      if (inner.isNotEmpty) yield inner;
    }
    var tried = 0;
    for (var i = 0; i < text.length && tried < 200; i++) {
      final c = text[i];
      if (c != '{' && c != '[') continue;
      final end = _balancedEnd(text, i);
      if (end <= i) continue;
      tried++;
      yield text.substring(i, end + 1);
    }
  }

  /// The index of the brace that closes the one at [start], skipping braces
  /// inside string literals and their escapes; -1 when it never closes.
  static int _balancedEnd(String text, int start) {
    final open = text[start];
    final close = open == '{' ? '}' : ']';
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var i = start; i < text.length; i++) {
      final c = text[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (c == r'\') {
          escaped = true;
        } else if (c == '"') {
          inString = false;
        }
        continue;
      }
      if (c == '"') {
        inString = true;
      } else if (c == open) {
        depth++;
      } else if (c == close) {
        depth--;
        if (depth == 0) return i;
      }
    }
    return -1;
  }

  /// The start of whatever came back, so the reader (and a bug report) can see
  /// what the endpoint actually said instead of only that parsing failed.
  static String _snippet(String raw) {
    final flat = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (flat.isEmpty) return '（空）';
    return flat.length <= 180 ? flat : '${flat.substring(0, 180)}…';
  }


  /// Reads a list of sentences out of the model's answer.
  ///
  /// Accepts the asked-for `{"sentences":[…]}` shape, a bare array, and a
  /// single `{"text":…}` object — local models drift between all three.
  static List<GeneratedSentence> parseSentences(String raw) {
    final decoded = _decode(raw);
    final candidates = switch (decoded) {
      final List<Object?> list => list,
      final Map<Object?, Object?> map => switch (map['sentences']) {
        final List<Object?> list => list,
        _ => map['text'] != null ? <Object?>[map] : const <Object?>[],
      },
      _ => const <Object?>[],
    };

    final out = <GeneratedSentence>[];
    final seen = <String>{};
    for (final item in candidates) {
      final sentence = item is String
          ? GeneratedSentence(text: item.trim())
          : item is Map
              ? GeneratedSentence.fromJson(item.cast<String, dynamic>())
              : null;
      if (sentence == null || sentence.text.isEmpty) continue;
      if (!seen.add(sentence.text.toLowerCase())) continue;
      out.add(sentence);
    }
    return out;
  }

  static GeneratedPassage parsePassage(String raw) {
    final decoded = _decode(raw);
    if (decoded is! Map) {
      throw const AiException('模型返回的短文不是 JSON 对象');
    }
    final json = decoded.cast<String, dynamic>();
    final text = (json['text'] ?? json['passage'] ?? '').toString().trim();
    final title = (json['title'] ?? '').toString().trim();
    return GeneratedPassage(
      title: title.isEmpty ? 'Untitled' : title,
      text: text,
      phrases: readPhraseList(json['phrases']),
    );
  }
}
