import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/audio/speech_engine.dart';
import '../../providers/dictionary_provider.dart';
import '../../providers/entry_speech_provider.dart';
import '../../providers/favorites_provider.dart';
import '../../providers/history_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/frequency_provider.dart';
import '../../providers/ipa_provider.dart';
import '../../providers/alphabet_provider.dart';
import '../../providers/numbers_provider.dart';
import '../../providers/themes_provider.dart';
import '../../providers/custom_text_provider.dart';
import '../../core/themes/theme_service.dart';
import '../../core/ui/ui_memory.dart';
import 'alphabet_detail_view.dart';
import 'alphabet_screen.dart';
import 'favorites_screen.dart';
import 'frequency_screen.dart';
import 'history_screen.dart';
import 'ipa_detail_view.dart';
import 'ipa_screen.dart';
import 'numbers_detail_view.dart';
import 'numbers_screen.dart';
import 'themes_screen.dart';
import 'vocab_drill_screen.dart';
import 'ai_practice_screen.dart';
import 'custom_detail_view.dart';
import 'custom_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'word_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// Keep in step with the destinations lists below: the rail has no 设置 entry
  /// (it sits in the rail's trailing corner), the phone bar has six.
  static const int _railDestinationCount = 5;
  static const int _mobileDestinationCount = 6;

  int _selectedIndex = 0;

  /// Sub-section of 生词本: 0 = 生词本, 1 = 查词历史.
  int _favoritesTab = 0;

  /// Sub-section of 基础: 0 = 音标, 1 = 字母, 2 = 数字.
  int _basicTab = 0;

  /// Sub-section of 背词: 0 = 词频, 1 = 主题, 2 = 背词, 3 = AI 练习.
  int _reciteTab = 0;

  /// The theme the drill and AI tabs read; null follows 主题's open scene.
  String? _reciteSceneId;
  final Set<int> _mountedMobileTabs = <int>{0};

  /// The middle pane's width. A notifier, not a plain field: dragging the
  /// divider must re-lay the panes out, not rebuild the shell and its lists.
  final ValueNotifier<double> _middlePaneWidth = ValueNotifier<double>(360);

  @override
  void dispose() {
    _middlePaneWidth.dispose();
    super.dispose();
  }
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      unawaited(context.read<DictionaryProvider>().initialize());
      final favorites = context.read<FavoritesProvider>();
      unawaited(favorites.initialize().then((_) {
        if (mounted) unawaited(favorites.ensureSeeded());
      }));
      unawaited(context.read<HistoryProvider>().initialize());
      unawaited(context.read<FrequencyProvider>().initialize());
      unawaited(context.read<NumbersProvider>().initialize());
      unawaited(context.read<ThemesProvider>().initialize());
      final settings = context.read<SettingsProvider>();
      final entrySpeech = context.read<EntrySpeechProvider>();
      unawaited(settings.initialize().then((_) {
        if (mounted && settings.speechEngine == SpeechEngine.kokoro) {
          entrySpeech.warmUp();
        }
      }));
      final custom = context.read<CustomTextProvider>();
      unawaited(custom.initialize().then((_) {
        if (mounted) unawaited(custom.ensureSeeded());
      }));
      unawaited(context.read<IpaProvider>().restore());
      unawaited(context.read<AlphabetProvider>().restore());
      await _restoreLayout();
    });
  }

  /// Puts the shell back the way it was closed: same section, same split.
  /// v1's ten destinations folded into v2's six.
  static int? _migrateLegacySection(int? old) {
    if (old == null) return null;
    const map = [0, 1, 3, 3, 2, 2, 2, 1, 4, 5];
    return old >= 0 && old < map.length ? map[old] : null;
  }

  Future<void> _restoreLayout() async {
    final section = await UiMemory.readInt(UiMemory.sectionV2) ??
        _migrateLegacySection(await UiMemory.readInt(UiMemory.section));
    final paneWidth = await UiMemory.readDouble(UiMemory.paneWidth);
    if (!mounted) return;
    final isDesktop = MediaQuery.sizeOf(context).width >= 800;
    final maxSection =
        (isDesktop ? _railDestinationCount : _mobileDestinationCount) - 1;
    setState(() {
      if (section != null) {
        _selectedIndex = section.clamp(0, maxSection);
        _mountedMobileTabs.add(_selectedIndex);
      }
      if (paneWidth != null) {
        _middlePaneWidth.value = paneWidth.clamp(220.0, 900.0);
      }
    });
  }

  void _selectSection(int index) {
    if (_selectedIndex == index) return;
    setState(() {
      _selectedIndex = index;
      _mountedMobileTabs.add(index);
    });
    unawaited(UiMemory.writeInt(UiMemory.sectionV2, index));
  }

  void _rememberPaneWidth() =>
      unawaited(UiMemory.writeDouble(UiMemory.paneWidth, _middlePaneWidth.value));

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 800;
        if (isDesktop) {
          return _buildDesktopLayout(context, constraints);
        } else {
          return _buildMobileLayout(context);
        }
      },
    );
  }

  Widget _buildDesktopLayout(BuildContext context, BoxConstraints constraints) {
    // 设置 (index 9) exists only in the phone bar; a section restored under a
    // wider window falls back to the last rail destination.
    final index = _selectedIndex.clamp(0, _railDestinationCount - 1);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Widget middlePane = _buildMiddlePane(index);

    final double maxMiddle = (constraints.maxWidth - 440.0).clamp(280.0, 900.0);
    return Scaffold(
      body: Row(
        children: [
          // Each pane repaints on its own: dragging the divider must not
          // repaint the rail, and the rail must not repaint the editor.
          RepaintBoundary(
            child: _DesktopNavigationRail(
              selectedIndex: index,
              onDestinationSelected: _selectSection,
            ),
          ),
          const VerticalDivider(width: 1),
          RepaintBoundary(
            child: _SizedPane(
              width: _middlePaneWidth,
              min: 220.0,
              max: maxMiddle,
              child: middlePane,
            ),
          ),
          _PaneDivider(
            width: _middlePaneWidth,
            min: 220.0,
            max: maxMiddle,
            isDark: isDark,
            onDone: _rememberPaneWidth,
            onReset: () {
              _middlePaneWidth.value = 360;
              _rememberPaneWidth();
            },
          ),
          Expanded(
            child: RepaintBoundary(
              child: _DesktopRightPane(index: index, basicTab: _basicTab),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiddlePane(int index) {
    switch (index) {
      case 0:
        return const SearchScreen(isPaneView: true);
      case 1:
        return _favoritesHub(pane: true);
      case 2:
        return _basicHub(pane: true);
      case 3:
        return _reciteHub(pane: true);
      case 4:
        return const CustomScreen(isPaneView: true);
      default:
        return const SearchScreen(isPaneView: true);
    }
  }

  Widget _buildMobileTab(int index) {
    switch (index) {
      case 0:
        return const SearchScreen(isPaneView: false);
      case 1:
        return _favoritesHub(pane: false);
      case 2:
        return _basicHub(pane: false);
      case 3:
        return _reciteHub(pane: false);
      case 4:
        return const CustomScreen(isPaneView: false);
      case 5:
        return const SettingsScreen(isPaneView: true);
      default:
        return const SearchScreen(isPaneView: false);
    }
  }

  /// 生词本 owns 查词历史 now: one section, a fixed two-tab strip.
  Widget _favoritesHub({required bool pane}) {
    final content = Column(
      children: [
        _SubtabStrip(
          labels: const ['生词本', '历史'],
          selected: _favoritesTab,
          onSelected: (value) => setState(() => _favoritesTab = value),
        ),
        Expanded(
          child: _favoritesTab == 0
              ? const FavoritesScreen(isPaneView: true)
              : const HistoryScreen(isPaneView: true),
        ),
      ],
    );
    return pane ? content : _hubPage(title: '生词本', content: content);
  }

  /// 基础: 音标 / 字母 / 数字.
  Widget _basicHub({required bool pane}) {
    final content = Column(
      children: [
        _SubtabStrip(
          labels: const ['音标', '字母', '数字'],
          selected: _basicTab,
          onSelected: (value) => setState(() => _basicTab = value),
        ),
        Expanded(
          child: switch (_basicTab) {
            0 => const IpaScreen(isPaneView: true),
            1 => const AlphabetScreen(isPaneView: true),
            _ => const NumbersScreen(isPaneView: true),
          },
        ),
      ],
    );
    return pane ? content : _hubPage(title: '基础', content: content);
  }

  /// 背词: 词频 / 主题, plus the drill and AI pages that used to hang off 主题.
  Widget _reciteHub({required bool pane}) {
    final themes = context.watch<ThemesProvider>();
    final scene = _reciteScene(themes);
    final body = switch (_reciteTab) {
      0 => const FrequencyScreen(isPaneView: true),
      1 => const ThemesScreen(isPaneView: true),
      2 => scene == null
          ? const _EmptyHub('还没有主题数据')
          : VocabDrillScreen(scene: scene),
      _ => scene == null
          ? const _EmptyHub('还没有主题数据')
          : AiPracticeScreen(scene: scene, isPaneView: true),
    };
    final content = Column(
      children: [
        _SubtabStrip(
          labels: const ['词频', '主题', '背词', 'AI 练习'],
          selected: _reciteTab,
          onSelected: (value) => setState(() => _reciteTab = value),
        ),
        if (_reciteTab >= 2) _reciteScenePicker(themes),
        Expanded(child: body),
      ],
    );
    return pane ? content : _hubPage(title: '背词', content: content);
  }

  ThemeScene? _reciteScene(ThemesProvider themes) {
    final scenes = themes.scenes;
    if (scenes.isEmpty) return null;
    final wanted = _reciteSceneId;
    if (wanted != null) {
      for (final scene in scenes) {
        if (scene.id == wanted) return scene;
      }
    }
    return themes.selectedScene ?? scenes.first;
  }

  Widget _reciteScenePicker(ThemesProvider themes) {
    final scenes = themes.scenes;
    final scene = _reciteScene(themes);
    if (scenes.length <= 1 || scene == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Row(
        children: [
          Icon(Icons.local_library_outlined,
              size: 16, color: Theme.of(context).hintColor),
          const SizedBox(width: 6),
          Expanded(
            child: DropdownButton<String>(
              value: scene.id,
              isExpanded: true,
              isDense: true,
              items: [
                for (final item in scenes)
                  DropdownMenuItem(
                    value: item.id,
                    child: Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
              ],
              onChanged: (value) => setState(() => _reciteSceneId = value),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hubPage({required String title, required Widget content}) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(child: content),
    );
  }

  Widget _buildMobileLayout(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          for (var i = 0; i < _mobileDestinationCount; i++)
            _mountedMobileTabs.contains(i) || i == _selectedIndex
                ? _buildMobileTab(i)
                : const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        // Six destinations: the sub-sections live inside their section.
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        selectedIndex: _selectedIndex,
        onDestinationSelected: _selectSection,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.search_rounded),
            label: '查词',
          ),
          NavigationDestination(
            icon: Icon(Icons.bookmark_outline_rounded),
            selectedIcon: Icon(Icons.bookmark_rounded),
            label: '生词本',
          ),
          NavigationDestination(
            icon: Icon(Icons.school_outlined),
            selectedIcon: Icon(Icons.school_rounded),
            label: '基础',
          ),
          NavigationDestination(
            icon: Icon(Icons.fitness_center_outlined),
            selectedIcon: Icon(Icons.fitness_center_rounded),
            label: '背词',
          ),
          NavigationDestination(
            icon: Icon(Icons.edit_note_outlined),
            selectedIcon: Icon(Icons.edit_note_rounded),
            label: '自定义',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: '设置',
          ),
        ],
      ),
    );
  }
}

/// A pane whose width follows [width] without rebuilding [child].
class _DesktopNavigationRail extends StatelessWidget {
  const _DesktopNavigationRail({
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return NavigationRail(
      selectedIndex: selectedIndex,
      onDestinationSelected: onDestinationSelected,
      leading: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.primary,
                    theme.colorScheme.secondary,
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.primary.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: const Icon(
                Icons.menu_book_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
          ],
        ),
      ),
      trailing: Expanded(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: IconButton(
              icon: Icon(
                Icons.settings_rounded,
                color: theme.colorScheme.primary,
              ),
              tooltip: '设置',
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => Dialog(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: 460,
                      maxHeight: 620,
                    ),
                    child: const SettingsScreen(isPaneView: true),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      // Five top-level sections now; the sub-sections live inside them.
      labelType: NavigationRailLabelType.selected,
      destinations: const [
        NavigationRailDestination(
          icon: Icon(Icons.search_rounded),
          selectedIcon: Icon(Icons.search_rounded),
          label: Text('查词'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.bookmark_outline_rounded),
          selectedIcon: Icon(Icons.bookmark_rounded),
          label: Text('生词本'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.school_outlined),
          selectedIcon: Icon(Icons.school_rounded),
          label: Text('基础'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.fitness_center_outlined),
          selectedIcon: Icon(Icons.fitness_center_rounded),
          label: Text('背词'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.edit_note_outlined),
          selectedIcon: Icon(Icons.edit_note_rounded),
          label: Text('自定义'),
        ),
      ],
    );
  }
}

class _DesktopRightPane extends StatelessWidget {
  const _DesktopRightPane({required this.index, required this.basicTab});

  final int index;
  final int basicTab;

  @override
  Widget build(BuildContext context) {
    if (index == 2) {
      return switch (basicTab) {
        0 => IpaDetailView(
            isPaneView: true,
            phoneme: context.select((IpaProvider p) => p.currentPhoneme),
          ),
        1 => AlphabetDetailView(
            isPaneView: true,
            letter: context.select((AlphabetProvider p) => p.currentLetter),
          ),
        _ => const NumbersDetailView(isPaneView: true),
      };
    }
    if (index == 4) {
      final selected = context.select(
        (CustomTextProvider p) => (id: p.selectedId, groupId: p.selectedGroupId),
      );
      return CustomDetailView(
        // Re-seeded per group as well: a new entry lands in the group that is
        // open.
        key: ValueKey('${selected.id}|${selected.groupId}'),
        itemId: selected.id,
        isPaneView: true,
      );
    }
    final word = context.select(
      (DictionaryProvider p) => p.currentWord ?? 'hello',
    );
    return WordDetailScreen(isPaneView: true, word: word);
  }
}

/// The chip strip that switches a section's sub-pages.
///
/// Chips rather than a segmented button: 背词 has four labels of different
/// widths, and a wrap keeps them legible on a 363 dp phone without shrinking.
class _SubtabStrip extends StatelessWidget {
  const _SubtabStrip({
    required this.labels,
    required this.selected,
    required this.onSelected,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (var i = 0; i < labels.length; i++)
            ChoiceChip(
              label: Text(labels[i], style: const TextStyle(fontSize: 12.5)),
              selected: selected == i,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onSelected: (_) => onSelected(i),
            ),
        ],
      ),
    );
  }
}

class _EmptyHub extends StatelessWidget {
  const _EmptyHub(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).hintColor),
          ),
        ),
      );
}

