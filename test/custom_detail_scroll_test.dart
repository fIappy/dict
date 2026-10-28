import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_dict/providers/custom_text_provider.dart';
import 'package:local_dict/providers/entry_speech_provider.dart';
import 'package:local_dict/providers/settings_provider.dart';
import 'package:local_dict/ui/screens/custom_detail_view.dart';
import 'package:provider/provider.dart';
import 'package:local_dict/core/mdx/entry_speech.dart';
import 'package:local_dict/ui/widgets/annotated_text.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dart:async';
import 'dart:typed_data';
import 'package:local_dict/core/audio/kokoro_voice.dart';
import 'package:local_dict/core/audio/pcm_audio.dart';
import 'package:local_dict/core/audio/speech_clip_player.dart';

class _TestPlayer implements SpeechClipPlayer {
  Completer<void>? gate;

  @override
  Future<bool> playAudioBytes(Uint8List bytes, {double rate = 1.0}) async {
    if (gate != null && !gate!.isCompleted) await gate!.future;
    return true;
  }
  @override
  Future<void> playSpeechClip(String assetPath, {double rate = 1.0}) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<bool> speakSentence(String sentence, {String accent = 'us', double rate = 1.0}) async => true;
  @override
  Future<String?> sentenceVoiceLabel(String accent) async => 'Voice';
  @override
  Future<void> stop() async {}
}

class _TestKokoro extends KokoroVoice {
  _TestKokoro() : super(finder: () async => null);
  @override
  Future<bool> isReady() async => true;
  @override
  Future<PcmClip?> synthesize(String text, {required String accent, required double rate}) async =>
      PcmClip(Int16List.fromList(List.filled(2205, 3)), 22050);
}

void main() {
  testWidgets('the passage editor has exactly one scrollbar', (tester) async {
    // The bug: the framework adds its own scrollbar to every scrollable
    // (EditableText included), so the explicit always-visible one doubled it —
    // two bars dragging in sync. The fix disables the framework's in this
    // subtree; this test keeps it that way.
    SharedPreferences.setMockInitialValues({});
    final provider = CustomTextProvider();
    await provider.initialize();
    final item = await provider.add(
      body: [for (var i = 0; i < 80; i++) 'Sentence number $i.'].join(' '),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<CustomTextProvider>.value(value: provider),
          ChangeNotifierProvider(create: (_) => EntrySpeechProvider()),
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ],
        child: MaterialApp(
          home: Scaffold(body: CustomDetailView(itemId: item.id)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Scrollbar), findsOneWidget,
        reason: 'the text field carries the only scrollbar');

    // Ask the behaviour the field actually resolves: with the framework's
    // scrollbars switched off it must hand the child back untouched instead of
    // wrapping it in a second bar.
    final fieldContext = tester.element(find.byType(TextField).last);
    final behavior = ScrollConfiguration.of(fieldContext);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    const probe = SizedBox(key: ValueKey('probe'));
    final wrapped = behavior.buildScrollbar(
      fieldContext,
      probe,
      ScrollableDetails.vertical(controller: controller),
    );
    expect(identical(wrapped, probe), isTrue,
        reason: 'the framework must not draw a second bar inside the field');
  });

  testWidgets('the body field scrolls instead of pushing the buttons away',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final provider = CustomTextProvider();
    await provider.initialize();
    final item = await provider.add(
      body: [for (var i = 0; i < 200; i++) 'Sentence number $i.'].join(' '),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<CustomTextProvider>.value(value: provider),
          ChangeNotifierProvider(create: (_) => EntrySpeechProvider()),
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ],
        child: MaterialApp(
          home: Scaffold(body: CustomDetailView(itemId: item.id)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Even with a very long passage the controls keep their place at the top of
    // the pane's flow: the field takes the free height.
    final field = tester.getRect(find.byType(TextField).last);
    final save = tester.getRect(find.widgetWithText(FilledButton, '保存'));
    expect(field.height, lessThan(600));
    expect(save.top, greaterThan(field.bottom - 1));
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'reading from a sentence highlights that sentence in red in the reader view',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final provider = CustomTextProvider();
    await provider.initialize();
    final item = await provider.add(
      body: 'First sentence. Second sentence. Third sentence.',
    );
    provider.select(item.id);

    final player = _TestPlayer();
    final speech = EntrySpeechProvider(
      player: player,
      kokoro: _TestKokoro(),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<CustomTextProvider>.value(value: provider),
          ChangeNotifierProvider<EntrySpeechProvider>.value(value: speech),
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ],
        child: MaterialApp(
          home: Scaffold(body: CustomDetailView(itemId: item.id)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.byType(AnnotatedText), findsNothing);
    player.gate = Completer<void>();
    final run = speech.playAll(
[
      EntryUtterance(
          text: 'Second sentence.',
          isPhrase: false,
          itemId: item.id,
          sentenceIndex: 1,
        ),
        EntryUtterance(
          text: 'Third sentence.',
          isPhrase: false,
          itemId: item.id,
          sentenceIndex: 2,
        ),
      ],
      rate: 1.0,
      gap: Duration.zero,
      accent: 'us',
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(AnnotatedText), findsOneWidget);
    final annotated = tester.widget<AnnotatedText>(find.byType(AnnotatedText));
    expect(annotated.speakingIndex, 1);

    expect(find.textContaining('正在朗读 2/3：Second sentence.'), findsOneWidget);
    player.gate?.complete();
    speech.stop();
    await tester.pump();
    await run;
  });

}
