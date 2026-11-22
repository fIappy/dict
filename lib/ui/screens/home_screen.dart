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
  /// (it sits in the rail's trailing corner), the phone bar has ten.
  static const int _railDestinationCount = 9;
  static const int _mobileDestinationCount = 10;

  int _selectedIndex = 0;
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
  Future<void> _restoreLayout() async {
    final section = await UiMemory.readInt(UiMemory.section);
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
    unawaited(UiMemory.writeInt(UiMemory.section, index));
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
              child: _DesktopRightPane(index: index),
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
        return const FavoritesScreen(isPaneView: true);
      case 2:
        return const FrequencyScreen(isPaneView: true);
      case 3:
        return const ThemesScreen(isPaneView: true);
      case 4:
        return const IpaScreen(isPaneView: true);
      case 5:
        return const AlphabetScreen(isPaneView: true);
      case 6:
        return const NumbersScreen(isPaneView: true);
      case 7:
        return const HistoryScreen(isPaneView: true);
      case 8:
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
        return const FavoritesScreen(isPaneView: false);
      case 2:
        return const FrequencyScreen(isPaneView: false);
      case 3:
        return const ThemesScreen(isPaneView: false);
      case 4:
        return const IpaScreen(isPaneView: false);
      case 5:
        return const AlphabetScreen(isPaneView: false);
      case 6:
        return const NumbersScreen(isPaneView: false);
      case 7:
        return const HistoryScreen(isPaneView: false);
      case 8:
        return const CustomScreen(isPaneView: false);
      case 9:
        return const SettingsScreen(isPaneView: true);
      default:
        return const SearchScreen(isPaneView: false);
    }
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
        // Ten destinations do not fit with a label under each; show the
        // selected one only, the same way the desktop rail does.
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
            icon: Icon(Icons.trending_up_rounded),
            label: '词频',
          ),
          NavigationDestination(
            icon: Icon(Icons.category_outlined),
            selectedIcon: Icon(Icons.category_rounded),
            label: '主题',
          ),
          NavigationDestination(
            icon: Icon(Icons.record_voice_over_outlined),
            selectedIcon: Icon(Icons.record_voice_over_rounded),
            label: '音标',
          ),
          NavigationDestination(
            icon: Icon(Icons.text_fields_outlined),
            selectedIcon: Icon(Icons.text_fields_rounded),
            label: '字母',
          ),
          NavigationDestination(
            icon: Icon(Icons.numbers_outlined),
            selectedIcon: Icon(Icons.numbers_rounded),
            label: '数字',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_rounded),
            label: '历史',
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
      // Nine destinations no longer fit the 720 px default window with
      // a label under every icon (历史/词典 were already clipped before the
      // numbers module was added). Showing the label of the selected item
      // only — the rest keep their tooltips — fits them all. `scrollable`
      // is not an option here: it hands the trailing widget unbounded
      // height, and the trailing widget is an Expanded settings button.
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
          icon: Icon(Icons.trending_up_rounded),
          selectedIcon: Icon(Icons.trending_up_rounded),
          label: Text('词频'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.category_outlined),
          selectedIcon: Icon(Icons.category_rounded),
          label: Text('主题'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.record_voice_over_outlined),
          selectedIcon: Icon(Icons.record_voice_over_rounded),
          label: Text('音标'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.text_fields_outlined),
          selectedIcon: Icon(Icons.text_fields_rounded),
          label: Text('字母'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.numbers_outlined),
          selectedIcon: Icon(Icons.numbers_rounded),
          label: Text('数字'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.history_rounded),
          selectedIcon: Icon(Icons.history_rounded),
          label: Text('历史'),
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
  const _DesktopRightPane({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    if (index == 4) {
      final phoneme = context.select((IpaProvider p) => p.currentPhoneme);
      return IpaDetailView(isPaneView: true, phoneme: phoneme);
    }
    if (index == 5) {
      final letter = context.select((AlphabetProvider p) => p.currentLetter);
      return AlphabetDetailView(isPaneView: true, letter: letter);
    }
    if (index == 6) {
      return const NumbersDetailView(isPaneView: true);
    }
    if (index == 8) {
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
