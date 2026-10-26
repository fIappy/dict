import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/platform/ai_window_launcher.dart';
import '../../core/themes/theme_service.dart';
import '../../providers/dictionary_provider.dart';
import '../../providers/themes_provider.dart';
import 'ai_practice_screen.dart';
import 'word_detail_screen.dart';

/// 主题词汇: pick a theme (通用 / 动作与变化 / 科学与技术 …), then read its words
/// in COCA frequency order.
class ThemesScreen extends StatefulWidget {
  final bool isPaneView;
  final void Function(String word)? onSelectWord;

  const ThemesScreen({super.key, this.isPaneView = false, this.onSelectWord});

  @override
  State<ThemesScreen> createState() => _ThemesScreenState();
}

class _ThemesScreenState extends State<ThemesScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
              onAiPractice: () => _openAiPractice(context, scene),
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
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          Expanded(
            child: provider.isLoading
                ? const Center(child: CircularProgressIndicator())
                : scene == null
                ? _buildSceneList(context, provider, isDark)
                : _buildSceneDetail(context, provider),
          ),
          if (!provider.isLoading)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
              child: Text(
                '${provider.sceneCount} 个场景 · ${provider.totalWords} 条归属 · '
                '词表来自 ${provider.source}（按词频排序）',
                style: TextStyle(
                  fontSize: 11,
                  color: theme.hintColor,
                  height: 1.4,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSceneList(
    BuildContext context,
    ThemesProvider provider,
    bool isDark,
  ) {
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
            subtitle: scene.hint.isEmpty
                ? null
                : Text(
                    scene.hint,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: theme.hintColor,
                      height: 1.35,
                    ),
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
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: theme.hintColor,
                ),
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
    // A flat theme holds one group: its words are the page, with nothing to
    // fold open first.
    if (groups.length == 1) {
      final group = groups.first;
      return ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        children: [
          if (provider.facetPageCount(group) > 1)
            _facetPager(context, provider, group),
          const SizedBox(height: 2),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final word in provider.facetWords(group))
                ActionChip(
                  label: Text(word, style: const TextStyle(fontSize: 12.5)),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onPressed: () => _onWordTapped(context, word),
                ),
            ],
          ),
        ],
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      itemCount: groups.length,
      itemBuilder: (context, index) {
        final group = groups[index];
        final expanded = provider.isFacetExpanded(group.id);
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: () => provider.toggleFacet(group.id),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Icon(
                        expanded
                            ? Icons.expand_more_rounded
                            : Icons.chevron_right_rounded,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 2),
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
                        '${group.words.length}',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: theme.hintColor,
                        ),
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
                ),
              ),
              if (expanded) ...[
                if (provider.facetPageCount(group) > 1)
                  _facetPager(context, provider, group),
                const SizedBox(height: 2),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final word in provider.facetWords(group))
                      ActionChip(
                        label: Text(
                          word,
                          style: const TextStyle(fontSize: 12.5),
                        ),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        onPressed: () => _onWordTapped(context, word),
                      ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  /// 50 words a page means a big facet runs to dozens of pages, where
  /// next-page-only navigation is useless. Tapping the label asks for a page.
  Future<void> _jumpToPage(
    BuildContext context,
    ThemesProvider provider,
    ThemeGroup group,
  ) async {
    final target = await showDialog<int>(
      context: context,
      builder: (_) => _PageJumpDialog(
        page: provider.facetPage(group) + 1,
        count: provider.facetPageCount(group),
      ),
    );
    if (target != null) provider.setFacetPage(group, target - 1);
  }

  /// Pager for one long facet. It sits above the chips so flipping a page never
  /// scrolls the control out of reach.
  Widget _facetPager(
    BuildContext context,
    ThemesProvider provider,
    ThemeGroup group,
  ) {
    final theme = Theme.of(context);
    final page = provider.facetPage(group);
    final count = provider.facetPageCount(group);
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left_rounded, size: 18),
          tooltip: '上一页',
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          onPressed: page == 0
              ? null
              : () => provider.setFacetPage(group, page - 1),
        ),
        InkWell(
          onTap: () => _jumpToPage(context, provider, group),
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Text(
              '第 ${page + 1} / $count 页',
              style: TextStyle(fontSize: 11.5, color: theme.hintColor),
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right_rounded, size: 18),
          tooltip: '下一页',
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          onPressed: page >= count - 1
              ? null
              : () => provider.setFacetPage(group, page + 1),
        ),
      ],
    );
  }
}

  /// Desktop gets a window of its own (one per theme, so the dictionary stays
  /// usable); everything else falls back to a normal page.
  Future<void> _openAiPractice(BuildContext context, ThemeScene scene) async {
    if (await openAiWindow(scene.id)) return;
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => AiPracticeScreen(scene: scene)),
    );
  }

class _SceneHeader extends StatelessWidget {
  const _SceneHeader({
    required this.scene,
    required this.wordCount,
    required this.onBack,
    required this.isDark,
    required this.onAiPractice,
  });

  final ThemeScene scene;
  final int wordCount;
  final VoidCallback onBack;
  final bool isDark;
  final VoidCallback onAiPractice;

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
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  scene.hint,
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.hintColor,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.auto_awesome_rounded, size: 18),
            tooltip: 'AI 练习：造句与主题短文',
            visualDensity: VisualDensity.compact,
            onPressed: onAiPractice,
          ),
        ],
      ),
    );
  }
}

/// The page prompt. It owns its controller: disposing one as soon as
/// `showDialog` returns tears it down while the route is still animating out.
class _PageJumpDialog extends StatefulWidget {
  const _PageJumpDialog({required this.page, required this.count});

  final int page;
  final int count;

  @override
  State<_PageJumpDialog> createState() => _PageJumpDialogState();
}

class _PageJumpDialogState extends State<_PageJumpDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: '${widget.page}',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() =>
      Navigator.pop(context, int.tryParse(_controller.text.trim()));

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        '跳到第几页（共 ${widget.count} 页）',
        style: const TextStyle(fontSize: 15),
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        style: const TextStyle(fontSize: 13),
        decoration: const InputDecoration(
          isDense: true,
          border: OutlineInputBorder(),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('跳转')),
      ],
    );
  }
}