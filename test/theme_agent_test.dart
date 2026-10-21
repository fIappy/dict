import 'package:flutter_test/flutter_test.dart';
import 'package:local_dict/core/ai/ai_config.dart';
import 'package:local_dict/core/ai/openai_client.dart';
import 'package:local_dict/core/ai/theme_agent.dart';

/// Captures the prompt instead of calling a server, and answers with a canned
/// reply. Lets the prompt itself be asserted.
class _CapturingClient extends OpenAiClient {
  _CapturingClient({this.reply = '{}'})
      : super(
          config: const AiConfig(
            baseUrl: 'http://127.0.0.1:11434/v1',
            apiKey: '',
            model: 'test-model',
          ),
        );

  final String reply;
  String system = '';
  String user = '';

  @override
  Future<String> complete({
    required String system,
    required String user,
    double temperature = 0.7,
    int? maxTokens,
  }) async {
    this.system = system;
    this.user = user;
    return reply;
  }
}

ThemeAgent _agent(OpenAiClient client) => ThemeAgent(client: client);

void main() {
  group('word bands', () {
    final ranked = [
      const RankedWord('the', 1), // stopword
      const RankedWord('time', 50),
      const RankedWord('travel', 900),
      const RankedWord('itinerary', 12000),
      const RankedWord('peregrination', 30000),
      const RankedWord('travel', 900), // duplicate
      const RankedWord('go', 30), // shorter than three letters
    ];

    test('easy takes the most frequent words and skips grammar words', () {
      expect(ThemeAgent.pickWords(ranked, PracticeLevel.easy, 2),
          ['time', 'travel']);
    });

    test('hard takes the rarest words', () {
      expect(ThemeAgent.pickWords(ranked, PracticeLevel.hard, 2),
          ['itinerary', 'peregrination']);
    });

    test('medium sits between the two', () {
      final picked = ThemeAgent.pickWords(ranked, PracticeLevel.medium, 2);
      expect(picked, ['travel', 'itinerary']);
    });

    test('a band wider than the pool returns the pool', () {
      expect(ThemeAgent.pickWords(ranked, PracticeLevel.easy, 99),
          ['time', 'travel', 'itinerary', 'peregrination']);
    });

    test('an empty pool yields nothing', () {
      expect(ThemeAgent.pickWords(const [], PracticeLevel.easy, 4), isEmpty);
    });
  });

  group('prompts', () {
    test('the sentence prompt carries the word, the count and the level', () async {
      final client = _CapturingClient(reply: '{"sentences":[{"text":"ok."}]}');
      final agent = _agent(client);

      await agent.sentences(
        word: 'run',
        count: 5,
        level: PracticeLevel.hard,
        sceneLabel: '体育运动',
      );

      expect(client.user, contains('"run"'));
      expect(client.user, contains('exactly 5'));
      expect(client.user, contains('hard'));
      expect(client.user, contains('体育运动'));
      expect(client.system.toLowerCase(), contains('idiomatic'));
      expect(client.system, contains('JSON only'));
    });

    test('the passage prompt lists the words it must cover', () async {
      final client = _CapturingClient(
        reply: '{"title":"A Walk","text":"Some text."}',
      );
      final agent = _agent(client);

      final passage = await agent.passage(
        sceneLabel: '旅行住宿',
        sceneHint: '酒店、行程与交通',
        words: const ['itinerary', 'lounge'],
        level: PracticeLevel.easy,
      );

      expect(client.user, contains('旅行住宿'));
      expect(client.user, contains('itinerary, lounge'));
      expect(client.user, contains('at least 80%'));
      expect(passage.title, 'A Walk');
      expect(passage.text, 'Some text.');
    });
  });

  group('parsing', () {
    test('plain JSON sentences', () {
      final out = ThemeAgent.parseSentences(
          '{"sentences":[{"text":"A cat sat.","translation":"猫坐着。"}]}');
      expect(out, hasLength(1));
      expect(out.single.text, 'A cat sat.');
      expect(out.single.translation, '猫坐着。');
    });

    test('code fences and surrounding prose are tolerated', () {
      final out = ThemeAgent.parseSentences(
          'Here you go:\n```json\n{"sentences":[{"text":"A cat sat."}]}\n```\nHope this helps.');
      expect(out.single.text, 'A cat sat.');
    });

    test('a bare array is accepted', () {
      final out = ThemeAgent.parseSentences('["First one.", "Second one."]');
      expect(out.map((s) => s.text), ['First one.', 'Second one.']);
    });

    test('duplicates and blanks are dropped', () {
      final out = ThemeAgent.parseSentences(
          '{"sentences":[{"text":"Same."},{"text":"same."},{"text":"  "}]}');
      expect(out.map((s) => s.text), ['Same.']);
    });

    test('garbage throws instead of pretending', () {
      expect(() => ThemeAgent.parseSentences('not json at all'),
          throwsA(isA<AiException>()));
      expect(() => ThemeAgent.parsePassage('nope'),
          throwsA(isA<AiException>()));
    });

    test('a brace in the prose does not derail the payload', () {
      final out = ThemeAgent.parseSentences(
          'Sure. (Note: {this} is not JSON.) {"sentences":[{"text":"Ok."}]}');
      expect(out.single.text, 'Ok.');
    });

    test('two answers in a row: the first valid one wins', () {
      final out = ThemeAgent.parseSentences(
          '{"sentences":[{"text":"First."}]}\n{"sentences":[{"text":"Second."}]}');
      expect(out.single.text, 'First.');
    });

    test('full-width braces from a chatty model are tolerated', () {
      final out = ThemeAgent.parseSentences(
          '好的：｛"sentences":［｛"text":"Full width."｝］｝');
      expect(out.single.text, 'Full width.');
    });

    test('a single sentence object is not thrown away', () {
      final out = ThemeAgent.parseSentences('{"text":"Solo.","translation":"单独。"}');
      expect(out.single.text, 'Solo.');
      expect(out.single.translation, '单独。');
    });

    test('braces inside strings do not break the scan', () {
      final out = ThemeAgent.parseSentences(
          r'{"sentences":[{"text":"He wrote {\"hi\"} on it."}]}');
      expect(out.single.text, 'He wrote {"hi"} on it.');
    });

    test('the failure message shows what the endpoint actually said', () {
      expect(
        () => ThemeAgent.parseSentences('Sorry, I cannot help with that.'),
        throwsA(isA<AiException>().having(
            (e) => e.message, 'message', contains('Sorry, I cannot help'))),
      );
    });

    test('a passage may be keyed text or passage', () {
      expect(ThemeAgent.parsePassage('{"title":"T","text":"Body."}').text,
          'Body.');
      expect(ThemeAgent.parsePassage('{"passage":"Body."}').text, 'Body.');
      expect(ThemeAgent.parsePassage('{"passage":"Body."}').title, 'Untitled');
    });
  });
}
