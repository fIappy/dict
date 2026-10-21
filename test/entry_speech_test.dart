import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_dict/core/audio/pcm_audio.dart';
import 'package:local_dict/core/audio/piper_voice.dart';
import 'package:local_dict/core/audio/speech_clip_player.dart';
import 'package:local_dict/core/mdx/entry_speech.dart';
import 'package:local_dict/providers/entry_speech_provider.dart';

/// The shape SIO writes: a section header, then one `pg_exam` per line with the
/// 〔label〕, the Chinese gloss and the source book mixed into the markup.
const String _sioHtml = '''
<span class="tio_forvo">🔊 run</span>
<span class="pi"> run </span>
<span class="pg_phrase"> WORD PARTNERSHIP 词语搭配 </span><span class="comment" onclick="myFunction()">中文显隐</span>
<span class="pg_exam"><span class="pg_key">〔IN CHARGE OF〕</span>a drug counselling service that is<span class="pg_ht"> run </span>by ex-addicts <zh_cn name="xxx">由曾经的吸毒者经管的一家戒毒咨询服务机构<span class="pg_book">朗文写作活用</span></zh_cn></span>
<span class="pg_sentence"> DEFINITIVE EXAMPLES 权威例句</span><span class="comment">中文显隐</span>
<span class="pg_exam">Though his staff is often confused by the way he<span class="pg_ht"> runs </span>things, he is still a great boss.<zh_cn>尽管他手下常常搞不懂他的做事方式，但他仍是位好老板。<span class="pg_book">柯林斯高阶</span></zh_cn></span>
''';

/// Dictionary.com marks its examples with `ex` and no section header.
const String _dictionaryComHtml = '''
<h1 class="hw">run</h1>
<span class="pron">/rʌn/</span>
<div class="defs"><li>move at a speed faster than a walk
<span class="ex">She runs to school every morning.</span></li></div>
''';

class _RecordingPlayer implements SpeechClipPlayer {
  final List<String> sentences = [];
  final List<double> rates = [];
  final List<String> accents = [];
  final List<Uint8List> buffers = [];
  int stops = 0;
  bool supportsSentences = true;

  /// Called before each sentence is spoken, so a test can stop mid-run.
  void Function(int index)? onSpeak;

  @override
  Future<bool> speakSentence(String sentence,
      {String accent = 'us', double rate = 1.0}) async {
    onSpeak?.call(sentences.length);
    sentences.add(sentence);
    accents.add(accent);
    rates.add(rate);
    return supportsSentences;
  }

  /// Whether the player can actually sound a byte buffer. A platform whose
  /// backend cannot is what the fallback in the provider exists for.
  bool bytesPlayable = true;

  @override
  Future<bool> playAudioBytes(Uint8List bytes, {double rate = 1.0}) async {
    buffers.add(bytes);
    return bytesPlayable;
  }

  @override
  Future<void> playSpeechClip(String assetPath, {double rate = 1.0}) async {}

  @override
  Future<String?> sentenceVoiceLabel(String accent) async =>
      supportsSentences ? 'Test Voice' : null;

  @override
  Future<void> stop() async {
    stops++;
  }
}

class _StubPiper extends PiperVoice {
  _StubPiper({this.ready = true}) : super(finder: (accent) async => null);

  final bool ready;
  final List<String> rendered = [];
  final List<double> rates = [];

  @override
  Future<bool> isReady(String accent) async => ready;

  @override
  Future<PcmClip?> synthesize(String text,
      {required String accent, required double rate}) async {
    rendered.add(text);
    rates.add(rate);
    return PcmClip(Int16List.fromList(List.filled(2205, 3)), 22050);
  }
}

