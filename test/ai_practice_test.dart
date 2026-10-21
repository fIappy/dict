import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:local_dict/core/ai/ai_archive.dart';
import 'package:local_dict/core/ai/ai_config.dart';
import 'package:local_dict/core/ai/openai_client.dart';
import 'package:local_dict/core/ai/theme_agent.dart';
import 'package:local_dict/providers/ai_practice_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Answers like a model would, without a model.
class _FakeAgent extends ThemeAgent {
  _FakeAgent({this.sentencesReply, this.passageReply})
      : super(
          client: OpenAiClient(
            config: const AiConfig(
              baseUrl: 'http://localhost/v1',
              apiKey: '',
              model: 'fake',
            ),
          ),
        );

  final List<GeneratedSentence>? sentencesReply;
  final GeneratedPassage? passageReply;
  PracticeLevel? lastLevel;
  List<String>? lastWords;

  @override
  Future<List<GeneratedSentence>> sentences({
    required String word,
    required int count,
    required PracticeLevel level,
    String? sceneLabel,
  }) async {
    lastLevel = level;
    return sentencesReply ?? [const GeneratedSentence(text: 'A fake sentence.')];
  }

  @override
  Future<GeneratedPassage> passage({
    required String sceneLabel,
    required String sceneHint,
    required List<String> words,
    required PracticeLevel level,
  }) async {
    lastLevel = level;
    lastWords = words;
    return passageReply ??
        const GeneratedPassage(title: 'Fake', text: 'A fake passage.');
  }
}

AiPracticeProvider _provider(_FakeAgent agent) => AiPracticeProvider(
      agentBuilder: (_) => agent,
    );

