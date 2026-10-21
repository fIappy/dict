import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/platform/ai_window_launcher.dart';
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
import 'ui/screens/home_screen.dart';
import 'ui/theme/app_theme.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // `local_dict --ai-window=<theme>` is the AI practice in its own window: a
  // second process, so it has plugins (storage, audio) and cannot block the
  // dictionary window.
  final aiSceneId = aiWindowSceneId(args);
  if (aiSceneId != null) {
    runApp(AiWindowApp(sceneId: aiSceneId));
    return;
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => DictionaryProvider()),
        ChangeNotifierProvider(create: (_) => FavoritesProvider()),
        ChangeNotifierProvider(create: (_) => HistoryProvider()),
        ChangeNotifierProvider(create: (_) => FrequencyProvider()),
        ChangeNotifierProvider(create: (_) => IpaProvider()),
        ChangeNotifierProvider(create: (_) => AlphabetProvider()),
        ChangeNotifierProvider(create: (_) => NumbersProvider()),
        ChangeNotifierProvider(create: (_) => ThemesProvider()),
        ChangeNotifierProvider(create: (_) => EntrySpeechProvider()),
        ChangeNotifierProvider(create: (_) => AiPracticeProvider()),
      ],
      child: const LocalDictApp(),
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
