import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/search_result.dart';
import '../../providers/dictionary_provider.dart';
import '../../providers/history_provider.dart';
import 'word_detail_screen.dart';

class SearchScreen extends StatefulWidget {
  final bool isPaneView;
  final void Function(String word)? onSelectWord;

  const SearchScreen({
    super.key,
    this.isPaneView = false,
    this.onSelectWord,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  static const List<String> _quickWords = [
    'abandon', 'accelerate', 'accommodation', 'aesthetic', 'challenge',
    'computer', 'contemporary', 'dictionary', 'environment', 'facilitate',
    'hello', 'infrastructure', 'perspective', 'significant', 'virtual',
  ];

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final dictProvider = context.read<DictionaryProvider>();
      dictProvider.onSearchQueryChanged(_controller.text);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onWordChosen(String word) {
    final dictProvider = context.read<DictionaryProvider>();
    final histProvider = context.read<HistoryProvider>();

    dictProvider.lookupWord(word);
    histProvider.addHistory(word);

    if (widget.onSelectWord != null) {
      widget.onSelectWord!(word);
    } else if (!widget.isPaneView) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => WordDetailScreen(word: word),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final dictProvider = context.watch<DictionaryProvider>();
    final histProvider = context.watch<HistoryProvider>();

    return Scaffold(
      appBar: widget.isPaneView
          ? null
          : AppBar(
              title: const Text('本地词典查词', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
      body: Column(
        children: [
          // Search Input Bar
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E2430) : Colors.white,
              border: Border(
                bottom: BorderSide(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                ),
              ),
            ),
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              autofocus: !widget.isPaneView,
              style: const TextStyle(fontSize: 16),
              decoration: InputDecoration(
                hintText: '输入单词进行部分/前缀/模糊匹配...',
                hintStyle: TextStyle(
                  color: isDark ? Colors.white38 : Colors.black38,
                  fontSize: 15,
                ),
                prefixIcon: const Icon(Icons.search_rounded, size: 22),
                suffixIcon: _controller.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 20),
                        onPressed: () {
                          _controller.clear();
                          _focusNode.requestFocus();
                        },
                      )
                    : null,
                filled: true,
                fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          // Results List or Recommendations
          Expanded(
            child: _controller.text.trim().isEmpty
                ? _buildEmptyState(theme, isDark, histProvider)
                : _buildResultsList(theme, isDark, dictProvider),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme, bool isDark, HistoryProvider histProvider) {
    final recent = histProvider.items;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (recent.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '最近查询',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              TextButton(
                onPressed: () => histProvider.clearAll(),
                child: const Text('清空', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: recent.take(12).map((item) {
              return ActionChip(
                avatar: const Icon(Icons.history_rounded, size: 16),
                label: Text(item.word),
                onPressed: () => _onWordChosen(item.word),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
        ],

        const Text(
          '高频核心词推荐',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _quickWords.map((word) {
            return ActionChip(
              label: Text(word),
              onPressed: () => _onWordChosen(word),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildResultsList(ThemeData theme, bool isDark, DictionaryProvider dictProvider) {
    final results = dictProvider.searchResults;

    if (results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.search_off_rounded, size: 48, color: theme.hintColor),
              const SizedBox(height: 12),
              Text(
                '未找到匹配 "${_controller.text}" 的词汇',
                style: TextStyle(color: theme.hintColor),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      itemCount: results.length,
      separatorBuilder: (_, _) => Divider(
        height: 1,
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
      ),
      itemBuilder: (context, index) {
        final item = results[index];
        final isSelected = dictProvider.currentWord?.toLowerCase() == item.word.toLowerCase();

        return ListTile(
          dense: true,
          selected: isSelected,
          selectedTileColor: theme.colorScheme.primaryContainer.withValues(alpha: 0.25),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          title: Row(
            children: [
              Text(
                item.word,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                  fontSize: 15,
                  color: isSelected ? theme.colorScheme.primary : null,
                ),
              ),
              const SizedBox(width: 8),
              _buildMatchBadge(item.matchType, theme),
              if (item.frequencyBadge != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    item.frequencyBadge!,
                    style: TextStyle(fontSize: 10, color: theme.hintColor),
                  ),
                ),
              ],
            ],
          ),
          subtitle: item.briefDefinition != null
              ? Text(
                  item.briefDefinition!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                )
              : null,
          trailing: const Icon(Icons.chevron_right_rounded, size: 18),
          onTap: () => _onWordChosen(item.word),
        );
      },
    );
  }

  Widget _buildMatchBadge(SearchMatchType matchType, ThemeData theme) {
    String label;
    Color color;

    switch (matchType) {
      case SearchMatchType.exact:
        label = '精确';
        color = const Color(0xFF16A34A);
        break;
      case SearchMatchType.prefix:
        label = '前缀';
        color = const Color(0xFF2563EB);
        break;
      case SearchMatchType.substring:
        label = '包含';
        color = const Color(0xFFD97706);
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}
