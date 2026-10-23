import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_dict/core/audio/kokoro_voice.dart';
import 'package:local_dict/core/audio/pcm_audio.dart';
import 'package:local_dict/core/audio/speech_clip_player.dart';
import 'package:local_dict/core/mdx/mdx_entry.dart';
import 'package:local_dict/providers/entry_speech_provider.dart';
import 'package:local_dict/providers/settings_provider.dart';
import 'package:local_dict/ui/widgets/word_definition_view.dart';
import 'package:provider/provider.dart';

/// The entry's own example markup only covers the lines the archive tagged.
/// Definitions, notes and explanations are plain rendered text, so the reader
/// has to be able to point at one and have it spoken.
class _RecordingPlayer implements SpeechClipPlayer {
  final List<String> sentences = [];
  int buffers = 0;

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<bool> playAudioBytes(Uint8List bytes, {double rate = 1.0}) async {
    buffers++;
    return true;
  }

  @override
  Future<void> playSpeechClip(String assetPath, {double rate = 1.0}) async {}


  @override
  Future<bool> speakSentence(String sentence,
          {String accent = 'us', double rate = 1.0}) async =>
      false;

  @override
  Future<String?> sentenceVoiceLabel(String accent) async => null;
  @override
  Future<void> stop() async {}
}

class _StubKokoro extends KokoroVoice {
  _StubKokoro() : super(finder: () async => null);

  final List<String> rendered = [];

  @override
  Future<bool> isReady() async => true;

  @override
  Future<PcmClip?> synthesize(String text,
      {required String accent, required double rate}) async {
    rendered.add(text);
    return PcmClip(Int16List.fromList(List.filled(2400, 3)), 24000);
  }
}

MdxEntry _entry() => MdxEntry(
      word: 'run',
      rawHtml: '<div class="defs"><li>move at a speed faster than a walk '
          '<span class="ex">She runs to school every morning.</span></li></div>',
      phonetic: '/rʌn/',
      soundKey: null,
      tabs: const [],
      panels: const {},
      exampleSentences: const [],
      definitions: const [],
    );

void main() {
  testWidgets('the speaker link in a line still plays', (tester) async {
    final player = _RecordingPlayer();
    final kokoro = _StubKokoro();
    final speech = EntrySpeechProvider(player: player, kokoro: kokoro);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
          ChangeNotifierProvider<EntrySpeechProvider>.value(value: speech),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: WordDefinitionView(entry: _entry()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The speaker the reader appended to every speakable line is a link inside
    // the rendered HTML; selection must not eat its tap.
    await tester.tapOnText(find.textRange.ofSubstring('🔊'));
    await tester.pumpAndSettle();

    expect(player.buffers, greaterThanOrEqualTo(1),
        reason: 'tapping the speaker link must reach the player');
  });

  testWidgets('a selected line is offered 朗读 and is spoken', (tester) async {
    final player = _RecordingPlayer();
    final kokoro = _StubKokoro();
    final speech = EntrySpeechProvider(player: player, kokoro: kokoro);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
          ChangeNotifierProvider<EntrySpeechProvider>.value(value: speech),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: WordDefinitionView(entry: _entry()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(
      find.textContaining('She runs to school', findRichText: true),
    );
    await tester.pumpAndSettle();

    expect(find.text('朗读'), findsOneWidget,
        reason: 'the selection menu gains a reading action');

    await tester.tap(find.text('朗读'));
    await tester.pumpAndSettle();

    // A long press selects the word under the finger; the reader drags the
    // handles to widen it. Whatever the selection is at tap time is what speaks.
    expect(kokoro.rendered, hasLength(1));
    final spoken = kokoro.rendered.single.toLowerCase();
    expect(spoken, isNotEmpty);
    expect('she runs to school every morning'.contains(spoken), isTrue,
        reason: 'spoke "$spoken", which is not part of the selected line');
  });
}