void main() {
  group('Entry speech lines', () {
    test('SIO sections become English-only phrases and sentences', () {
      final items = extractEntryUtterances(_sioHtml);

      expect(items, const [
        EntryUtterance(
          text: 'a drug counselling service that is run by ex-addicts',
          isPhrase: true,
        ),
        EntryUtterance(
          text: 'Though his staff is often confused by the way he runs things, '
              'he is still a great boss.',
          isPhrase: false,
        ),
      ]);
    });

    test('Dictionary.com examples are sentences', () {
      final items = extractEntryUtterances(_dictionaryComHtml);
      expect(items, const [
        EntryUtterance(
          text: 'She runs to school every morning.',
          isPhrase: false,
        ),
      ]);
    });

    test('the prepared html links each line to its index', () {
      final prepared = prepareEntrySpeech(_sioHtml);
      expect(prepared.utterances.length, 2);
      expect(prepared.html, contains('href="speech://0"'));
      expect(prepared.html, contains('href="speech://1"'));
      // The reader's own markup survives the rewrite.
      expect(prepared.html, contains('pg_phrase'));
      expect(prepared.html, contains('Though his staff is often confused'));
    });

    test('the same line from two books is spoken once', () {
      const html = '''
<span class="pg_sentence">DEFINITIVE EXAMPLES</span>
<span class="pg_exam">He runs a tight ship.<zh_cn>他管理有方。<span class="pg_book">朗文</span></zh_cn></span>
<span class="pg_exam">He runs a tight ship.<zh_cn>他治军甚严。<span class="pg_book">牛津</span></zh_cn></span>
''';
      expect(extractEntryUtterances(html).map((e) => e.text).toList(),
          ['He runs a tight ship.']);
    });

    test('Chinese-only lines, single words and empty markup yield nothing', () {
      expect(extractEntryUtterances(''), isEmpty);
      expect(
        extractEntryUtterances(
          '<span class="pg_exam"><zh_cn>只有中文</zh_cn></span>',
        ),
        isEmpty,
      );
      expect(
        extractEntryUtterances('<span class="pg_exam">running</span>'),
        isEmpty,
        reason: 'the headword itself is the pronunciation bar\'s job',
      );
    });
  });

  group('Entry speech playback', () {
    const lines = [
      EntryUtterance(text: 'in charge of', isPhrase: true),
      EntryUtterance(text: 'She runs to school every morning.', isPhrase: false),
    ];

    test('plays the lines in order with the slider value and the accent', () async {
      final player = _RecordingPlayer();
      final provider = EntrySpeechProvider(player: player, piper: _StubPiper(ready: false));

      await provider.playAll(lines,
          rate: 0.8, gap: Duration.zero, accent: 'uk');

      expect(player.sentences, lines.map((l) => l.text).toList());
      expect(player.rates, [0.8, 0.8]);
      expect(player.accents, ['uk', 'uk']);
      expect(provider.isPlaying, isFalse);
      expect(provider.currentIndex, isNull);
    });

    test('Piper reads the line when the model is there', () async {
      final player = _RecordingPlayer();
      final piper = _StubPiper();
      final provider = EntrySpeechProvider(player: player, piper: piper);

      await provider.playAll([lines.first],
          rate: 1.0, gap: Duration.zero, accent: 'us');

      expect(piper.rendered, ['in charge of']);
      expect(piper.rates, [1.0], reason: 'the slider value, not halved');
      expect(player.buffers, hasLength(1));
      expect(player.sentences, isEmpty, reason: 'the platform voice is not used');
    });

    test('stop drops the pending lines of a run in flight', () async {
      final player = _RecordingPlayer();
      final provider = EntrySpeechProvider(player: player, piper: _StubPiper(ready: false));
      player.onSpeak = (index) {
        if (index == 0) provider.stop();
      };

      await provider.playAll(lines,
          rate: 1.0, gap: Duration.zero, accent: 'us');

      expect(player.sentences, [lines.first.text]);
      expect(provider.isPlaying, isFalse);
      expect(player.stops, greaterThan(0));
    });

    test('playing one line stops whatever was running', () async {
      final player = _RecordingPlayer();
      final provider = EntrySpeechProvider(player: player, piper: _StubPiper(ready: false));

      await provider.playOne(lines.last,
          rate: 1.0, accent: 'us');

      expect(player.sentences, [lines.last.text]);
      expect(player.stops, greaterThan(0));
      expect(provider.isPlaying, isFalse);
    });

    test('a clip the player cannot sound falls back to the platform voice', () async {
      final player = _RecordingPlayer()..bytesPlayable = false;
      final provider = EntrySpeechProvider(player: player, piper: _StubPiper(ready: true));

      await provider.playOne(lines.first, rate: 1.0, accent: 'us');

      expect(player.buffers, isNotEmpty, reason: 'the Piper clip was tried first');
      expect(player.sentences, [lines.first.text],
          reason: 'the platform voice spoke instead of leaving silence');
    });

    test('a selection is spoken through the same voice', () async {
      final player = _RecordingPlayer();
      final provider = EntrySpeechProvider(player: player, piper: _StubPiper(ready: false));

      await provider.speakText('  A definition nobody tagged.  ',
          rate: 1.2, accent: 'uk');

      expect(player.sentences, ['A definition nobody tagged.'],
          reason: 'the selection is one utterance, trimmed');
      expect(player.rates.last, 1.2);
      expect(player.accents.last, 'uk');
      expect(provider.isPlaying, isFalse);
    });

    test('an empty selection says nothing', () async {
      final player = _RecordingPlayer();
      final provider = EntrySpeechProvider(player: player, piper: _StubPiper(ready: false));

      await provider.speakText('   ', rate: 1.0, accent: 'us');
      expect(player.sentences, isEmpty);
      expect(provider.isPlaying, isFalse);
    });

    test('en-GB settings read with the British voice', () {
      expect(accentForLanguage('en-US'), 'us');
      expect(accentForLanguage('en-GB'), 'uk');
      expect(accentForLanguage('zh-CN'), 'us');
    });
  });
}
