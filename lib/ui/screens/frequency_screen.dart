import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/audio/audio_manager.dart';
import '../../core/frequency/frequency_service.dart';
import '../../providers/dictionary_provider.dart';
import '../../providers/frequency_provider.dart';
import 'word_detail_screen.dart';

class FrequencyScreen extends StatefulWidget {
  final bool isPaneView;
  final void Function(String word)? onSelectWord;

  const FrequencyScreen({
    super.key,
    this.isPaneView = false,
    this.onSelectWord,
  });

  @override
  State<FrequencyScreen> createState() => _FrequencyScreenState();
}

class _FrequencyScreenState extends State<FrequencyScreen> {
  final AudioManager _audio = AudioManager();
  final TextEditingController _startRangeCtrl = TextEditingController();
  final TextEditingController _endRangeCtrl = TextEditingController();
  final TextEditingController _jumpPageCtrl = TextEditingController();
  bool _isEditingRange = false;

  @override
  void dispose() {
    _startRangeCtrl.dispose();
    _endRangeCtrl.dispose();
    _jumpPageCtrl.dispose();
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
        MaterialPageRoute(
          builder: (_) => WordDetailScreen(word: word),
        ),
      );
    }
  }

  void _applyRange(FrequencyProvider freqProvider) {
    final s = int.tryParse(_startRangeCtrl.text.trim()) ?? freqProvider.startRank;
    final e = int.tryParse(_endRangeCtrl.text.trim()) ?? freqProvider.endRank;
    if (s > e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('起始词频排名不能大于结束排名')),
      );
      return;
    }
    freqProvider.setRange(s, e);
    setState(() => _isEditingRange = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final freqProvider = context.watch<FrequencyProvider>();
    final dictProvider = context.watch<DictionaryProvider>();

    final items = freqProvider.currentPageItems;
    final curPage = freqProvider.currentPage;
    final totalPages = freqProvider.totalPages;

    return Scaffold(
      body: Column(
        children: [
          // Top Range Controls Bar
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
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
                        Icon(Icons.trending_up_rounded, color: theme.colorScheme.primary, size: 20),
                        const SizedBox(width: 8),
                        const Text(
                          '词频排行榜',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ],
                    ),
                    TextButton.icon(
                      icon: Icon(
                        _isEditingRange ? Icons.check_circle_outline_rounded : Icons.tune_rounded,
                        size: 16,
                      ),
                      label: Text(_isEditingRange ? '完成' : '调整范围', style: const TextStyle(fontSize: 12.5)),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () {
                        setState(() {
                          if (!_isEditingRange) {
                            _startRangeCtrl.text = '${freqProvider.startRank}';
                            _endRangeCtrl.text = '${freqProvider.endRank}';
                            _isEditingRange = true;
                          } else {
                            _applyRange(freqProvider);
                          }
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Range indicator or inline inputs
                if (!_isEditingRange)
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '排名范围: #${freqProvider.startRank} ~ #${freqProvider.endRank}',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '共 ${freqProvider.totalItems} 词',
                        style: TextStyle(fontSize: 12, color: theme.hintColor),
                      ),
                    ],
                  )
                else ...[
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _startRangeCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: '起始排名',
                            hintText: '如 400',
                            isDense: true,
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          ),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6),
                        child: Text('~', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _endRangeCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: '结束排名',
                            hintText: '如 1000',
                            isDense: true,
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          minimumSize: Size.zero,
                        ),
                        onPressed: () => _applyRange(freqProvider),
                        child: const Text('应用', style: TextStyle(fontSize: 12.5)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Preset Chips
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildPresetChip('前100词', 1, 100, freqProvider),
                        _buildPresetChip('前500词', 1, 500, freqProvider),
                        _buildPresetChip('400-1000', 400, 1000, freqProvider),
                        _buildPresetChip('1000-3000', 1000, 3000, freqProvider),
                        _buildPresetChip('5000-6000', 5000, 6000, freqProvider),
                        _buildPresetChip('6000-10000', 6000, 10000, freqProvider),
                        _buildPresetChip('10000-20000', 10000, 20000, freqProvider),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          // 20-words per page List
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Text(
                      '当前范围无匹配词汇',
                      style: TextStyle(color: theme.hintColor),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => Divider(
                      height: 1,
                      color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                    ),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final isSelected = dictProvider.currentWord?.toLowerCase() == item.word.toLowerCase();
                      return _buildWordTile(context, item, isSelected, theme, isDark);
                    },
                  ),
          ),

          // Bottom Pagination Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E2430) : Colors.white,
              border: Border(
                top: BorderSide(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Prev button
                IconButton.outlined(
                  icon: const Icon(Icons.chevron_left_rounded, size: 20),
                  tooltip: '上一页',
                  style: IconButton.styleFrom(
                    padding: const EdgeInsets.all(6),
                    minimumSize: const Size(32, 32),
                  ),
                  onPressed: curPage > 1 ? () => freqProvider.previousPage() : null,
                ),

                // Page Indicator & Jump button
                InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => _showJumpDialog(context, freqProvider, totalPages),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '第 $curPage / $totalPages 页',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.unfold_more_rounded, size: 14, color: theme.hintColor),
                      ],
                    ),
                  ),
                ),

                // Next button
                IconButton.outlined(
                  icon: const Icon(Icons.chevron_right_rounded, size: 20),
                  tooltip: '下一页',
                  style: IconButton.styleFrom(
                    padding: const EdgeInsets.all(6),
                    minimumSize: const Size(32, 32),
                  ),
                  onPressed: curPage < totalPages ? () => freqProvider.nextPage() : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetChip(String label, int start, int end, FrequencyProvider provider) {
    final isCurrent = provider.startRank == start && provider.endRank == end;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ActionChip(
        label: Text(label, style: const TextStyle(fontSize: 11)),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
        backgroundColor: isCurrent ? Theme.of(context).colorScheme.primaryContainer : null,
        onPressed: () {
          provider.setRange(start, end);
          setState(() {
            _startRangeCtrl.text = '$start';
            _endRangeCtrl.text = '$end';
            _isEditingRange = false;
          });
        },
      ),
    );
  }

  Widget _buildWordTile(
    BuildContext context,
    WordFrequencyInfo item,
    bool isSelected,
    ThemeData theme,
    bool isDark,
  ) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _onWordTapped(context, item.word),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.25)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Rank Badge: #1, #2, #400...
            Container(
              width: 46,
              alignment: Alignment.centerLeft,
              child: Text(
                '#${item.rank ?? ''}',
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                  color: isSelected
                      ? theme.colorScheme.primary
                      : (isDark ? Colors.amber[300] : Colors.orange[800]),
                ),
              ),
            ),

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
                      if (item.cefr != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: _getCefrBgColor(item.cefr!, isDark),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            item.cefr!,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (item.briefZh != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.briefZh!,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),

            // Audio speaker button
            IconButton(
              icon: const Icon(Icons.volume_up_rounded, size: 18),
              tooltip: '播放读音',
              splashRadius: 16,
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              onPressed: () => _audio.playWord(word: item.word),
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

  void _showJumpDialog(BuildContext context, FrequencyProvider provider, int totalPages) {
    _jumpPageCtrl.text = '${provider.currentPage}';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('跳转到指定页'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('输入页码 (1 ~ $totalPages):', style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 8),
            TextField(
              controller: _jumpPageCtrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            child: const Text('取消'),
            onPressed: () => Navigator.pop(ctx),
          ),
          FilledButton(
            child: const Text('跳转'),
            onPressed: () {
              final p = int.tryParse(_jumpPageCtrl.text.trim());
              if (p != null) {
                provider.setPage(p);
              }
              Navigator.pop(ctx);
            },
          ),
        ],
      ),
    );
  }
}
