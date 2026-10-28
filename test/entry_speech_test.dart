import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_dict/core/audio/pcm_audio.dart';
import 'package:local_dict/core/audio/kokoro_voice.dart';
import 'package:local_dict/core/audio/speech_engine.dart';
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

  /// When set, each sentence waits for it — the test's way of being inside a
  /// line when it pauses.
  Completer<void>? gate;

  /// Whether the player can actually sound a byte buffer. A platform whose
  /// backend cannot is what the fallback in the provider exists for.
  bool bytesPlayable = true;

  /// Called after each buffer starts, so a test can stop a looping run.
  void Function(int played)? onBuffer;

  @override
  Future<bool> playAudioBytes(Uint8List bytes, {double rate = 1.0}) async {
    buffers.add(bytes);
    onBuffer?.call(buffers.length);
    return bytesPlayable;
  }

  @override
  Future<void> playSpeechClip(String assetPath, {double rate = 1.0}) async {}


  @override
  Future<void> setVolume(double volume) async => this.volume = volume;

  double volume = 1.0;

  @override
  Future<bool> speakSentence(String sentence,
      {String accent = 'us', double rate = 1.0}) async {
    sentences.add(sentence);
    accents.add(accent);
    rates.add(rate);
    return true;
  }

  @override
  Future<String?> sentenceVoiceLabel(String accent) async => 'Test Voice';
  @override
  Future<void> stop() async {
    stops++;
  }
}

/// A Kokoro that renders everything except [bad], which it cannot.
class _PartialKokoro extends _StubKokoro {
  _PartialKokoro(this.bad);

  final String bad;

  @override
  Future<PcmClip?> synthesize(String text,
      {required String accent, required double rate}) async {
    rendered.add(text);
    rates.add(rate);
    if (text == bad) return null;
    return PcmClip(Int16List.fromList(List.filled(2205, 3)), 22050);
  }
}

/// A player whose byte playback can be held, and which reports the clip as
/// never having sounded when it is released after a stop (what a real player
/// does).
class _GatedPlayer extends _RecordingPlayer {
  Completer<void>? _gate;
  bool _stopped = false;

  void hold() {
    _gate = Completer<void>();
    _stopped = false;
  }

  void release() {
    _gate?.complete();
    _gate = null;
  }

  @override
  Future<void> stop() async {
    _stopped = true;
    await super.stop();
  }

  @override
  Future<bool> playAudioBytes(Uint8List bytes, {double rate = 1.0}) async {
    buffers.add(bytes);
    final gate = _gate;
    if (gate != null) await gate.future;
    // A clip cut short by a stop never sounded; the next one plays normally.
    final sounded = !_stopped;
    _stopped = false;
    return sounded;
  }
}

/// A player that holds chosen playbacks, so a repeat can be requested while a
/// line is sounding.
class _GateQueuePlayer extends _RecordingPlayer {
  final List<Completer<void>> _gates = [];

  /// The gate a playback is currently waiting on (already taken off the queue).
  Completer<void>? _held;

  void holdNext() => _gates.add(Completer<void>());

  void releaseNext() {
    // The playback already waiting on a gate comes first: a later holdNext()
    // queues the gate for the *next* line.
    final held = _held;
    if (held != null && !held.isCompleted) {
      held.complete();
      return;
    }
    if (_gates.isNotEmpty) {
      final gate = _gates.removeAt(0);
      if (!gate.isCompleted) gate.complete();
    }
  }

  void releaseAll() {
    while (_gates.isNotEmpty) {
      releaseNext();
    }
    releaseNext();
  }

  @override
  Future<bool> playAudioBytes(Uint8List bytes, {double rate = 1.0}) async {
    buffers.add(bytes);
    if (_gates.isNotEmpty) {
      _held = _gates.removeAt(0);
      await _held!.future;
      _held = null;
    }
    return true;
  }
}

class _StubKokoro extends KokoroVoice {
  _StubKokoro({this.ready = true}) : super(finder: () async => null);

  final bool ready;
  final List<String> rendered = [];
  final List<double> rates = [];

