import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_dict/core/audio/speech_engine.dart';
import 'package:local_dict/providers/dictionary_provider.dart';
import 'package:local_dict/providers/settings_provider.dart';
import 'package:local_dict/ui/screens/settings_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _app() => MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => DictionaryProvider()),
      ],
      child: const MaterialApp(home: Scaffold(body: SettingsScreen(isPaneView: true))),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the settings panel owns the engine choice and the volume',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    // Engine: both choices, Kokoro selected by default.
    await tester.scrollUntilVisible(find.text('Kokoro'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Kokoro'), findsOneWidget);
    expect(find.text('系统语音'), findsOneWidget);

    final engine = tester.widget<SegmentedButton<SpeechEngine>>(
      find.byType(SegmentedButton<SpeechEngine>),
    );
    expect(engine.selected, {SpeechEngine.kokoro});

    // Volume: a slider labelled 音量 that reports a percentage.
    await tester.scrollUntilVisible(find.text('音量'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('音量'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
  });

  testWidgets('choosing the system engine is remembered', (tester) async {
    final settings = SettingsProvider();
    await settings.initialize();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ChangeNotifierProvider(create: (_) => DictionaryProvider()),
        ],
        child: const MaterialApp(home: Scaffold(body: SettingsScreen(isPaneView: true))),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('系统语音'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('系统语音'));
    await tester.pumpAndSettle();

    expect(settings.speechEngine, SpeechEngine.system);
  });
}
