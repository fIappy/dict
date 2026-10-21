import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_dict/core/ai/ai_config.dart';
import 'package:local_dict/core/ai/openai_client.dart';
import 'package:local_dict/core/ai/passage_style.dart';
import 'package:local_dict/core/ai/theme_agent.dart';
import 'package:local_dict/core/themes/theme_service.dart';
import 'package:local_dict/providers/ai_practice_provider.dart';
import 'package:local_dict/providers/entry_speech_provider.dart';
import 'package:local_dict/providers/settings_provider.dart';
import 'package:local_dict/ui/screens/ai_practice_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _scene = ThemeScene(
  id: 'sports',
  label: '体育运动',
  hint: '比赛与训练',
  count: 1,
  groups: [
    ThemeGroup(
      id: 'people',
      label: '人',
      words: ['coach', 'match', 'team', 'referee'],
    ),
  ],
);

/// Answers only when the test says so, which is how a slow endpoint looks from
/// the UI's side.
class _BlockingAgent extends ThemeAgent {
  _BlockingAgent()
      : super(
          client: OpenAiClient(
            config: const AiConfig(
              baseUrl: 'http://localhost/v1',
              apiKey: '',
              model: 'm',
            ),
          ),
        );

  final Completer<void> _gate = Completer<void>();

  void finish() => _gate.complete();

  @override
  Future<({List<GeneratedSentence> items, String reasoning})> sentences({
    required String word,
    required int count,
    required PracticeLevel level,
    String? sceneLabel,
  }) async {
    await _gate.future;
    return (items: [const GeneratedSentence(text: 'A sentence.')], reasoning: '');
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('theme words are red and collocations are underlined',
      (tester) async {
    final provider = AiPracticeProvider(agentBuilder: (_) => _MarksAgent());
    await _mount(tester, provider);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'coach');
    await tester.tap(find.text('生成句子'));
    await tester.pumpAndSettle();

    _expectMarks(_annotated(tester, 'take care of'));
  });

  testWidgets('passage settings reach the request', (tester) async {
    final agent = _PassageAgent();
    final provider = AiPracticeProvider(agentBuilder: (_) => agent);
    await _mount(tester, provider);
    await tester.pumpAndSettle();

    // The stored default seeds the field.
    expect(find.widgetWithText(TextField, '140'), findsOneWidget);

    await tester.ensureVisible(find.text('幽默型'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('幽默型'));
    await tester.pump();

    await tester.ensureVisible(find.byType(TextField).at(1));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(1), '5000');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    // The whole theme is required until the band is narrowed.
    expect(find.textContaining('排名 1–4 / 共 4'), findsOneWidget);

    await tester.ensureVisible(find.text('生成短文'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('生成短文'));
    await tester.pumpAndSettle();

    expect(agent.lastStyle, PassageStyle.humorous);
    expect(agent.lastLength, 5000);
    expect(agent.lastWords, ['coach', 'match', 'team', 'referee']);
    expect(agent.lastNote, contains('ranks 1-4 of 4'));
    expect(find.text('Night Shift'), findsOneWidget);
  });

  testWidgets('a band wider than the passage can hold says so', (tester) async {
    final agent = _PassageAgent();
    final provider = AiPracticeProvider(agentBuilder: (_) => agent);
    await _mount(tester, provider);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('词汇区间与追加要求'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('词汇区间与追加要求'));
    await tester.pumpAndSettle();

    // The whole theme fits in the default 140-word passage.
    expect(find.textContaining('区间 4 词 · 要 4 词'), findsOneWidget);
    expect(find.textContaining('全部要求出现'), findsOneWidget);

    // Twenty words can only carry three of them; the count must say why.
    await tester.enterText(find.byType(TextField).at(1), '20');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.textContaining('区间 4 词 · 要 3 词'), findsOneWidget);
    expect(find.textContaining('已从区间里等距抽取'), findsOneWidget);

    await tester.ensureVisible(find.text('生成短文'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('生成短文'));
    await tester.pumpAndSettle();
    expect(agent.lastWords, hasLength(3));
  });

  testWidgets('an archived generation is shown on the main page again',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'ai_archive_v1':
          '[{"id":"a1","sceneId":"sports","sceneLabel":"体育运动","kind":"sentences",'
              '"level":"easy","createdAt":1750000000000,"model":"m","word":"coach",'
              '"lines":[{"text":"The coach called the team.","translation":"教练喊了队伍。"}]}]',
    });
    final provider = AiPracticeProvider(agentBuilder: (_) => _BlockingAgent());
    await _mount(tester, provider);
    await tester.pumpAndSettle();