const _config = AiConfig(
  baseUrl: 'http://localhost/v1',
  apiKey: 'test-key',
  model: 'fake',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('archive', () {
    test('saved items come back newest first', () async {
      final store = AiArchiveStore();
      await store.add(const AiArchiveItem(
        id: 'old',
        sceneId: 'medical',
        sceneLabel: '医疗健康',
        kind: AiItemKind.sentences,
        level: PracticeLevel.easy,
        createdAt: 1000,
        model: 'm',
        word: 'ward',
        lines: [GeneratedSentence(text: 'One.')],
      ));
      final items = await store.add(const AiArchiveItem(
        id: 'new',
        sceneId: 'medical',
        sceneLabel: '医疗健康',
        kind: AiItemKind.passage,
        level: PracticeLevel.hard,
        createdAt: 2000,
        model: 'm',
        title: 'Title',
        text: 'Body.',
      ));

      expect(items.map((i) => i.id), ['new', 'old']);
      final reloaded = await AiArchiveStore().load();
      expect(reloaded.map((i) => i.id), ['new', 'old']);
      expect(reloaded.first.text, 'Body.');
      expect(reloaded.last.lines.single.text, 'One.');
    });

    test('delete removes only the asked item', () async {
      final store = AiArchiveStore();
      for (final id in ['a', 'b']) {
        await store.add(AiArchiveItem(
          id: id,
          sceneId: 's',
          sceneLabel: 'S',
          kind: AiItemKind.passage,
          level: PracticeLevel.easy,
          createdAt: id == 'a' ? 1 : 2,
          model: 'm',
          text: id,
        ));
      }
      final left = await store.remove('a');
      expect(left.map((i) => i.id), ['b']);
    });

    test('a corrupted document reads as empty', () async {
      SharedPreferences.setMockInitialValues({'ai_archive_v1': '{not json'});
      expect(await AiArchiveStore().load(), isEmpty);
    });
  });

  group('provider', () {
    test('a successful generation is archived under its theme', () async {
      final agent = _FakeAgent(
        sentencesReply: [const GeneratedSentence(text: 'He ran home.')],
      );
      final provider = _provider(agent);

      final ok = await provider.generateSentences(
        config: _config,
        sceneId: 'sports',
        sceneLabel: '体育运动',
        word: 'run',
        count: 3,
        level: PracticeLevel.easy,
      );

      expect(ok, isTrue);
      expect(provider.sentences.single.text, 'He ran home.');
      expect(provider.sentencesWord, 'run');
      final archived = provider.archiveFor('sports');
      expect(archived, hasLength(1));
      expect(archived.single.word, 'run');
      expect(archived.single.lines.single.text, 'He ran home.');

      // And it survives a reload, which is the whole point of archiving.
      final reloaded = AiPracticeProvider();
      await reloaded.loadArchive();
      expect(reloaded.archiveFor('sports').single.word, 'run');
    });

    test('a passage is stored with the words it was built from', () async {
      final agent = _FakeAgent(
        passageReply: const GeneratedPassage(title: 'Night Shift', text: 'Body.'),
      );
      final provider = _provider(agent);

      final ok = await provider.generatePassage(
        config: _config,
        sceneId: 'medical',
        sceneLabel: '医疗健康',
        sceneHint: '医院、诊疗',
        sceneWords: const ['ward', 'nurse', 'suture', 'stethoscope', 'clinic'],
        level: PracticeLevel.hard,
        wordCount: 3,
      );

      expect(ok, isTrue);
      expect(provider.passage?.title, 'Night Shift');
      expect(provider.passageWords, hasLength(3));
      expect(agent.lastLevel, PracticeLevel.hard);
      expect(provider.archiveFor('medical').single.title, 'Night Shift');
      expect(provider.archiveFor('medical').single.level, PracticeLevel.hard);
    });

    test('a failed generation keeps the error and archives nothing', () async {
      final provider = AiPracticeProvider(
        agentBuilder: (_) => _ThrowingAgent(),
      );

      final ok = await provider.generateSentences(
        config: _config,
        sceneId: 'sports',
        sceneLabel: '体育运动',
        word: 'run',
        count: 3,
        level: PracticeLevel.easy,
      );

      expect(ok, isFalse);
      expect(provider.error, contains('限流'));
      expect(provider.archiveFor('sports'), isEmpty);
      expect(provider.isGenerating, isFalse);
    });

    test('opening another theme drops the previous results', () async {
      final provider = _provider(_FakeAgent());
      await provider.generateSentences(
        config: _config,
        sceneId: 'a',
        sceneLabel: 'A',
        word: 'x',
        count: 3,
        level: PracticeLevel.easy,
      );
      provider.openScene('b');
      expect(provider.sentences, isEmpty, reason: 'results belong to their theme');
      expect(provider.passage, isNull);
      expect(provider.archiveFor('a'), hasLength(1),
          reason: 'archived work stays available when the theme is reopened');
    });
  });

  group('client', () {
    test('reads the assistant text out of the standard envelope', () async {
      final client = OpenAiClient(
        config: _config,
        httpClient: MockClient((request) async {
          expect(request.headers['Authorization'], 'Bearer test-key');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['model'], 'fake');
          expect(body['messages'], hasLength(2));
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {'role': 'assistant', 'content': 'Hello.'}
                }
              ]
            }),
            200,
          );
        }),
      );

      expect(
        await client.complete(system: 's', user: 'u'),
        'Hello.',
      );
    });

    test('a rejected key is reported as such, not as a stack trace', () async {
      final client = OpenAiClient(
        config: _config,
        httpClient: MockClient((_) async => http.Response(
              jsonEncode({
                'error': {'message': 'Invalid API key'}
              }),
              401,
            )),
      );

      await expectLater(
        client.complete(system: 's', user: 'u'),
        throwsA(isA<AiException>().having(
            (e) => e.message, 'message', contains('鉴权失败'))),
      );
    });

    test('an unparseable body is reported', () async {
      final client = OpenAiClient(
        config: _config,
        httpClient: MockClient((_) async => http.Response('<html>oops</html>', 200)),
      );
      await expectLater(
        client.complete(system: 's', user: 'u'),
        throwsA(isA<AiException>()),
      );
    });

    test('an unconfigured config refuses before dialling out', () async {
      final client = OpenAiClient(
        config: const AiConfig(baseUrl: '', apiKey: '', model: ''),
        httpClient: MockClient((_) async => fail('must not call the network')),
      );
      await expectLater(
        client.complete(system: 's', user: 'u'),
        throwsA(isA<AiException>()),
      );
    });

    test('the endpoint is normalised', () {
      const base = AiConfig(baseUrl: 'https://x.test/v1/', apiKey: '', model: 'm');
      expect(base.chatCompletionsUrl, 'https://x.test/v1/chat/completions');
      const full =
          AiConfig(baseUrl: 'https://x.test/v1/chat/completions', apiKey: '', model: 'm');
      expect(full.chatCompletionsUrl, 'https://x.test/v1/chat/completions');
    });
  });
}

class _ThrowingAgent extends ThemeAgent {
  _ThrowingAgent()
      : super(
          client: OpenAiClient(
            config: const AiConfig(baseUrl: 'http://localhost/v1', apiKey: '', model: 'x'),
          ),
        );

  @override
  Future<List<GeneratedSentence>> sentences({
    required String word,
    required int count,
    required PracticeLevel level,
    String? sceneLabel,
  }) async =>
      throw const AiException('触发限流（429）：稍后再试');
}
