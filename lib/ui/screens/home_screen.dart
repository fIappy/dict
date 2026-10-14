import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/dictionary_provider.dart';
import '../../providers/favorites_provider.dart';
import '../../providers/history_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/frequency_provider.dart';
import '../../providers/ipa_provider.dart';
import '../../providers/alphabet_provider.dart';
import '../../providers/numbers_provider.dart';
import 'alphabet_detail_view.dart';
import 'alphabet_screen.dart';
import 'dictionary_manager_screen.dart';
import 'favorites_screen.dart';
import 'frequency_screen.dart';
import 'history_screen.dart';
import 'ipa_detail_view.dart';
import 'ipa_screen.dart';
import 'numbers_detail_view.dart';
import 'numbers_screen.dart';
import 'search_screen.dart';
import 'word_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  double _middlePaneWidth = 360.0;
  bool _isDividerHovered = false;
  bool _isDividerDragging = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DictionaryProvider>().initialize();
      context.read<FavoritesProvider>().initialize();
      context.read<HistoryProvider>().initialize();
      context.read<FrequencyProvider>().initialize();
      context.read<NumbersProvider>().initialize();
      context.read<SettingsProvider>().initialize();
    });
  }

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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final dictProvider = context.watch<DictionaryProvider>();
    final ipaProvider = context.watch<IpaProvider>();
    final alphabetProvider = context.watch<AlphabetProvider>();
    final settings = context.watch<SettingsProvider>();
    return Scaffold(
      body: Row(
        children: [
          // 1. Navigation Rail
          NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) {
              setState(() => _selectedIndex = index);
            },
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
                      isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                      color: theme.colorScheme.primary,
                    ),
                    tooltip: isDark ? '切换到浅色模式' : '切换到深色模式',
                    onPressed: () {
                      settings.setThemeMode(isDark ? ThemeMode.light : ThemeMode.dark);
                    },
                  ),
                ),
              ),
            ),
            // Eight destinations no longer fit the 720 px default window with
            // a label under every icon (历史/词典 were already clipped before the
            // numbers module was added). Showing the label of the selected item
            // only — the rest keep their tooltips — fits them all. `scrollable`
            // is not an option here: it hands the trailing widget unbounded
            // height, and the trailing widget is an Expanded theme toggle.
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
                icon: Icon(Icons.folder_copy_outlined),
                selectedIcon: Icon(Icons.folder_copy_rounded),
                label: Text('词典'),
              ),
            ],
          ),

          const VerticalDivider(width: 1),

          // 2. Middle Navigation Pane (Search list, Favorites list, etc.)
          SizedBox(
            width: _middlePaneWidth,
            child: _buildMiddlePane(),
          ),

          // Draggable vertical divider splitter
          MouseRegion(
            cursor: SystemMouseCursors.resizeColumn,
            onEnter: (_) => setState(() => _isDividerHovered = true),
            onExit: (_) => setState(() => _isDividerHovered = false),
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragStart: (_) => setState(() => _isDividerDragging = true),
              onHorizontalDragEnd: (_) => setState(() => _isDividerDragging = false),
              onHorizontalDragCancel: () => setState(() => _isDividerDragging = false),
              onHorizontalDragUpdate: (details) {
                setState(() {
                  // Keep right detail pane at least 360px wide
                  final maxW = (constraints.maxWidth - 440.0).clamp(280.0, 900.0);
                  final nextW = _middlePaneWidth + details.delta.dx;
                  _middlePaneWidth = nextW.clamp(220.0, maxW);
                });
              },
              onDoubleTap: () {
                setState(() {
                  _middlePaneWidth = 360.0;
                });
              },
              child: Container(
                width: 12,
                color: Colors.transparent,
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: (_isDividerHovered || _isDividerDragging) ? 3 : 1,
                    height: double.infinity,
                    color: (_isDividerHovered || _isDividerDragging)
                        ? theme.colorScheme.primary
                        : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: _selectedIndex == 3
                ? IpaDetailView(
                    isPaneView: true,
                    phoneme: ipaProvider.currentPhoneme,
                  )
                : (_selectedIndex == 4
                    ? AlphabetDetailView(
                        isPaneView: true,
                        letter: alphabetProvider.currentLetter,
                      )
                    : (_selectedIndex == 5
                        ? const NumbersDetailView(isPaneView: true)
                        : WordDetailScreen(
                            isPaneView: true,
                            word: dictProvider.currentWord ?? 'hello',
                          ))),
          ),
        ],
      ),
    );
  }

  Widget _buildMiddlePane() {
    switch (_selectedIndex) {
      case 0:
        return const SearchScreen(isPaneView: true);
      case 1:
        return const FavoritesScreen(isPaneView: true);
      case 2:
        return const FrequencyScreen(isPaneView: true);
      case 3:
        return const IpaScreen(isPaneView: true);
      case 4:
        return const AlphabetScreen(isPaneView: true);
      case 5:
        return const NumbersScreen(isPaneView: true);
      case 6:
        return const HistoryScreen(isPaneView: true);
      case 7:
        return const DictionaryManagerScreen();
      default:
        return const SearchScreen(isPaneView: true);
    }
  }

  Widget _buildMobileLayout(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: const [
          SearchScreen(isPaneView: false),
          FavoritesScreen(isPaneView: false),
          FrequencyScreen(isPaneView: false),
          IpaScreen(isPaneView: false),
          AlphabetScreen(isPaneView: false),
          NumbersScreen(isPaneView: false),
          HistoryScreen(isPaneView: false),
          DictionaryManagerScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() => _selectedIndex = index);
        },
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
            icon: Icon(Icons.folder_copy_outlined),
            selectedIcon: Icon(Icons.folder_copy_rounded),
            label: '词典',
          ),
        ],
      ),
    );
  }
}