    expect(provider.sentences, isEmpty, reason: 'nothing generated yet');
    expect(find.textContaining('来自归档'), findsNothing);

    await tester.dragUntilVisible(
      find.text('coach · 1 句'),
      find.byType(ListView).first,
      const Offset(0, -160),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('coach · 1 句'));
    await tester.pumpAndSettle();

    expect(provider.sentencesWord, 'coach');
    expect(provider.archiveSource?.id, 'a1');
    expect(find.textContaining('来自归档'), findsOneWidget);
    expect(_annotated(tester, 'The coach called the team.').textSpan, isNotNull);
  });

  testWidgets('the generate button reports progress while a request runs',
      (tester) async {
    final agent = _BlockingAgent();
    final provider = AiPracticeProvider(agentBuilder: (_) => agent);

    await _mount(tester, provider);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'coach');
    await tester.tap(find.text('生成句子'));
    await tester.pump();

    // A slow endpoint used to look like a dead button: the only feedback was a
    // two-pixel bar at the very top of the page.
    expect(find.text('生成中…'), findsOneWidget);
    expect(find.text('生成句子'), findsNothing);
    expect(provider.isGenerating, isTrue);

    agent.finish();
    await tester.pumpAndSettle();
    expect(find.text('生成句子'), findsOneWidget);
    expect(find.text('A sentence.'), findsOneWidget);
  });

  testWidgets('an empty word says what to do instead of doing nothing',
      (tester) async {
    final provider = AiPracticeProvider(agentBuilder: (_) => _BlockingAgent());

    await _mount(tester, provider);
    await tester.pumpAndSettle();

    await tester.tap(find.text('生成句子'));
    await tester.pump();

    expect(find.textContaining('先输入一个要造句的单词'), findsOneWidget);
    expect(provider.isGenerating, isFalse);
  });
}

/// Records what the passage request carried.
class _PassageAgent extends _BlockingAgent {
  PassageStyle? lastStyle;
  int? lastLength;
  List<String>? lastWords;
  String lastNote = '';
  String lastExtra = '';

  @override
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
    lastStyle = style;
    lastLength = length;
    lastWords = words;
    lastNote = wordsNote;
    lastExtra = extra;
    return (
      passage: const GeneratedPassage(
        title: 'Night Shift',
        text: 'The coach walked in and the team stood up.',
        phrases: ['walked in'],
      ),
      reasoning: '',
    );
  }
}

/// A model answer that uses a theme word and a collocation.
class _MarksAgent extends _BlockingAgent {
  _MarksAgent() : super();

  @override
  Future<({List<GeneratedSentence> items, String reasoning})> sentences({
    required String word,
    required int count,
    required PracticeLevel level,
    String? sceneLabel,
  }) async => (
        items: [
          const GeneratedSentence(
            text: 'The coach told us to take care of the ball.',
            translation: '教练让我们看好球。',
            phrases: ['take care of'],
          ),
        ],
        reasoning: '',
      );
}

SelectableText _annotated(WidgetTester tester, String fragment) => tester
    .widgetList<SelectableText>(find.byType(SelectableText))
    .firstWhere((w) => w.textSpan?.toPlainText().contains(fragment) ?? false);

void _expectMarks(SelectableText widget) {
  final spans = widget.textSpan!.children!.cast<TextSpan>();
  final red = spans.firstWhere((s) => s.text == 'coach');
  final phrase = spans.firstWhere((s) => s.text == 'take care of');
  expect(red.style?.color, isNotNull,
      reason: 'theme words carry their own colour');
  expect(phrase.style?.decoration, TextDecoration.underline,
      reason: 'collocations are underlined');
}

Future<void> _mount(WidgetTester tester, AiPracticeProvider provider) {
  return tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider<AiPracticeProvider>.value(value: provider),
        ChangeNotifierProvider(create: (_) => EntrySpeechProvider()),
      ],
      child: const MaterialApp(home: AiPracticeScreen(scene: _scene)),
    ),
  );
}
