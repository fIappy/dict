import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_dict/core/ai/ai_config.dart';
import 'package:local_dict/core/ai/openai_client.dart';
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
    ThemeGroup(id: 'people', label: '人', words: ['coach']),
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

  testWidgets('the generate button reports progress while a request runs',
      (tester) async {
    final agent = _BlockingAgent();
    final provider = AiPracticeProvider(agentBuilder: (_) => agent);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
          ChangeNotifierProvider<AiPracticeProvider>.value(value: provider),
          ChangeNotifierProvider(create: (_) => EntrySpeechProvider()),
        ],
        child: const MaterialApp(home: AiPracticeScreen(scene: _scene)),
      ),
    );
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

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
          ChangeNotifierProvider<AiPracticeProvider>.value(value: provider),
          ChangeNotifierProvider(create: (_) => EntrySpeechProvider()),
        ],
        child: const MaterialApp(home: AiPracticeScreen(scene: _scene)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('生成句子'));
    await tester.pump();

    expect(find.textContaining('先输入一个要造句的单词'), findsOneWidget);
    expect(provider.isGenerating, isFalse);
  });
}
