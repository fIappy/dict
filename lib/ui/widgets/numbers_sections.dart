import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/numbers/number_data.dart';
import '../../core/numbers/number_model.dart';
import '../../core/numbers/number_training.dart';
import '../../providers/numbers_provider.dart';
import '../../providers/settings_provider.dart';

/// The 英 /美音 colours the module uses everywhere, matching the IPA screen.
const Color kUkColor = Color(0xFF1E40AF);
const Color kUsColor = Color(0xFFB45309);

Color cardColor(bool isDark) => isDark ? const Color(0xFF1E2430) : Colors.white;
Color borderColor(bool isDark) => isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);

/// One sentence with a play button, labelled by accent.
class _AccentLine extends StatelessWidget {
  const _AccentLine({
    required this.flag,
    required this.accent,
    required this.text,
    required this.color,
    required this.reading,
  });

  final String flag;
  final String accent;
  final String text;
  final Color color;
  final NumberReading reading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final provider = context.watch<NumbersProvider>();
    final settings = context.watch<SettingsProvider>();
    // The engine is a settings-panel choice; the drill just follows it.
    provider.speechEngine = settings.speechEngine;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(flag, style: const TextStyle(fontSize: 13)),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text.isEmpty ? '—' : text,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 14,
              height: 1.45,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ),
        IconButton(
          icon: Icon(Icons.volume_up_rounded, size: 18, color: color),
          tooltip: accent == 'uk' ? '播放英音' : '播放美音',
          splashRadius: 16,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          onPressed: () => provider.playReading(reading, accent: accent),
        ),
      ],
    );
  }
}

/// A number and how it is said, with one play button per accent.
class NumberReadingCard extends StatelessWidget {
  const NumberReadingCard({
    super.key,
    required this.reading,
    this.showInput = true,
  });

  final NumberReading reading;

