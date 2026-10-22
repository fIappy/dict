import 'package:flutter/foundation.dart';

import '../core/ai/ai_archive.dart';
import '../core/ai/ai_config.dart';
import '../core/ai/openai_client.dart';
import '../core/ai/passage_style.dart';
import '../core/ai/theme_agent.dart';
import '../core/ai/vocabulary_band.dart';
import '../core/frequency/frequency_service.dart';

/// State of the AI practice page: the two generators, their results, and the
/// archive kept under the open theme.
///
/// Every generation is archived as soon as it succeeds — asking twice for the
/// same word and losing the first answer is the failure mode this avoids.
/// Which generator a run belongs to.
enum AiRunKind { sentences, passage }

class AiPracticeProvider extends ChangeNotifier {
  AiPracticeProvider({
    AiArchiveStore? store,
    FrequencyService? frequency,
    ThemeAgent Function(OpenAiClient client)? agentBuilder,
  }) : _store = store ?? AiArchiveStore(),
       _frequency = frequency ?? FrequencyService(),
       _agentBuilder = agentBuilder;

  final AiArchiveStore _store;
  final FrequencyService _frequency;
  final ThemeAgent Function(OpenAiClient client)? _agentBuilder;

  String? _sceneId;
  bool _isGenerating = false;
  AiRunKind? _running;
  String? _error;
  List<GeneratedSentence> _sentences = const [];
  String? _sentencesWord;
  GeneratedPassage? _passage;
  List<String> _passageWords = const [];
  int _passageLength = 0;
  List<AiArchiveItem> _archive = const [];
  AiArchiveItem? _source;
  String? _reasoning;
  String? _rankedSceneId;
  List<String> _rankedSceneWords = const [];

  bool get isGenerating => _isGenerating;

  /// The open theme's vocabulary in COCA order. The band controls count in
  /// this order; the ranking is cached because it walks the whole theme.
  List<String> rankedWordsFor(String sceneId, Iterable<String> words) {
    if (_rankedSceneId != sceneId) {
      _rankedSceneId = sceneId;
      _rankedSceneWords = rankByFrequency(
        words,
        (word) => _frequency.getFrequency(word)?.rank,
      );
    }
    return _rankedSceneWords;
  }

  /// Which of the two generators is running, so only its own button reports
  /// progress and the other just goes quiet.
  AiRunKind? get running => _running;
  String? get error => _error;
  List<GeneratedSentence> get sentences => _sentences;
  String? get sentencesWord => _sentencesWord;
  GeneratedPassage? get passage => _passage;

  /// The words the last passage was required to use — shown so the reader can
  /// see which band of the theme it was built from.
  List<String> get passageWords => _passageWords;

  /// How long the last passage was asked to be, in words.
  int get passageLength => _passageLength;

  /// True when the model wrote well under the requested length.
  bool get passageShort {
    final passage = _passage;
    if (passage == null || _passageLength <= 0) return false;
    return passage.wordCount < _passageLength * 0.7;
  }
  List<AiArchiveItem> get archive => _archive;

  /// The archived item currently on screen, when it was loaded from the
  /// archive rather than generated just now.
  AiArchiveItem? get archiveSource => _source;

  /// The thinking the last generation came with, when the endpoint exposes it.
  String? get reasoning => _reasoning;

  List<AiArchiveItem> archiveFor(String sceneId) => [
    for (final item in _archive)
      if (item.sceneId == sceneId) item,
  ];

  /// Opens a theme: previous results belong to the theme they were made in.
  void openScene(String sceneId) {
    if (_sceneId == sceneId) return;
    _sceneId = sceneId;
    _sentences = const [];
    _sentencesWord = null;
    _passage = null;
    _passageWords = const [];
    _passageLength = 0;
    _source = null;
    _error = null;
    _reasoning = null;
    notifyListeners();
  }

