import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_dict/core/mdx/entry_speech.dart';
import 'package:local_dict/core/audio/speech_engine.dart';
import 'package:local_dict/providers/entry_speech_provider.dart';
import 'package:local_dict/providers/settings_provider.dart';
import 'package:local_dict/ui/widgets/speakable_selection.dart';
import 'package:provider/provider.dart';

/// Records what would have been read instead of touching audio plugins.
class _RecordingSpeech extends EntrySpeechProvider {
  final List<String> spoken = [];
  final List<String> played = [];

  @override
  Future<void> playAll(
    List<EntryUtterance> items, {
    required double rate,
    required Duration gap,
    required String accent,
    bool? loop,
    SpeechEngine engine = SpeechEngine.kokoro,
    double volume = 1.0,
  }) async {
    played.addAll([for (final item in items) item.text]);
  }

  @override
  Future<void> speakText(
    String text, {
    required double rate,
    required String accent,
    SpeechEngine engine = SpeechEngine.kokoro,
    double volume = 1.0,
  }) async {
    spoken.add(text);
  }
}

Widget _app(Widget child, _RecordingSpeech speech) => MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider<EntrySpeechProvider>.value(value: speech),
      ],
      child: MaterialApp(home: Scaffold(body: Center(child: child))),
    );

void main() {
  testWidgets('selecting a word offers 朗读 and reads that word',
      (tester) async {
    final speech = _RecordingSpeech();
    await tester.pumpWidget(_app(
      const SpeakableText('The coach called the team.'),
      speech,
    ));
    await tester.pumpAndSettle();

    await tester.longPressAt(
      tester.getCenter(find.text('The coach called the team.')),
    );
    await tester.pumpAndSettle();

    expect(find.text('朗读'), findsOneWidget);
    await tester.tap(find.text('朗读'));
    await tester.pumpAndSettle();

    expect(speech.spoken, hasLength(1));
    expect(speech.spoken.single, isNotEmpty);
    expect('The coach called the team.', contains(speech.spoken.single));
  });

  testWidgets('right-clicking a passage reads from that sentence to the end',
      (tester) async {
    // Secondary-click menus are a desktop behaviour, and the test binding
    // insists the override is cleared before the body ends.
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      final speech = _RecordingSpeech();
      final controller = TextEditingController(
        text: 'I put my bag down.\nI turned on the light.\nI sat down.',
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(_app(
        Listener(
          onPointerDown: (event) {
            if (event.buttons & kSecondaryMouseButton != 0) {
              rememberSecondaryTap(event.position);
            }
          },
          child: TextField(
            controller: controller,
            contextMenuBuilder: speakableEditableMenu,
            maxLines: 5,
          ),
        ),
        speech,
      ));
      await tester.pumpAndSettle();

      // Right-click on the second line.
      final box = tester.getRect(find.byType(TextField));
      await tester.tapAt(
        Offset(box.left + 40, box.top + 40),
        buttons: kSecondaryButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();

      expect(find.text('从这里开始朗读'), findsOneWidget);
      await tester.tap(find.text('从这里开始朗读'));
      await tester.pumpAndSettle();

      expect(speech.played.last, 'I sat down.',
          reason: 'reading continues to the end of the passage');
      expect(speech.played.first, isNot('I put my bag down.'),
          reason: 'it starts at the clicked sentence, not at the top');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('a draggable text block gets the same 朗读 action',
      (tester) async {
    final speech = _RecordingSpeech();
    await tester.pumpWidget(_app(
      const SpeakableSelectionArea(
        child: Text('The coach called the team.'),
      ),
      speech,
    ));
    await tester.pumpAndSettle();

    await tester.longPressAt(
      tester.getCenter(find.text('The coach called the team.')),
    );
    await tester.pumpAndSettle();

    expect(find.text('朗读'), findsOneWidget);
    await tester.tap(find.text('朗读'));
    await tester.pumpAndSettle();

    expect(speech.spoken.single.trim(), isNotEmpty);
  });
}