  /// The written form is redundant when the card is already inside the example
  /// it came from.
  final bool showInput;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: cardColor(isDark),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor(isDark)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showInput)
            Row(
              children: [
                Text(
                  reading.input,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    reading.category.labelZh,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          if (showInput) const SizedBox(height: 8),
          _AccentLine(
            flag: '英',
            accent: 'uk',
            text: reading.ukText,
            color: kUkColor,
            reading: reading,
          ),
          _AccentLine(
            flag: '美',
            accent: 'us',
            text: reading.usText,
            color: kUsColor,
            reading: reading,
          ),
          if (reading.note.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lightbulb_outline_rounded, size: 15, color: Colors.amber[700]),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    reading.note,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: isDark ? Colors.white60 : Colors.black54,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// One vocabulary word card: the word itself, the value it stands for, and one
/// play button per accent. Used for the forms that have to be learnt one by one
/// (`one`…`twelve`, `forty`, `twelfth`).
class NumberWordCard extends StatelessWidget {
  const NumberWordCard({
    super.key,
    required this.example,
    this.selected = false,
    this.onTap,
    this.width = 240,
    this.large = false,
  });

  final NumberExample example;
  final bool selected;
  final VoidCallback? onTap;
  final double width;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final provider = context.watch<NumbersProvider>();
    // A word card is always spoken as the word itself.
    final reading = NumberData.readingOf(example);
    void Function()? playsAccent(String accent) =>
        reading == null ? null : () => provider.playReading(reading, accent: accent);

    return Material(
      color: selected
          ? theme.colorScheme.primaryContainer.withValues(alpha: isDark ? 0.35 : 0.55)
          : cardColor(isDark),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          width: width,
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? theme.colorScheme.primary : borderColor(isDark),
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The word is the whole point of the card, so it gets the row:
              // `thirteenth` wraps to a second line instead of being cut off,
              // and the value moves under it.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      example.input,
                      style: TextStyle(
                        fontSize: large ? 28 : 20,
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.volume_up_rounded, size: 17, color: kUkColor),
                    tooltip: '英音',
                    splashRadius: 15,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                    onPressed: playsAccent('uk'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.volume_up_rounded, size: 17, color: kUsColor),
                    tooltip: '美音',
                    splashRadius: 15,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                    onPressed: playsAccent('us'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  example.value ?? '',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                example.hint,
                style: TextStyle(fontSize: large ? 13 : 11, color: theme.hintColor, height: 1.4),
                maxLines: large ? 4 : 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A rule card: one regular range taught once, with a few samples to try.
///
/// English numbers are regular from `twenty-one` up, so the range is described
/// instead of enumerated — the samples are what gets played, one at a time.
class NumberPatternCard extends StatelessWidget {
  const NumberPatternCard({
    super.key,
    required this.example,
    this.selected = false,
    this.onTap,
    this.width = 340,
    this.large = false,
  });

  final NumberExample example;
  final bool selected;
  final VoidCallback? onTap;
  final double width;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final provider = context.watch<NumbersProvider>();

    return Material(
      color: selected
          ? theme.colorScheme.primaryContainer.withValues(alpha: isDark ? 0.35 : 0.55)
          : cardColor(isDark),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          width: width,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? theme.colorScheme.primary : borderColor(isDark),
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF7C3AED).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      '规则',
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF7C3AED)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Rule titles can be long ("2010 起两种读法"), so they wrap
                  // instead of pushing the card wider than the grid column.
                  Expanded(
                    child: Text(
                      example.input,
                      style: TextStyle(fontSize: large ? 22 : 17, fontWeight: FontWeight.w800),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                example.hint,
                style: TextStyle(
                  fontSize: large ? 13.5 : 12,
                  height: 1.5,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final sample in example.samples)
                    InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => provider.playReading(NumberData.sampleReading(example, sample)),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: borderColor(isDark)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              sample,
                              style: const TextStyle(fontSize: 12.5, fontFamily: 'monospace'),
                            ),
                            const SizedBox(width: 4),
                            Icon(Icons.volume_up_rounded, size: 13, color: theme.colorScheme.primary),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A card in the 分类展示 grid: written number, vocabulary word or rule.
class NumberExampleCard extends StatelessWidget {
  const NumberExampleCard({
    super.key,
    required this.example,
    this.selected = false,
    this.onTap,
    this.width = 240,
    this.large = false,
  });

  final NumberExample example;
  final bool selected;
  final VoidCallback? onTap;
  final double width;
  final bool large;

  @override
  Widget build(BuildContext context) {
    switch (example.kind) {
      case NumberCardKind.word:
        return NumberWordCard(
          example: example,
          selected: selected,
          onTap: onTap,
          width: width,
          large: large,
        );
      case NumberCardKind.pattern:
        return NumberPatternCard(
          example: example,
          selected: selected,
          onTap: onTap,
          width: large ? width * 1.6 : width * 1.35,
          large: large,
        );
      case NumberCardKind.number:
        return _NumberSentenceCard(
          example: example,
          selected: selected,
          onTap: onTap,
          width: width,
        );
    }
  }
}

/// The original card: a written number with its 🇬🇧/🇺🇸 sentence.
class _NumberSentenceCard extends StatelessWidget {
  const _NumberSentenceCard({
    required this.example,
    required this.selected,
    this.onTap,
    this.width = 240,
  });

  final NumberExample example;
  final bool selected;
  final VoidCallback? onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final provider = context.watch<NumbersProvider>();
    final reading = NumberData.readingOf(example);

    return Material(
      color: selected
          ? theme.colorScheme.primaryContainer.withValues(alpha: isDark ? 0.35 : 0.55)
          : cardColor(isDark),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          width: width,
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? theme.colorScheme.primary : borderColor(isDark),
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      example.input,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'monospace',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.volume_up_rounded, size: 16, color: kUkColor),
                    tooltip: '英音',
                    splashRadius: 14,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                    onPressed: reading == null ? null : () => provider.playReading(reading, accent: 'uk'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.volume_up_rounded, size: 16, color: kUsColor),
                    tooltip: '美音',
                    splashRadius: 14,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                    onPressed: reading == null ? null : () => provider.playReading(reading, accent: 'us'),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              if (reading != null)
                Text(
                  '英音 ${reading.ukText}',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              if (reading != null && reading.usText != reading.ukText)
                Text(
                  '美音 ${reading.usText}',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              const SizedBox(height: 6),
              Text(
                example.hint,
                style: TextStyle(fontSize: 11, color: theme.hintColor, height: 1.35),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 自由输入: type any number, see the sentence for both accents.
class NumbersInputSection extends StatefulWidget {
  const NumbersInputSection({super.key});

  @override
  State<NumbersInputSection> createState() => _NumbersInputSectionState();
}

class _NumbersInputSectionState extends State<NumbersInputSection> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = context.watch<NumbersProvider>();
    final reading = provider.lookup;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.keyboard_rounded, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            const Text(
              '输入任意数字',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '自动识别整数 / 小数 / 年份 / 时刻 / 日期 / 金额 / 电话 / 分数 / 百分数',
                style: TextStyle(fontSize: 11.5, color: theme.hintColor),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _controller,
          onSubmitted: (value) => provider.parseInput(value, override: provider.lookupOverride),
          onChanged: (value) => provider.parseInput(value, override: provider.lookupOverride),
          decoration: InputDecoration(
            isDense: true,
            hintText: r'例如 1234 / 3.14 / 1999 / 3:30 / 2026-10-08 / $12.50 / 1/2 / 25%',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.numbers_rounded, size: 18),
            suffixIcon: IconButton(
              icon: const Icon(Icons.clear_rounded, size: 18),
              tooltip: '清空',
              onPressed: () {
                _controller.clear();
                provider.parseInput('');
              },
            ),
          ),
          keyboardType: TextInputType.text,
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            ChoiceChip(
              label: const Text('自动识别', style: TextStyle(fontSize: 11.5)),
              selected: provider.lookupOverride == null,
              onSelected: (_) =>
                  provider.parseInput(_controller.text, override: null),
            ),
            for (final category in const [
              NumberCategory.cardinal,
              NumberCategory.decimal,
              NumberCategory.year,
              NumberCategory.clock,
              NumberCategory.date,
              NumberCategory.money,
              NumberCategory.phone,
              NumberCategory.fraction,
              NumberCategory.ordinal,
              NumberCategory.percent,
            ])
              ChoiceChip(
                label: Text(category.labelZh, style: const TextStyle(fontSize: 11.5)),
                selected: provider.lookupOverride == category,
                onSelected: (_) => provider.parseInput(
                  _controller.text,
                  override: provider.lookupOverride == category ? null : category,
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (provider.lookupInput.trim().isEmpty)
          Text(
            '在上面输入数字，下面会出现对应的英语读法。',
            style: TextStyle(fontSize: 12.5, color: theme.hintColor),
          )
        else if (reading == null || reading.ukText.isEmpty)
          Text(
            '无法识别「${provider.lookupInput}」。请检查格式，或用上面的标签手动指定读法。',
            style: const TextStyle(fontSize: 12.5, color: Colors.redAccent),
          )
        else
          NumberReadingCard(reading: reading),
      ],
    );
  }
}

/// 训练: a random set of numbers, hidden until asked for, spoken at a chosen
/// speed with a chosen interval between the numbers.
class NumbersTrainingSection extends StatefulWidget {
  const NumbersTrainingSection({super.key});

  @override
  State<NumbersTrainingSection> createState() => _NumbersTrainingSectionState();
}

class _NumbersTrainingSectionState extends State<NumbersTrainingSection> {
  /// The custom-count field: the slider covers 1–100, anything longer is typed.
  final TextEditingController _countController = TextEditingController();
  int _shows = 0;

  @override
  void dispose() {
    _countController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final provider = context.watch<NumbersProvider>();

    if (_shows != provider.count) {
      _shows = provider.count;
      _countController.text = '${provider.count}';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.fitness_center_rounded, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            const Text('数字训练', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '生成后默认隐藏：先朗读、再显示数字对照',
                style: TextStyle(fontSize: 11.5, color: theme.hintColor),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Drill type
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final kind in TrainingKind.values)
              ChoiceChip(
                label: Text(kind.labelZh, style: const TextStyle(fontSize: 11.5)),
                selected: provider.kind == kind,
                onSelected: (_) => provider.setKind(kind),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(provider.kind.hint, style: TextStyle(fontSize: 11.5, color: theme.hintColor)),

        // Length (only the number-shaped kinds use it) and count
        if (const {
          TrainingKind.integer,
          TrainingKind.large,
          TrainingKind.decimal,
          TrainingKind.mixed,
        }.contains(provider.kind))
          _SliderRow(
            label: '位数',
            value: provider.digits.toDouble(),
            min: 1,
            max: 9,
            divisions: 8,
            display: '${provider.digits} 位',
            onChanged: (value) => provider.setDigits(value.round()),
          ),
        // 整数 mode can drill *runs*: one row holds several numbers read back to
        // back, which is what dictation practice wants.
        if (provider.kind == TrainingKind.integer) ...[
          Row(
            children: [
              Transform.scale(
                scale: 0.8,
                child: Switch(
                  value: provider.runMode,
                  onChanged: (value) => provider.setRunMode(value),
                ),
              ),
              const SizedBox(width: 2),
              const Text('多组连读',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  provider.runMode
                      ? '每组一次连读 ${provider.runMin}–${provider.runMax} 个数字，组与组之间按下方「组间」停'
                      : '一次连读多个数字（听写式练习）：组内紧凑，组间留出记录时间',
                  style: TextStyle(fontSize: 11, color: theme.hintColor),
                ),
              ),
            ],
          ),
          if (provider.runMode) ...[
            _RangeSliderRow(
              label: '每组',
              values: RangeValues(
                provider.runMin.toDouble(),
                provider.runMax.toDouble(),
              ),
              min: NumbersLimits.minRunLength.toDouble(),
              max: NumbersLimits.maxRunLength.toDouble(),
              divisions: NumbersLimits.maxRunLength - NumbersLimits.minRunLength,
              display: '${provider.runMin}–${provider.runMax} 个',
              onChanged: (values) =>
                  provider.setRunRange(values.start.round(), values.end.round()),
            ),
            _SliderRow(
              label: '组内',
              value: provider.runGapMs / 1000.0,
              min: NumbersLimits.minRunGapMs / 1000.0,
              max: NumbersLimits.maxRunGapMs / 1000.0,
              divisions: 40, // 0.05 s steps
              display: provider.runGapMs == 0
                  ? '连读'
                  : '${(provider.runGapMs / 1000.0).toStringAsFixed(2)} 秒',
              onChanged: (value) => provider.setRunGapMs((value * 1000).round()),
            ),
          ],
        ],
        _SliderRow(
          label: '数量',
          value: provider.count.clamp(NumbersLimits.minTrainingCount, 100).toDouble(),
          min: NumbersLimits.minTrainingCount.toDouble(),
          max: 100,
          divisions: 100 - NumbersLimits.minTrainingCount,
          display: '${provider.count} 个',
          onChanged: (value) => provider.setCount(value.round()),
        ),
        // Anything beyond the slider is typed here: the drill renders its numbers
        // lazily and the queue simply keeps going, so a few hundred are fine.
        Row(
          children: [
            const SizedBox(
              width: 40,
              child: Text('自定义', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
            ),
            Expanded(
              child: SizedBox(
                height: 34,
                child: TextField(
                  controller: _countController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontSize: 12.5),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    hintText: '输入任意数量，最多 ${NumbersLimits.maxTrainingCount} 个',
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (value) {
                    final parsed = int.tryParse(value.trim());
                    if (parsed != null) provider.setCount(parsed);
                  },
                ),
              ),
            ),
          ],
        ),

        // Speed and interval — the two knobs the drill is specified with.
        _SliderRow(
          label: '语速',
          value: provider.rate,
          min: NumbersLimits.minRate,
          max: NumbersLimits.maxRate,
          divisions: NumbersLimits.rateDivisions,
          // ×1.00 is the teaching pace, not the voice's native speed. The hint
          // rides on a tooltip because `display` sits in a fixed 62 px box and a
          // longer string wraps, which grows the row and pushes the buttons off
          // a small window.
          tooltip: '×1.00 为教学语速，约为母语者自然语速的一半；往上更快，'
              '往下更慢（慢于引擎极限的部分由词间停顿补足）。',
          display: '×${provider.rate.toStringAsFixed(2)}',
          onChanged: provider.setRate,
        ),
        _SliderRow(
          label: provider.runBatch ? '组间' : '间隔',
          value: provider.gapMs / 1000.0,
          min: 0,
          max: 3,
          divisions: 60, // 0.05 s steps, down to none at all
          display: provider.gapMs == 0
              ? '连读'
              : '${(provider.gapMs / 1000.0).toStringAsFixed(2)} 秒',
          onChanged: (value) => provider.setGapMs((value * 1000).round()),
        ),

        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.tonalIcon(
              icon: const Icon(Icons.casino_rounded, size: 18),
              label: const Text('生成一组'),
              onPressed: provider.generateTraining,
            ),
            OutlinedButton.icon(
              icon: Icon(
                provider.revealed ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                size: 18,
              ),
              label: Text(provider.revealed ? '隐藏数字' : '显示数字'),
              onPressed: provider.training.isEmpty ? null : provider.toggleReveal,
            ),
            FilledButton.icon(
              icon: const Icon(Icons.play_arrow_rounded, size: 20),
              label: Text(
                provider.playingIndex >= 0
                    ? '正在朗读 ${provider.playingIndex + 1}/${provider.training.length}'
                    : '开始朗读',
              ),
              onPressed: provider.training.isEmpty || provider.isPlaying
                  ? null
                  : provider.playTraining,
            ),
            OutlinedButton.icon(
              icon: Icon(
                provider.isPaused
                    ? Icons.play_arrow_rounded
                    : Icons.pause_rounded,
                size: 18,
              ),
              label: Text(provider.isPaused ? '继续' : '暂停'),
              onPressed: provider.isPlaying
                  ? provider.pausePlayback
                  : (provider.isPaused ? provider.resumePlayback : null),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.stop_rounded, size: 18),
              label: const Text('停止'),
              onPressed: provider.isPlaying || provider.isPaused
                  ? provider.stopPlayback
                  : null,
            ),
            // 循环播放: the same list again and again until 停止. The hint rides on
            // a tooltip so the chip costs no vertical space — the row above it
            // already sits at the bottom of a small window.
            Tooltip(
              message: '循环播放：整组朗读完自动从头再来，直到按「停止」'
                  '（播放中改这个开关，本轮结束后生效）',
              child: FilterChip(
                avatar: const Icon(Icons.repeat_rounded, size: 16),
                label: const Text('循环', style: TextStyle(fontSize: 11.5)),
                selected: provider.loop,
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onSelected: provider.setLoop,
              ),
            ),
            // Which accent the drill speaks in.
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'uk', label: Text('英音', style: TextStyle(fontSize: 11.5))),
                ButtonSegment(value: 'us', label: Text('美音', style: TextStyle(fontSize: 11.5))),
              ],
              selected: {provider.accent},
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onSelectionChanged: (selection) => provider.setAccent(selection.first),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const SizedBox(height: 12),

        // The generated numbers themselves.
        if (provider.training.isEmpty)
          Text(
            '还没有生成数字。选好类型、位数与数量后点「生成一组」，'
            '再点「开始朗读」即可练习听力；语速与间隔随时可调。',
            style: TextStyle(fontSize: 12.5, color: theme.hintColor, height: 1.5),
          )
        else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: borderColor(isDark)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Two lines that each wrap: the hint and the batch summary used to
                // share one row with a Spacer between them, which overflowed on a
                // phone (RIGHT OVERFLOWED BY 18.1 PIXELS).
                Row(
                  children: [
                    Icon(
                      provider.revealed ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                      size: 14,
                      color: theme.hintColor,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        provider.revealed
                            ? (provider.runBatch ? '数字已显示（点击任意一组可单独试听）' : '数字已显示（点击单个数字可单独试听）')
                            : '数字已隐藏，点击「显示数字」查看',
                        style: TextStyle(fontSize: 11.5, color: theme.hintColor),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (provider.runBatch)
                      '共 ${provider.training.length} 组 · 每组 '
                          '${provider.runMin}–${provider.runMax} 个数字'
                    else
                      '共 ${provider.training.length} 个 · ${provider.kind.labelZh}',
                    if (provider.trainingDistinctCount < provider.training.length)
                      '（可选值只有 ${provider.trainingDistinctCount} 个，其余循环重复）'
                    else
                      '（不重复）',
                  ].join(),
                  style: TextStyle(fontSize: 11.5, color: theme.hintColor),
                ),
                const SizedBox(height: 10),
                _TrainingNumberList(
                  items: provider.training,
                  revealed: provider.revealed,
                  playingIndex: provider.playingIndex,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The generated numbers, rendered lazily: the drill's count is the user's call,
/// and a few hundred rows must not all be built at once.
class _TrainingNumberList extends StatefulWidget {
  const _TrainingNumberList({
    required this.items,
    required this.revealed,
    required this.playingIndex,
  });

  final List<NumberTrainingItem> items;
  final bool revealed;
  final int playingIndex;

  @override
  State<_TrainingNumberList> createState() => _TrainingNumberListState();
}

class _TrainingNumberListState extends State<_TrainingNumberList> {
  /// Rows have a fixed height so the view can be scrolled to the one being read
  /// without measuring anything.
  static const double _rowHeight = 42;
  static const int _visibleRows = 6;

  final ScrollController _controller = ScrollController();

  @override
  void didUpdateWidget(covariant _TrainingNumberList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final index = widget.playingIndex;
    if (index < 0 || index == oldWidget.playingIndex) return;
    // Keep the number being spoken in sight.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_controller.hasClients) return;
      final target = (index * _rowHeight)
          .clamp(0.0, _controller.position.maxScrollExtent);
      _controller.animateTo(
        target,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows = widget.items.length.clamp(1, _visibleRows);

    return SizedBox(
      height: rows * _rowHeight,
      child: ListView.builder(
        controller: _controller,
        itemExtent: _rowHeight,
        itemCount: widget.items.length,
        itemBuilder: (context, index) => _TrainingNumberRow(
          index: index,
          item: widget.items[index],
          revealed: widget.revealed,
          speaking: widget.playingIndex == index,
        ),
      ),
    );
  }
}

/// One generated number: its place in the batch, the number itself (hidden until
/// asked for) and a play button.
class _TrainingNumberRow extends StatelessWidget {
  const _TrainingNumberRow({
    required this.index,
    required this.item,
    required this.revealed,
    required this.speaking,
  });

  final int index;
  final NumberTrainingItem item;
  final bool revealed;
  final bool speaking;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final provider = context.read<NumbersProvider>();

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: speaking
            ? theme.colorScheme.primaryContainer.withValues(alpha: isDark ? 0.45 : 0.6)
            : (isDark ? const Color(0xFF1E2430) : Colors.white),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: revealed ? () => provider.playTrainingItem(item) : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: speaking ? theme.colorScheme.primary : borderColor(isDark),
                width: speaking ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  child: Text('${index + 1}', style: TextStyle(fontSize: 11, color: theme.hintColor)),
                ),
                Expanded(
                  child: Text(
                    revealed ? item.input : '• • •',
                    style: TextStyle(
                      fontSize: revealed ? 16 : 13,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                      letterSpacing: revealed ? 0 : 1.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (speaking)
                  Icon(Icons.graphic_eq_rounded, size: 15, color: theme.colorScheme.primary)
                else if (revealed)
                  Icon(Icons.volume_up_rounded, size: 15, color: theme.hintColor),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A slider over a range, used for a run's length (e.g. 3–7 numbers).
class _RangeSliderRow extends StatelessWidget {
  const _RangeSliderRow({
    required this.label,
    required this.values,
    required this.min,
    required this.max,
    required this.divisions,
    required this.display,
    required this.onChanged,
  });

  final String label;
  final RangeValues values;
  final double min;
  final double max;
  final int divisions;
  final String display;
  final ValueChanged<RangeValues> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        SizedBox(
          width: 40,
          child: Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
        ),
        Expanded(
          child: RangeSlider(
            values: RangeValues(
              values.start.clamp(min, max),
              values.end.clamp(min, max),
            ),
            min: min,
            max: max,
            divisions: divisions,
            labels: RangeLabels('${values.start.round()}', '${values.end.round()}'),
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 62,
          child: Text(
            display,
            style: TextStyle(fontSize: 12, color: theme.hintColor),
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.display,
    required this.onChanged,
    this.tooltip,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String display;
  final ValueChanged<double> onChanged;

  /// Optional explanation shown on hover; wrapped around the label so it costs
  /// no layout space of its own.
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        SizedBox(
          width: 40,
          child: tooltip == null
              ? Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))
              : Tooltip(
                  message: tooltip!,
                  child: Text(label,
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                ),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 62,
          child: Text(
            display,
            style: TextStyle(fontSize: 12, color: theme.hintColor),
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }
}
