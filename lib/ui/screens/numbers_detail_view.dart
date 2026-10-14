import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/numbers/number_model.dart';
import '../../providers/numbers_provider.dart';
import '../widgets/numbers_sections.dart';
import 'numbers_screen.dart';

/// The number module's wide side: the current sentence at the top, then the free
/// input box and the training drill.
///
/// On the desktop layout this is the right pane next to [NumbersScreen]; tapping
/// a card on the left or typing on the right both update the sentence here.
class NumbersDetailView extends StatelessWidget {
  final bool isPaneView;

  const NumbersDetailView({super.key, this.isPaneView = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = context.watch<NumbersProvider>();
    final selected = provider.selected;
    final reading = provider.currentReading;

    final content = SelectionArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. The sentence currently in focus (selected card, or last lookup).
            Row(
              children: [
                Icon(Icons.record_voice_over_rounded, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                const Text(
                  '当前读法',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '点「英音」「美音」分别试听，语速与「数字训练」共用',
                    style: TextStyle(fontSize: 11.5, color: theme.hintColor),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (reading != null && provider.lookup != null)
              NumberReadingCard(reading: reading)
            else if (selected != null && selected.kind != NumberCardKind.number)
              // A vocabulary word or a rule: show the card itself, bigger.
              NumberExampleCard(example: selected, width: 420, large: true)
            else if (reading != null)
              NumberReadingCard(reading: reading)
            else
              Text(
                '先在左侧选择一类数字表达方式，或在下面输入任意数字。',
                style: TextStyle(fontSize: 13, color: theme.hintColor),
              ),

            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 16),

            // 2. Free input: any number becomes an English sentence.
            const NumbersInputSection(),

            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 16),

            // 3. The drill.
            const NumbersTrainingSection(),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );

    if (isPaneView) return content;

    return Scaffold(
      appBar: AppBar(
        title: const Text('数字发音与训练', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: content,
    );
  }
}
