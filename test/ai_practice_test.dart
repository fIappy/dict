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
  String reasoningText = '';

  @override
  Future<({List<GeneratedSentence> items, String reasoning})> sentences({
    required String word,
    required int count,
    required PracticeLevel level,
    String? sceneLabel,
  }) async {
    lastLevel = level;
    return (
      items: sentencesReply ?? [const GeneratedSentence(text: 'A fake sentence.')],
      reasoning: reasoningText,
    );
  }

  @override
  Future<({GeneratedPassage passage, String reasoning})> passage({
    required String sceneLabel,
    required String sceneHint,
    required List<String> words,
    required PracticeLevel level,
  }) async {
    lastLevel = level;
    lastWords = words;
    return (
      passage: passageReply ??
          const GeneratedPassage(title: 'Fake', text: 'A fake passage.'),
      reasoning: reasoningText,
    );
  }
}


http.Response _ok(String content, {String? reasoning}) => http.Response(
      jsonEncode({
        'id': 'chatcmpl-1',
        'object': 'chat.completion',
        'created': 0,
        'model': 'fake',
        'choices': [
          {
            'index': 0,
            'finish_reason': 'stop',
            'message': {
              'role': 'assistant',
              'content': content,
              'reasoning_content': ?reasoning,
            },
          },
        ],
      }),
      200,
    );

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


    test('the reasoning is kept with the result and the archive entry', () async {
      final agent = _FakeAgent(
        sentencesReply: [const GeneratedSentence(text: 'X.')],
      )..reasoningText = 'weighed two senses of the word';
      final provider = _provider(agent);

      await provider.generateSentences(
        config: _config,
        sceneId: 's',
        sceneLabel: 'S',
        word: 'x',
        count: 3,
        level: PracticeLevel.easy,
      );

      expect(provider.reasoning, 'weighed two senses of the word');
      expect(provider.archiveFor('s').single.reasoning,
          'weighed two senses of the word');
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

  group('restoring a saved generation', () {
    test('the passage keeps its phrases, words and reasoning on disk', () async {
      final agent = _FakeAgent(
        passageReply: const GeneratedPassage(
          title: 'Match day',
          text: 'The coach asked us to take care of the ball.',
          phrases: ['take care of'],
        ),
      )..reasoningText = 'stuck to the theme';
      final provider = _provider(agent);

      await provider.generatePassage(
        config: _config,
        sceneId: 'sports',
        sceneLabel: '体育运动',
        sceneHint: '比赛',
        sceneWords: const ['coach', 'match', 'team'],
        level: PracticeLevel.easy,
      );

      final reloaded = (await AiArchiveStore().load()).single;
      expect(reloaded.title, 'Match day');
      expect(reloaded.phrases, ['take care of']);
      expect(reloaded.words, agent.lastWords);
      expect(reloaded.words, isNotEmpty);
      expect(reloaded.reasoning, 'stuck to the theme');
    });

    test('an archived passage is put back on the page as it was made', () async {
      final agent = _FakeAgent(
        passageReply: const GeneratedPassage(
          title: 'Match day',
          text: 'The coach asked us to take care of the ball.',
          phrases: ['take care of'],
        ),
      )..reasoningText = 'stuck to the theme';
      final provider = _provider(agent);
      await provider.generatePassage(
        config: _config,
        sceneId: 'sports',
        sceneLabel: '体育运动',
        sceneHint: '比赛',
        sceneWords: const ['coach', 'match', 'team'],
        level: PracticeLevel.medium,
      );
      final item = provider.archiveFor('sports').single;

      provider.openScene('other');
      expect(provider.passage, isNull);

      provider.showArchiveItem(item);

      expect(provider.passage?.title, 'Match day');
      expect(provider.passage?.phrases, ['take care of']);
      expect(provider.passageWords, agent.lastWords);
      expect(provider.reasoning, 'stuck to the theme');
      expect(provider.archiveSource?.id, item.id);
      expect(provider.sentences, isEmpty,
          reason: 'the page shows the item, not a mix of both kinds');
    });

    test('an archived sentence set comes back with its phrases and word',
        () async {
      final agent = _FakeAgent(
        sentencesReply: [
          const GeneratedSentence(
            text: 'The coach told us to take care of the ball.',
            translation: '教练让我们看好球。',
            phrases: ['take care of'],
          ),
        ],
      );
      final provider = _provider(agent);
      await provider.generateSentences(
        config: _config,
        sceneId: 'sports',
        sceneLabel: '体育运动',
        word: 'coach',
        count: 3,
        level: PracticeLevel.hard,
      );
      final item = provider.archiveFor('sports').single;

      provider.openScene('other');
      expect(provider.sentences, isEmpty);

      provider.showArchiveItem(item);

      expect(provider.sentencesWord, 'coach');
      expect(provider.sentences.single.phrases, ['take care of']);
      expect(provider.sentences.single.translation, '教练让我们看好球。');
      expect(provider.passage, isNull);
    });

    test('a new generation drops the archive banner', () async {
      final provider = _provider(_FakeAgent());
      await provider.generateSentences(
        config: _config,
        sceneId: 'sports',
        sceneLabel: '体育运动',
        word: 'coach',
        count: 3,
        level: PracticeLevel.easy,
      );
      provider.showArchiveItem(provider.archiveFor('sports').single);
      expect(provider.archiveSource, isNotNull);

      await provider.generateSentences(
        config: _config,
        sceneId: 'sports',
        sceneLabel: '体育运动',
        word: 'team',
        count: 3,
        level: PracticeLevel.easy,
      );

      expect(provider.archiveSource, isNull);
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

      final reply = await client.complete(system: 's', user: 'u');
      expect(reply.text, 'Hello.');
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


    test('reasoning comes back with the answer', () async {
      final client = OpenAiClient(
        config: _config,
        httpClient: MockClient(
          (_) async => _ok('Hello.', reasoning: 'First I read the theme.'),
        ),
      );

      final reply = await client.complete(system: 's', user: 'u');
      expect(reply.text, 'Hello.');
      expect(reply.reasoning, contains('First I read the theme'));
    });

    test('the configured reasoning effort is sent', () async {
      Map<String, dynamic>? body;
      final client = OpenAiClient(
        config: const AiConfig(
          baseUrl: 'http://localhost/v1',
          apiKey: 'k',
          model: 'm',
          reasoningEffort: AiReasoningEffort.medium,
        ),
        httpClient: MockClient((request) async {
          body = jsonDecode(request.body) as Map<String, dynamic>;
          return _ok('Hi.');
        }),
      );

      await client.complete(system: 's', user: 'u');
      expect(body!['reasoning_effort'], 'medium');
    });

    test('a server that rejects the effort is asked again without it', () async {
      final bodies = <Map<String, dynamic>>[];
      final client = OpenAiClient(
        config: _config,
        httpClient: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          bodies.add(body);
          if (bodies.length == 1) {
            return http.Response(
              jsonEncode({
                'error': {'message': 'Unsupported parameter: reasoning_effort'},
              }),
              400,
            );
          }
          return _ok('Fine.');
        }),
      );

      final reply = await client.complete(system: 's', user: 'u');
      expect(bodies, hasLength(2));
      expect(bodies.first['reasoning_effort'], 'low');
      expect(bodies.last.containsKey('reasoning_effort'), isFalse);
      expect(reply.text, 'Fine.');
    });

    test('models come from the endpoint, sorted', () async {
      final client = OpenAiClient(
        config: _config,
        httpClient: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/v1/models');
          return http.Response(
            jsonEncode({
              'object': 'list',
              'data': [
                {'id': 'model-b', 'object': 'model', 'created': 0, 'owned_by': 'x'},
                {'id': 'model-a', 'object': 'model', 'created': 0, 'owned_by': 'x'},
              ],
            }),
            200,
          );
        }),
      );

      expect(await client.listModels(), ['model-a', 'model-b']);
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
  Future<({List<GeneratedSentence> items, String reasoning})> sentences({
    required String word,
    required int count,
    required PracticeLevel level,
    String? sceneLabel,
  }) async =>
      throw const AiException('触发限流（429）：稍后再试');
}
