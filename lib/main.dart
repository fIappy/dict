import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/platform/child_window_launcher.dart';
import 'core/audio/kokoro_voice.dart';
import 'core/platform/window_frame.dart';
import 'providers/custom_text_provider.dart';
import 'providers/dictionary_provider.dart';
import 'providers/ai_practice_provider.dart';
import 'providers/entry_speech_provider.dart';
import 'providers/favorites_provider.dart';
import 'providers/history_provider.dart';
import 'providers/frequency_provider.dart';
import 'providers/ipa_provider.dart';
import 'providers/alphabet_provider.dart';
import 'providers/numbers_provider.dart';
import 'providers/themes_provider.dart';
import 'providers/settings_provider.dart';
import 'ui/ai_window_app.dart';
import 'ui/vocab_window_app.dart';
import 'ui/screens/home_screen.dart';
import 'ui/theme/app_theme.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // `local_dict --ai-window=<theme>` / `--vocab-window=<theme>` are the child
  // windows: a second process, so each has plugins (storage, audio) and cannot
  // block the dictionary window.
  final request = childWindowRequest(args);
  if (request != null) {
    runApp(switch (request.window) {
      ChildWindow.ai => AiWindowApp(sceneId: request.sceneId),
      ChildWindow.vocabulary => VocabWindowApp(sceneId: request.sceneId),
    });
    return;
  }

  // Put the window back where it was before the first frame, so it never shows
  // at the runner's default size first.
  await WindowFrame.restore();

  // One engine for the whole app: it owns a worker isolate with the model
  // loaded (~150 MB), so a second instance would double that.
  final voice = KokoroVoice();

  runApp(
    WindowFrameKeeper(
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
          ChangeNotifierProvider(create: (_) => DictionaryProvider()),
          ChangeNotifierProvider(create: (_) => FavoritesProvider()),
          ChangeNotifierProvider(create: (_) => HistoryProvider()),
          ChangeNotifierProvider(create: (_) => FrequencyProvider()),
          ChangeNotifierProvider(create: (_) => IpaProvider()),
          ChangeNotifierProvider(create: (_) => AlphabetProvider()),
          ChangeNotifierProvider(create: (_) => NumbersProvider(kokoro: voice)),
          ChangeNotifierProvider(create: (_) => ThemesProvider()),
          ChangeNotifierProvider(
              create: (_) => EntrySpeechProvider(kokoro: voice)),
          ChangeNotifierProvider(create: (_) => CustomTextProvider()),
          ChangeNotifierProvider(create: (_) => AiPracticeProvider()),
        ],
        child: const LocalDictApp(),
      ),
    ),
  );
}

class LocalDictApp extends StatelessWidget {
  const LocalDictApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    return MaterialApp(
      title: '本地词典 - Local Dictionary',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: settings.themeMode,
      home: const HomeScreen(),
    );
  }
}
