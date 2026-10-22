import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_dict/providers/entry_speech_provider.dart';
import 'package:local_dict/providers/settings_provider.dart';
import 'package:local_dict/ui/widgets/speakable_selection.dart';
import 'package:provider/provider.dart';

/// Records what would have been read instead of touching audio plugins.
class _RecordingSpeech extends EntrySpeechProvider {
  final List<String> spoken = [];

  @override
  Future<void> speakText(
    String text, {
    required double rate,
    required String accent,
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
