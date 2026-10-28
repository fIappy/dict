import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../core/themes/theme_service.dart';
import '../providers/dictionary_provider.dart';
import '../providers/entry_speech_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/themes_provider.dart';
import '../providers/vocabulary_provider.dart';
import 'screens/vocab_drill_screen.dart';
import 'theme/app_theme.dart';

/// The app that runs inside a 背词 window: one theme's words and their
/// meanings, plus the dictionary for the words in it.
/// Launched as `local_dict --vocab-window=<sceneId>`.
class VocabWindowApp extends StatelessWidget {
  const VocabWindowApp({super.key, required this.sceneId});

  final String sceneId;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => ThemesProvider()),
        ChangeNotifierProvider(create: (_) => VocabularyProvider()),
        ChangeNotifierProvider(create: (_) => DictionaryProvider()),
        ChangeNotifierProvider(create: (_) => EntrySpeechProvider()),
      ],
      child: _VocabWindow(sceneId: sceneId),
    );
  }
}

class _VocabWindow extends StatefulWidget {
  const _VocabWindow({required this.sceneId});

  final String sceneId;

  @override
  State<_VocabWindow> createState() => _VocabWindowState();
}

class _VocabWindowState extends State<_VocabWindow> {
  ThemeScene? _scene;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    // Read the providers before the first await: the widget may be gone by the
    // time the window manager answers.
    final settings = context.read<SettingsProvider>();
    final themes = context.read<ThemesProvider>();
    final vocabulary = context.read<VocabularyProvider>();
    final dictionary = context.read<DictionaryProvider>();

    try {
      await windowManager.ensureInitialized();
      await windowManager.waitUntilReadyToShow(
        WindowOptions(
          size: const Size(1180, 820),
          center: true,
          minimumSize: const Size(720, 520),
          title: '背词',
        ),
        () async {
          await windowManager.show();
          await windowManager.focus();
        },
      );
    } on Exception catch (e) {
      // A window without a size is still a working window.
      debugPrint('Window sizing unavailable: $e');
    }

    await settings.initialize();
    await vocabulary.initialize();
    // The curated stars (the `*` marks in the theme files) arrive once per
    // library version; the reader's own ratings win.
    await vocabulary.ensureSeeded();
    await themes.initialize();
    // The dictionary is the slow one (it opens the .mdx files); the word list
    // is readable before it answers.
    await dictionary.initialize(restoreWord: false);
    if (!mounted) return;

    final scene = themes.scenes.where((s) => s.id == widget.sceneId).firstOrNull;
    if (scene == null) {
      setState(() => _failed = true);
      return;
    }
    setState(() => _scene = scene);
    try {
      await windowManager.setTitle('背词 · ${scene.label}');
    } on Exception catch (e) {
      debugPrint('Window title unavailable: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final Widget body;
    if (_failed) {
      body = const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('找不到这个主题，可能词典数据已更新。', style: TextStyle(fontSize: 13)),
        ),
      );
    } else if (_scene == null) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      body = VocabDrillScreen(scene: _scene!);
    }

    return MaterialApp(
      title: '背词',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: settings.themeMode,
      home: Scaffold(
        body: SafeArea(child: body),
        backgroundColor: Theme.of(context).colorScheme.surface,
      ),
    );
  }
}
