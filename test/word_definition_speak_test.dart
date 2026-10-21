import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_dict/core/audio/piper_voice.dart';
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

  @override
  Future<bool> speakSentence(String sentence,
      {String accent = 'us', double rate = 1.0}) async {
    sentences.add(sentence);
    return true;
  }

  @override
  Future<bool> playAudioBytes(Uint8List bytes, {double rate = 1.0}) async => true;

  @override
  Future<void> playSpeechClip(String assetPath, {double rate = 1.0}) async {}

  @override
  Future<String?> sentenceVoiceLabel(String accent) async => null;

  @override
  Future<void> stop() async {}
}

class _NoPiper extends PiperVoice {
  _NoPiper() : super(finder: (accent) async => null);

  @override
  Future<bool> isReady(String accent) async => false;
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
    final speech = EntrySpeechProvider(player: player, piper: _NoPiper());

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

    expect(player.sentences, hasLength(1),
        reason: 'tapping the speaker link must reach the player');
  });

  testWidgets('a selected line is offered 朗读所选 and is spoken', (tester) async {
    final player = _RecordingPlayer();
    final speech = EntrySpeechProvider(player: player, piper: _NoPiper());

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

    expect(find.text('朗读所选'), findsOneWidget,
        reason: 'the selection menu gains a reading action');

    await tester.tap(find.text('朗读所选'));
    await tester.pumpAndSettle();

    // A long press selects the word under the finger; the reader drags the
    // handles to widen it. Whatever the selection is at tap time is what speaks.
    expect(player.sentences, hasLength(1));
    final spoken = player.sentences.single.toLowerCase();
    expect(spoken, isNotEmpty);
    expect('she runs to school every morning'.contains(spoken), isTrue,
        reason: 'spoke "$spoken", which is not part of the selected line');
  });
}