/// A pane whose width follows [width] without rebuilding [child].
class _SizedPane extends StatelessWidget {
  const _SizedPane({
    required this.width,
    required this.min,
    required this.max,
    required this.child,
  });

  final ValueListenable<double> width;
  final double min;
  final double max;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: width,
      child: child,
      builder: (context, value, child) => SizedBox(
        width: value.clamp(min, max),
        child: child,
      ),
    );
  }
}

/// The bar between the list pane and the detail pane.
///
/// Owns its hover/drag look and writes the width into a notifier, so a drag is
/// a layout change and nothing above it rebuilds.
class _PaneDivider extends StatefulWidget {
  const _PaneDivider({
    required this.width,
    required this.min,
    required this.max,
    required this.isDark,
    required this.onDone,
    required this.onReset,
  });

  final ValueNotifier<double> width;
  final double min;
  final double max;
  final bool isDark;
  final VoidCallback onDone;
  final VoidCallback onReset;

  @override
  State<_PaneDivider> createState() => _PaneDividerState();
}

class _PaneDividerState extends State<_PaneDivider> {
  bool _hovering = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = _hovering || _dragging;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) {
        if (_hovering) return;
        setState(() => _hovering = true);
      },
      onExit: (_) {
        if (_dragging || !_hovering) return;
        setState(() => _hovering = false);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (_) {
          if (!_dragging) setState(() => _dragging = true);
        },
        onHorizontalDragUpdate: (details) {
          widget.width.value = (widget.width.value + details.delta.dx)
              .clamp(widget.min, widget.max);
        },
        onHorizontalDragEnd: (_) {
          if (_dragging) setState(() => _dragging = false);
          widget.onDone();
        },
        onHorizontalDragCancel: () {
          if (_dragging) setState(() => _dragging = false);
          widget.onDone();
        },
        onDoubleTap: widget.onReset,
        child: SizedBox(
          width: 12,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: active ? 3 : 1,
              height: double.infinity,
              color: active
                  ? theme.colorScheme.primary
                  : (widget.isDark
                      ? const Color(0xFF334155)
                      : const Color(0xFFE2E8F0)),
            ),
          ),
        ),
      ),
    );
  }
}
