import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/numbers/number_data.dart';
import '../../core/numbers/number_model.dart';
import '../../providers/numbers_provider.dart';
import '../widgets/numbers_sections.dart';

/// The number module's list side.
///
/// On the desktop layout this fills the middle pane: pick a category, then a
/// card — the sentence and the drill live in the detail pane. On a phone the
/// same widget carries all three sections behind a small selector, because there
/// is no second pane to put them in.
class NumbersScreen extends StatefulWidget {
  final bool isPaneView;

  const NumbersScreen({super.key, this.isPaneView = false});

  @override
  State<NumbersScreen> createState() => _NumbersScreenState();
}

class _NumbersScreenState extends State<NumbersScreen> {
  int _section = 0;

  static const List<String> _sectionLabels = ['分类展示', '自由输入', '数字训练'];

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NumbersProvider>();

    return Scaffold(
      appBar: widget.isPaneView
          ? null
          : AppBar(
              title: const Text('数字发音与训练', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
      body: Column(
        children: [
          if (!widget.isPaneView) _buildSectionSelector(context),
          if (widget.isPaneView || _section == 0) _buildCategoryBar(context, provider),
          Expanded(
            child: widget.isPaneView
                ? _buildExampleGrid(context, provider)
                : switch (_section) {
                    0 => _buildExampleGrid(context, provider),
                    1 => const SingleChildScrollView(
                        padding: EdgeInsets.all(16),
                        child: NumbersInputSection(),
                      ),
                    _ => const SingleChildScrollView(
                        padding: EdgeInsets.all(16),
                        child: NumbersTrainingSection(),
                      ),
                  },
          ),
        ],
      ),
    );
  }

  Widget _buildSectionSelector(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SegmentedButton<int>(
        segments: [
          for (var i = 0; i < _sectionLabels.length; i++)
            ButtonSegment(
              value: i,
              label: Text(_sectionLabels[i], style: const TextStyle(fontSize: 12)),
            ),
        ],
        selected: {_section},
        showSelectedIcon: false,
        onSelectionChanged: (selection) => setState(() => _section = selection.first),
      ),
    );
  }

  Widget _buildCategoryBar(BuildContext context, NumbersProvider provider) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2430) : Colors.white,
        border: Border(bottom: BorderSide(color: borderColor(isDark))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.numbers_rounded, size: 17, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              const Text(
                '数字表达方式分类',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '点击卡片查看/选中，点「英音」「美音」试听',
                  style: TextStyle(fontSize: 11.5, color: theme.hintColor),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              FilterChip(
                label: Text('全部 (${NumberData.allExamples.length})',
                    style: const TextStyle(fontSize: 11.5)),
                selected: provider.category == null,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onSelected: (_) => provider.selectCategory(null),
              ),
              for (final category in NumberCategory.values)
                FilterChip(
                  label: Text(
                    '${category.labelZh} (${NumberData.getByCategory(category).length})',
                    style: const TextStyle(fontSize: 11.5),
                  ),
                  selected: provider.category == category,
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onSelected: (_) => provider.selectCategory(
                    provider.category == category ? null : category,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildExampleGrid(BuildContext context, NumbersProvider provider) {
    final examples = provider.visibleExamples;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final example in examples)
            NumberExampleCard(
              example: example,
              selected: provider.selected == example,
              onTap: () {
                provider.selectExample(example);
                // On a phone there is no detail pane to update, so tapping the
                // card reads the sentence out immediately. A rule card has no
                // sentence of its own — its samples carry their own buttons.
                final reading = NumberData.readingOf(example);
                if (!widget.isPaneView && reading != null) {
                  provider.playReading(reading);
                }
              },
            ),
        ],
      ),
    );
  }
}
