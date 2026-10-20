import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/themes/theme_service.dart';
import '../../providers/dictionary_provider.dart';
import '../../providers/themes_provider.dart';
import 'word_detail_screen.dart';

/// 主题词汇: pick a situation (居家生活 / 校园学习 / 医疗健康 …), then read its
/// vocabulary split into 人 / 事 / 物 / 动作 / 情况 / 虚拟, each facet in COCA
/// frequency order.
class ThemesScreen extends StatefulWidget {
  final bool isPaneView;
  final void Function(String word)? onSelectWord;

  const ThemesScreen({
    super.key,
    this.isPaneView = false,
    this.onSelectWord,
  });

  @override
  State<ThemesScreen> createState() => _ThemesScreenState();
}

class _ThemesScreenState extends State<ThemesScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _detailScroll = ScrollController();

  @override
  void dispose() {
    _searchController.dispose();
    _detailScroll.dispose();
    super.dispose();
  }

  /// Paging replaces the word list in place; without this the reader would
  /// land at the same scroll offset on the next page.
  void _goPage(ThemesProvider provider, int page) {
    provider.setPage(page);
    if (_detailScroll.hasClients) _detailScroll.jumpTo(0);
  }

  void _onWordTapped(BuildContext context, String word) {
    final dictProvider = context.read<DictionaryProvider>();
    dictProvider.lookupWord(word);

    if (widget.onSelectWord != null) {
      widget.onSelectWord!(word);
    } else if (!widget.isPaneView) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => WordDetailScreen(word: word)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final provider = context.watch<ThemesProvider>();
    final scene = provider.selectedScene;

    return Scaffold(
      appBar: widget.isPaneView
          ? null
          : AppBar(
              title: const Text(
                '主题词汇',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
      body: Column(
        children: [
          if (scene != null)
            _SceneHeader(
              scene: scene,
              wordCount: provider.visibleWordCount,
              onBack: provider.backToScenes,
              isDark: isDark,
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: TextField(
              controller: _searchController,
              onChanged: provider.setQuery,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
                hintText: scene == null
                    ? '搜索场景，或直接搜一个词…'
                    : '在「${scene.label}」里搜词…',
                hintStyle: const TextStyle(fontSize: 12.5),
                suffixIcon: provider.query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded, size: 16),
                        tooltip: '清空',
                        onPressed: () {
                          _searchController.clear();
                          provider.setQuery('');
                        },
                      ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          Expanded(
            child: provider.isLoading
                ? const Center(child: CircularProgressIndicator())
                : scene == null
                    ? _buildSceneList(context, provider, isDark)
                    : Column(
                        children: [
                          Expanded(child: _buildSceneDetail(context, provider)),
                          if (provider.pageCount > 1)
                            _buildPager(context, provider),
                        ],
                      ),
          ),
          if (!provider.isLoading)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
              child: Text(
                '${provider.sceneCount} 个场景 · ${provider.totalWords} 条归属 · '
                '词表来自 ${provider.source}（按词频排序）',
                style: TextStyle(fontSize: 11, color: theme.hintColor, height: 1.4),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSceneList(BuildContext context, ThemesProvider provider, bool isDark) {
    final scenes = provider.visibleScenes;
    if (scenes.isEmpty) {
      return const Center(
        child: Text('没有匹配的场景', style: TextStyle(fontSize: 13)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      itemCount: scenes.length,
      itemBuilder: (context, index) {
        final scene = scenes[index];
        final theme = Theme.of(context);
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          elevation: 0,
          color: isDark ? const Color(0xFF1E2430) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
              color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
            ),
          ),
          child: ListTile(
            dense: true,
            title: Text(
              scene.label,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              scene.hint,
              style: TextStyle(fontSize: 11.5, color: theme.hintColor, height: 1.35),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${scene.count}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded, size: 18, color: theme.hintColor),
              ],
            ),
            onTap: () => provider.select(scene.id),
          ),
        );
      },
    );
  }

  Widget _buildSceneDetail(BuildContext context, ThemesProvider provider) {
    final groups = provider.visibleGroups;
    if (groups.isEmpty) {
      return const Center(
        child: Text('这个场景里没有匹配的词', style: TextStyle(fontSize: 13)),
      );
    }
    final theme = Theme.of(context);
    return ListView.builder(
      controller: _detailScroll,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      itemCount: groups.length,
      itemBuilder: (context, index) {
        final group = groups[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    group.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _groupCountLabel(provider, group),
                    style: TextStyle(fontSize: 11.5, color: theme.hintColor),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Divider(
                      color: theme.dividerColor.withValues(alpha: 0.35),
                      height: 1,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final word in group.words)
                    ActionChip(
                      label: Text(word, style: const TextStyle(fontSize: 12.5)),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onPressed: () => _onWordTapped(context, word),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  /// A facet can run past a page boundary; show "shown / total" so a partial
  /// facet is not read as a short one.
  String _groupCountLabel(ThemesProvider provider, ThemeGroup group) {
    final total = provider.groupTotalWords(group.id);
    final shown = group.words.length;
    return shown < total ? '$shown / $total' : '$shown';
  }

  /// Page controls for scenes long enough to be paged (see
  /// [ThemesProvider.pageWordThreshold]). Hidden entirely for short scenes.
  Widget _buildPager(BuildContext context, ThemesProvider provider) {
    final theme = Theme.of(context);
    final page = provider.page;
    final count = provider.pageCount;
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.4)),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(6, 2, 6, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded, size: 20),
            tooltip: '上一页',
            visualDensity: VisualDensity.compact,
            onPressed: page == 0 ? null : () => _goPage(provider, page - 1),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              '第 ${page + 1} / $count 页',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded, size: 20),
            tooltip: '下一页',
            visualDensity: VisualDensity.compact,
            onPressed: page >= count - 1 ? null : () => _goPage(provider, page + 1),
          ),
        ],
      ),
    );
  }
}

class _SceneHeader extends StatelessWidget {
  const _SceneHeader({
    required this.scene,
    required this.wordCount,
    required this.onBack,
    required this.isDark,
  });

  final ThemeScene scene;
  final int wordCount;
  final VoidCallback onBack;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2430) : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
            tooltip: '返回场景列表',
            visualDensity: VisualDensity.compact,
            onPressed: onBack,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${scene.label} · $wordCount 词',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
                Text(
                  scene.hint,
                  style: TextStyle(fontSize: 11, color: theme.hintColor, height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
