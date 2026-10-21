import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../core/themes/theme_service.dart';
import '../providers/ai_practice_provider.dart';
import '../providers/entry_speech_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/themes_provider.dart';
import 'screens/ai_practice_screen.dart';
import 'theme/app_theme.dart';

/// The app that runs inside an AI window: one theme, its practice page, and
/// nothing else. Launched as `local_dict --ai-window=<sceneId>`.
class AiWindowApp extends StatelessWidget {
  const AiWindowApp({super.key, required this.sceneId});

  final String sceneId;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => ThemesProvider()),
        ChangeNotifierProvider(create: (_) => AiPracticeProvider()),
        ChangeNotifierProvider(create: (_) => EntrySpeechProvider()),
      ],
      child: _AiWindow(sceneId: sceneId),
    );
  }
}

class _AiWindow extends StatefulWidget {
  const _AiWindow({required this.sceneId});

  final String sceneId;

  @override
  State<_AiWindow> createState() => _AiWindowState();
}

class _AiWindowState extends State<_AiWindow> {
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

    // The window manager plugin is only there on desktop; a lookup failure must
    // leave a working window, just an unsized one.
    try {
      await windowManager.ensureInitialized();
      await windowManager.waitUntilReadyToShow(
        WindowOptions(size: const Size(760, 940), center: true, title: 'AI 练习'),
        () async {
          await windowManager.show();
          await windowManager.focus();
        },
      );
    } on Exception catch (e) {
      debugPrint('Window sizing unavailable: $e');
    }

    await settings.initialize();
    await themes.initialize();
    if (!mounted) return;

    final scene = themes.scenes.where((s) => s.id == widget.sceneId).firstOrNull;
    if (scene == null) {
      setState(() => _failed = true);
      return;
    }
    setState(() => _scene = scene);
    try {
      await windowManager.setTitle('AI 练习 · ${scene.label}');
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
      body = AiPracticeScreen(scene: _scene!);
    }

    return MaterialApp(
      title: 'AI 练习',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: settings.themeMode,
      home: Scaffold(
        body: SafeArea(child: body),
        // The window title bar is the frame; an in-app bar here would repeat it.
        backgroundColor: Theme.of(context).colorScheme.surface,
      ),
    );
  }
}
