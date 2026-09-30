import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/frequency/frequency_service.dart';
import '../../core/models/history_item.dart';
import '../../providers/dictionary_provider.dart';
import '../../providers/history_provider.dart';
import 'word_detail_screen.dart';

class HistoryScreen extends StatefulWidget {
  final bool isPaneView;
  final void Function(String word)? onSelectWord;

  const HistoryScreen({
    super.key,
    this.isPaneView = false,
    this.onSelectWord,
  });

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final TextEditingController _filterController = TextEditingController();
  String _filterText = '';

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  void _onWordTapped(BuildContext context, String word) {
    final dictProvider = context.read<DictionaryProvider>();
    dictProvider.lookupWord(word, addToHistory: false);

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

  String _formatRelativeTime(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inMinutes < 1) {
      return '刚刚';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}分钟前';
    } else if (diff.inHours < 24 && now.day == dateTime.day) {
      return DateFormat('HH:mm').format(dateTime);
    } else if (diff.inDays <= 1 || (diff.inHours < 48 && now.day - dateTime.day == 1)) {
      return '昨天 ${DateFormat('HH:mm').format(dateTime)}';
    } else {
      return DateFormat('MM-dd HH:mm').format(dateTime);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final histProvider = context.watch<HistoryProvider>();
    final dictProvider = context.watch<DictionaryProvider>();

    var items = histProvider.items;
    if (_filterText.trim().isNotEmpty) {
      final q = _filterText.trim().toLowerCase();
      items = items.where((item) => item.word.toLowerCase().contains(q)).toList();
    }

    return Scaffold(
      body: Column(
        children: [
          // Top Header Bar
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Text(
                          '查词历史',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${histProvider.items.length}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (histProvider.items.isNotEmpty)
                      TextButton.icon(
                        icon: const Icon(Icons.delete_sweep_outlined, size: 16),
                        label: const Text('清空', style: TextStyle(fontSize: 12.5)),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.red[600],
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () => _confirmClear(context, histProvider),
                      ),
                  ],
                ),
                const SizedBox(height: 10),

                // Search Filter Input
                TextField(
                  controller: _filterController,
                  decoration: InputDecoration(
                    hintText: '过滤历史单词...',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    prefixIcon: const Icon(Icons.search_rounded, size: 18),
                    suffixIcon: _filterText.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            onPressed: () {
                              _filterController.clear();
                              setState(() => _filterText = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (val) {
                    setState(() => _filterText = val);
                  },
                ),
              ],
            ),
          ),

          // History List or Empty View
          Expanded(
            child: items.isEmpty
                ? _buildEmptyState(theme)
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => Divider(
                      height: 1,
                      color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                    ),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final isSelected = dictProvider.currentWord?.toLowerCase() == item.word.toLowerCase();
                      return _buildHistoryRow(context, item, isSelected, theme, isDark, histProvider);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryRow(
    BuildContext context,
    HistoryItem item,
    bool isSelected,
    ThemeData theme,
    bool isDark,
    HistoryProvider histProvider,
  ) {
    final freq = FrequencyService().getFrequency(item.word);
    final relativeTime = _formatRelativeTime(item.createdAt);

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _onWordTapped(context, item.word),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.25)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Word & Definition
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          item.word,
                          style: TextStyle(
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                            fontSize: 15,
                            color: isSelected ? theme.colorScheme.primary : null,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (freq?.cefr != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: _getCefrBgColor(freq!.cefr!, isDark),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            freq.cefr!,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ] else if (freq?.rank != null && freq!.rank! <= 5000) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            freq.frequencyLabel,
                            style: TextStyle(fontSize: 9.5, color: theme.hintColor),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (freq?.briefZh != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      freq!.briefZh!,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),

            // Time & Delete Button
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  relativeTime,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 15),
                  tooltip: '删除记录',
                  splashRadius: 14,
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  color: isDark ? Colors.white30 : Colors.black26,
                  hoverColor: Colors.red.withValues(alpha: 0.1),
                  onPressed: () => histProvider.deleteItem(item.id),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _getCefrBgColor(String cefr, bool isDark) {
    switch (cefr.toUpperCase()) {
      case 'A1':
      case 'A2':
        return isDark ? const Color(0xFF15803D) : const Color(0xFF16A34A);
      case 'B1':
      case 'B2':
        return isDark ? const Color(0xFF1D4ED8) : const Color(0xFF2563EB);
      case 'C1':
      case 'C2':
        return isDark ? const Color(0xFF7E22CE) : const Color(0xFF9333EA);
      default:
        return Colors.blueGrey;
    }
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history_toggle_off_rounded, size: 48, color: theme.hintColor),
            const SizedBox(height: 12),
            Text(
              _filterText.isNotEmpty ? '未找到相关历史记录' : '暂无查词历史',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              _filterText.isNotEmpty ? '尝试更换过滤关键词' : '在查词页面查询单词后，记录会自动出现在这里',
              style: TextStyle(fontSize: 12.5, color: theme.hintColor),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _confirmClear(BuildContext context, HistoryProvider histProvider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空历史记录'),
        content: const Text('确定要清空所有查询记录吗？此操作无法撤销。'),
        actions: [
          TextButton(
            child: const Text('取消'),
            onPressed: () => Navigator.pop(ctx),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('清空'),
            onPressed: () async {
              Navigator.pop(ctx);
              await histProvider.clearAll();
            },
          ),
        ],
      ),
    );
  }
}