  /// Held by a test that wants to sit inside a line.
  Completer<void>? gate;

  /// Called before each line is rendered.
  void Function(int index)? onRender;

  @override
  Future<bool> isReady() async => ready;

  @override
  Future<PcmClip?> synthesize(String text,
      {required String accent, required double rate}) async {
    onRender?.call(rendered.length);
    rendered.add(text);
    rates.add(rate);
    final waiting = gate;
    if (waiting != null) await waiting.future;
    return PcmClip(Int16List.fromList(List.filled(2205, 3)), 24000);
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

    test('plays the lines in order with the slider value', () async {
      final player = _RecordingPlayer();
      final kokoro = _StubKokoro();
      final provider = EntrySpeechProvider(player: player, kokoro: kokoro);

      await provider.playAll(lines,
          rate: 0.8, gap: Duration.zero, accent: 'uk');

      expect(kokoro.rendered, lines.map((l) => l.text).toList());
      expect(kokoro.rates, [0.8, 0.8]);
      expect(player.buffers, hasLength(2));
      expect(provider.isPlaying, isFalse);
      expect(provider.currentIndex, isNull);
    });

    test('Kokoro reads the line when the model is there', () async {
      final player = _RecordingPlayer();
      final kokoro = _StubKokoro();
      final provider = EntrySpeechProvider(player: player, kokoro: kokoro);

      await provider.playAll([lines.first],
          rate: 1.0, gap: Duration.zero, accent: 'us');

      expect(kokoro.rendered, ['in charge of']);
      expect(kokoro.rates, [1.0], reason: 'the slider value, not halved');
      expect(player.buffers, hasLength(1));
      expect(player.sentences, isEmpty, reason: 'no other engine is used');
    });

    test('a line Kokoro cannot render is skipped, not read by another voice',
        () async {
      final player = _RecordingPlayer();
      final kokoro = _PartialKokoro('Two.');
      final provider = EntrySpeechProvider(player: player, kokoro: kokoro);

      await provider.playAll(const [
        EntryUtterance(text: 'One.', isPhrase: false),
        EntryUtterance(text: 'Two.', isPhrase: false),
        EntryUtterance(text: 'Three.', isPhrase: false),
      ], rate: 1.0, gap: Duration.zero, accent: 'us');

      // Two buffers, one per renderable line; the platform voice never speaks.
      expect(player.buffers, hasLength(2));
      expect(player.sentences, isEmpty,
          reason: 'switching voices mid-run is the male-voice bug');
    });

    test('pausing mid-line never hands the line to the platform voice',
        () async {
      final player = _GatedPlayer();
      final kokoro = _StubKokoro();
      final provider = EntrySpeechProvider(player: player, kokoro: kokoro);

      player.hold();
      final run = provider.playAll(const [
        EntryUtterance(text: 'One.', isPhrase: false),
        EntryUtterance(text: 'Two.', isPhrase: false),
      ], rate: 1.0, gap: Duration.zero, accent: 'us');
      await pumpEventQueue();
      expect(provider.isPlaying, isTrue);

      provider.pause();
      player.release();
      await pumpEventQueue();
      expect(player.sentences, isEmpty,
          reason: 'a stopped line must not be re-read by the system voice');

      provider.resume();
      await run;
      // One render per line: prefetching already had "Two." ready, and the
      // repeated line reuses its clip. What matters is that it *sounds* twice.
      expect(kokoro.rendered, ['One.', 'Two.']);
      expect(player.buffers, hasLength(3),
          reason: 'One, One again after 继续, then Two');
    });

    test('重复本句 lets the line finish, then says it again', () async {
      final player = _GateQueuePlayer();
      final kokoro = _StubKokoro();
      final provider = EntrySpeechProvider(player: player, kokoro: kokoro);

      player.holdNext();
      final run = provider.playAll(const [
        EntryUtterance(text: 'One.', isPhrase: false),
        EntryUtterance(text: 'Two.', isPhrase: false),
        EntryUtterance(text: 'Three.', isPhrase: false),
      ], rate: 1.0, gap: Duration.zero, accent: 'us');
      await pumpEventQueue();

      provider.repeatCurrent();
      player.releaseAll();
      await run;

      expect(kokoro.rendered, ['One.', 'Two.', 'Three.'],
          reason: 'each line is rendered once');
      expect(player.buffers, hasLength(4),
          reason: 'One sounds twice: once now, once again after it finished');
    });

    test('重复前一句 cuts the line and continues from the one before', () async {
      final player = _GateQueuePlayer();
      final kokoro = _StubKokoro();
      final provider = EntrySpeechProvider(player: player, kokoro: kokoro);

      player.holdNext();
      final run = provider.playAll(const [
        EntryUtterance(text: 'One.', isPhrase: false),
        EntryUtterance(text: 'Two.', isPhrase: false),
        EntryUtterance(text: 'Three.', isPhrase: false),
      ], rate: 1.0, gap: Duration.zero, accent: 'us');
      await pumpEventQueue();

      player.holdNext();
      player.releaseNext(); // 'One.' finishes, 'Two.' now sounds
      await pumpEventQueue();
      expect(provider.currentIndex, 1);

      provider.repeatPrevious();
      player.releaseAll();
      await run;

      expect(kokoro.rendered, ['One.', 'Two.', 'Three.']);
      expect(player.buffers, hasLength(5),
          reason: 'One, Two, then One and Two again, then Three');
    });

    test('重复前一句 on the first line repeats the first line', () async {
      final player = _GateQueuePlayer();
      final kokoro = _StubKokoro();
      final provider = EntrySpeechProvider(player: player, kokoro: kokoro);

      player.holdNext();
      final run = provider.playAll(const [
        EntryUtterance(text: 'One.', isPhrase: false),
        EntryUtterance(text: 'Two.', isPhrase: false),
      ], rate: 1.0, gap: Duration.zero, accent: 'us');
      await pumpEventQueue();

      provider.repeatPrevious();
      player.releaseAll();
      await run;

      expect(kokoro.rendered, ['One.', 'Two.']);
      expect(player.buffers, hasLength(3), reason: 'One twice, then Two');
    });

    test('the repeat buttons do nothing when the run is idle', () async {
      final player = _RecordingPlayer();
      final provider = EntrySpeechProvider(player: player, kokoro: _StubKokoro());

      provider.repeatCurrent();
      provider.repeatPrevious();

      expect(provider.canRepeat, isFalse);
      expect(player.sentences, isEmpty);
      expect(player.buffers, isEmpty);
    });

    test('isReading matches only the exact lines being spoken', () async {
      final player = _GateQueuePlayer();
      final provider = EntrySpeechProvider(player: player, kokoro: _StubKokoro());

      player.holdNext();
      final run = provider.playAll(const [
        EntryUtterance(text: 'One.', isPhrase: false),
        EntryUtterance(text: 'Two.', isPhrase: false),
      ], rate: 1.0, gap: Duration.zero, accent: 'us');
      await pumpEventQueue();

      expect(provider.isReading(['One.', 'Two.']), isTrue);
      expect(provider.isReading(['One.']), isFalse);
      expect(provider.isReading(['Two.', 'One.']), isFalse);

      player.releaseAll();
      await run;
      expect(provider.isReading(['One.', 'Two.']), isFalse);
    });

    test('the speaking line carries the class the reader colours', () {
      final prepared = prepareEntrySpeech(_sioHtml, speaking: 1);
      expect('speaking'.allMatches(prepared.html).length, 1);
      expect(
        prepareEntrySpeech(_sioHtml).html.contains('speaking'),
        isFalse,
        reason: 'nothing is read when no index is given',
      );
    });

    test('stop drops the pending lines of a run in flight', () async {
      final player = _RecordingPlayer();
      final kokoro = _StubKokoro()..gate = Completer<void>();
      final provider = EntrySpeechProvider(player: player, kokoro: kokoro);

      final run = provider.playAll(lines,
          rate: 1.0, gap: Duration.zero, accent: 'us');
      await Future<void>.delayed(Duration.zero);
      expect(provider.currentIndex, 0);

      provider.stop();
      kokoro.gate!.complete();
      await run;

      expect(kokoro.rendered.length, lessThanOrEqualTo(2),
          reason: 'at most the line playing plus the one prefetched');
      expect(player.buffers, isEmpty, reason: 'the cut line never sounds');
      expect(provider.isPlaying, isFalse);
      expect(player.stops, greaterThan(0));
    });

    test('playing one line stops whatever was running', () async {
      final player = _RecordingPlayer();
      final kokoro = _StubKokoro();
      final provider = EntrySpeechProvider(player: player, kokoro: kokoro);

      await provider.playOne(lines.last, rate: 1.0, accent: 'us');

      expect(kokoro.rendered, [lines.last.text]);
      expect(player.buffers, hasLength(1));
      expect(player.stops, greaterThan(0));
      expect(provider.isPlaying, isFalse);
    });

    test('a selection is spoken through the same voice', () async {
      final player = _RecordingPlayer();
      final kokoro = _StubKokoro();
      final provider = EntrySpeechProvider(player: player, kokoro: kokoro);

      await provider.speakText('  A definition nobody tagged.  ',
          rate: 1.2, accent: 'uk');

      expect(kokoro.rendered, ['A definition nobody tagged.'],
          reason: 'the selection is one utterance, trimmed');
      expect(kokoro.rates.last, 1.2);
      expect(provider.isPlaying, isFalse);
    });

    test('an empty selection says nothing', () async {
      final player = _RecordingPlayer();
      final provider = EntrySpeechProvider(player: player, kokoro: _StubKokoro(ready: false));

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

  test('the volume from the settings panel reaches the player', () async {
    final player = _RecordingPlayer();
    final provider = EntrySpeechProvider(player: player, kokoro: _StubKokoro());

    await provider.playAll(
      const [EntryUtterance(text: 'One.', isPhrase: false)],
      rate: 1.0,
      gap: Duration.zero,
      accent: 'us',
      volume: 0.35,
    );

    expect(player.volume, closeTo(0.35, 1e-9));
  });

  test('the system engine reads the lines and Kokoro stays idle', () async {
    final player = _RecordingPlayer();
    final kokoro = _StubKokoro();
    final provider = EntrySpeechProvider(player: player, kokoro: kokoro);

    await provider.playAll(
      const [
        EntryUtterance(text: 'One.', isPhrase: false),
        EntryUtterance(text: 'Two.', isPhrase: false),
      ],
      rate: 1.0,
      gap: Duration.zero,
      accent: 'us',
      engine: SpeechEngine.system,
    );

    expect(kokoro.rendered, isEmpty, reason: 'the model is not touched');
    expect(player.sentences, ['One.', 'Two.']);
  });
  test('currentUtterance and sentenceIndexFor track the active item', () async {
    final player = _RecordingPlayer();
    final kokoro = _StubKokoro();
    final speech = EntrySpeechProvider(player: player, kokoro: kokoro);

    final tracked = <String?>[];
    final item1Indices = <int?>[];
    final item2Indices = <int?>[];

    player.onBuffer = (count) {
      tracked.add(speech.currentUtterance?.text);
      item1Indices.add(speech.sentenceIndexFor('item-1'));
      item2Indices.add(speech.sentenceIndexFor('item-2'));
    };

    await speech.playAll(const [
      EntryUtterance(text: 'One.', isPhrase: false, itemId: 'item-1', sentenceIndex: 0),
      EntryUtterance(text: 'Two.', isPhrase: false, itemId: 'item-1', sentenceIndex: 1),
      EntryUtterance(text: 'Three.', isPhrase: false, itemId: 'item-2', sentenceIndex: 0),
    ], rate: 1.0, gap: Duration.zero, accent: 'us');

    expect(tracked, ['One.', 'Two.', 'Three.']);
    expect(item1Indices, [0, 1, null]);
    expect(item2Indices, [null, null, 0]);
    expect(speech.currentUtterance, isNull);
    expect(speech.sentenceIndexFor('item-1'), isNull);
  });

  test('the engine renders a window ahead of the line sounding', () async {
    final player = _GateQueuePlayer();
    final kokoro = _StubKokoro();
    final speech = EntrySpeechProvider(player: player, kokoro: kokoro);

    final lines = [
      for (var i = 0; i < 15; i++) EntryUtterance(text: 'line $i.', isPhrase: false),
    ];

    player.holdNext(); // sit inside the first line
    final run = speech.playAll(lines, rate: 1.0, gap: Duration.zero, accent: 'us');
    await Future<void>.delayed(const Duration(milliseconds: 50));

    // The first line pays the render; the next ten are already done while it
    // sounds, so those lines start on the configured gap alone.
    final window = EntrySpeechProvider.prefetchWindow;
    for (var ahead = 1; ahead <= window && ahead < lines.length; ahead++) {
      expect(kokoro.rendered, contains('line $ahead.'),
          reason: 'line $ahead should be rendered while line 0 sounds');
    }
    expect(kokoro.rendered, isNot(contains('line ${window + 1}.')));

    player.releaseAll();
    await run;
  }, timeout: const Timeout(Duration(minutes: 1)));

  group('pause, resume and loop', () {
    List<EntryUtterance> lines() => const [
          EntryUtterance(text: 'One.', isPhrase: false),
          EntryUtterance(text: 'Two.', isPhrase: false),
          EntryUtterance(text: 'Three.', isPhrase: false),
        ];

    test('pause silences at once and resume says that line again', () async {
      // The gate is on the *player*, so the pause lands while the line is
      // actually sounding — which is where "silence now" has to work.
      final player = _GateQueuePlayer();
      final kokoro = _StubKokoro();
      final speech = EntrySpeechProvider(player: player, kokoro: kokoro);

      player.holdNext();
      final run = speech.playAll(lines(), rate: 1.0, gap: Duration.zero, accent: 'us');
      await Future<void>.delayed(Duration.zero);
      expect(speech.currentIndex, 0, reason: 'inside the first line');

      speech.pause();
      expect(speech.isPaused, isTrue);
      expect(player.stops, 1, reason: 'the sound is cut, not waited out');

      player.releaseNext();
      await Future<void>.delayed(Duration.zero);
      expect(player.buffers, hasLength(1), reason: 'nothing new while paused');

      speech.resume();
      player.releaseAll();
      await run;

      expect(kokoro.rendered, ['One.', 'Two.', 'Three.'],
          reason: 'one render per line; the repeated line reuses its clip');
      expect(player.buffers, hasLength(4),
          reason: 'One, One again after 继续, Two, Three');
      expect(speech.isPaused, isFalse);
      expect(speech.isPlaying, isFalse);
    });

    test('循环 runs the list again until stopped', () async {
      final player = _RecordingPlayer();
      final kokoro = _StubKokoro();
      final speech = EntrySpeechProvider(player: player, kokoro: kokoro);
      player.onBuffer = (played) {
        if (played >= 5) speech.stop();
      };

      await speech.playAll(
        lines(),
        rate: 1.0,
        gap: Duration.zero,
        accent: 'us',
        loop: true,
      );

      expect(player.buffers.length, greaterThanOrEqualTo(5));
      expect(kokoro.rendered, ['One.', 'Two.', 'Three.'],
          reason: 'a looping run reuses the clips it already rendered');
      expect(speech.isPlaying, isFalse);
    });

    test('a one-off read never loops, even with the switch on', () async {
      final player = _RecordingPlayer();
      final kokoro = _StubKokoro();
      final speech = EntrySpeechProvider(player: player, kokoro: kokoro);
      speech.setLoop(true);

      await speech.speakText('Hello.', rate: 1.0, accent: 'us');

      expect(kokoro.rendered, ['Hello.']);
      expect(speech.loop, isTrue, reason: 'the switch keeps its setting');
    });
  });
}