  Future<void> loadArchive() async {
    _archive = await _store.ensureSeeded();
    notifyListeners();
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  Future<bool> generateSentences({
    required AiConfig config,
    required String sceneId,
    required String sceneLabel,
    required String word,
    required int count,
    required PracticeLevel level,
  }) => _run(AiRunKind.sentences, () async {
    final result = await _agent(
      config,
    ).sentences(word: word, count: count, level: level, sceneLabel: sceneLabel);
    _sentences = result.items;
    _sentencesWord = word;
    _reasoning = result.reasoning.isEmpty ? null : result.reasoning;
    await _archiveItem(
      AiArchiveItem(
        id: _newId(),
        sceneId: sceneId,
        sceneLabel: sceneLabel,
        kind: AiItemKind.sentences,
        level: level,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        model: config.model,
        word: word,
        lines: result.items,
        reasoning: result.reasoning,
      ),
    );
  });

  Future<bool> generatePassage({
    required AiConfig config,
    required String sceneId,
    required String sceneLabel,
    required String sceneHint,
    required List<String> requiredWords,
    required PracticeLevel level,
    int length = 140,
    PassageStyle style = PassageStyle.descriptive,
    String wordsNote = '',
    String extra = '',
  }) => _run(AiRunKind.passage, () async {
    final agent = _agent(config);
    final words = requiredWords;
    final result = await agent.passage(
      sceneLabel: sceneLabel,
      sceneHint: sceneHint,
      words: words,
      level: level,
      style: style,
      length: length,
      wordsNote: wordsNote,
      extra: extra,
    );
    _passage = result.passage;
    _passageWords = words;
    _passageLength = length;
    _reasoning = result.reasoning.isEmpty ? null : result.reasoning;
    await _archiveItem(
      AiArchiveItem(
        id: _newId(),
        sceneId: sceneId,
        sceneLabel: sceneLabel,
        kind: AiItemKind.passage,
        level: level,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        model: config.model,
        title: result.passage.title,
        text: result.passage.text,
        phrases: result.passage.phrases,
        words: words,
        length: length,
        style: style.name,
        reasoning: result.reasoning,
      ),
    );
  });

  /// Puts a saved generation back on the page exactly as it was when it was
  /// made: the same sentences or the same passage, the same reasoning, and the
  /// same target words.
  void showArchiveItem(AiArchiveItem item) {
    _error = null;
    _reasoning = item.reasoning.isEmpty ? null : item.reasoning;
    if (item.kind == AiItemKind.passage) {
      _passage = GeneratedPassage(
        title: item.title,
        text: item.text,
        phrases: item.phrases,
      );
      _passageWords = item.words;
      _passageLength = item.length;
      _sentences = const [];
      _sentencesWord = null;
    } else {
      _sentences = item.lines;
      _sentencesWord = item.word;
      _passage = null;
      _passageWords = const [];
    }
    _source = item;
    notifyListeners();
  }

  /// Drops the "loaded from the archive" banner, leaving the text in place.
  void clearSource() {
    if (_source == null) return;
    _source = null;
    notifyListeners();
  }

  Future<void> delete(String id) async {
    _archive = await _store.remove(id);
    notifyListeners();
  }

  /// One generation at a time: the button is the only way in, and two live
  /// requests would race into the same result fields.
  Future<bool> _run(AiRunKind kind, Future<void> Function() body) async {
    if (_isGenerating) return false;
    _isGenerating = true;
    _running = kind;
    _error = null;
    _source = null;
    notifyListeners();
    try {
      await body();
      return true;
    } on AiException catch (e) {
      _error = e.message;
      return false;
    } catch (e, stack) {
      // `Error` subclasses (ArgumentError, StateError…) are not `Exception`s;
      // letting one escape left the button doing visibly nothing at all.
      debugPrint('AI generation failed: $e\n$stack');
      _error = '生成失败：$e';
      return false;
    } finally {
      _isGenerating = false;
      _running = null;
      notifyListeners();
    }
  }

  Future<void> _archiveItem(AiArchiveItem item) async {
    _archive = await _store.add(item);
  }

  ThemeAgent _agent(AiConfig config) {
    final client = OpenAiClient(config: config);
    final builder = _agentBuilder;
    if (builder != null) return builder(client);
    return ThemeAgent(client: client);
  }

  static String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${_sequence++}';

  static int _sequence = 0;
}
