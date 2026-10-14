import 'dart:math';

import 'number_model.dart';
import 'number_speller.dart';

/// The bounds the drill settings are clamped to.
///
/// They live here rather than in the UI so generation, persistence and the
/// sliders can never disagree.
class NumbersLimits {
  const NumbersLimits._();

  /// A batch larger than this stops being a drill and starts being a marathon
  /// (the speech alone would run for hours), but it is deliberately far above
  /// what the slider offers.
  static const int minTrainingCount = 1;
  static const int maxTrainingCount = 1000;

  /// 0 means "no pause at all": the sentences follow each other directly.
  static const int minGapMs = 0;
  static const int maxGapMs = 5000;

  /// 语速. ×1.0 is the teaching pace — half the voice's natural rate — because a
  /// native-speaker pace is the fast end of what a listening drill can use. The
  /// slow end is past the engine's prosody floor and is carried by pauses.
  static const double minRate = 0.5;
  static const double maxRate = 1.5;
  static const int rateDivisions = 20;

  /// 多组连读 (integer mode): how long a run may be, and how tightly its numbers
  /// follow each other. The gap *between* runs is the ordinary [minGapMs]…
  /// [maxGapMs] one.
  static const int minRunLength = 2;
  static const int maxRunLength = 12;
  static const int minRunGapMs = 0;
  static const int maxRunGapMs = 2000;
}

/// What the training module generates numbers from.
///
/// One kind per category the module teaches, so the drill can target whatever the
/// learner is working on — plus [mixed], which draws from all of them.
enum TrainingKind {
  integer('整数', '每个位数随机，受「位数」影响'),
  large('大数字', '七位以上的大数字，三位一组'),
  decimal('小数', '带两位小数的小数'),
  year('年份', '四位年份（含 ten sixty-six / nineteen hundred 这类读法）'),
  ordinal('序数词', '1st / 2nd / 23rd / 100th，带正确后缀'),
  fraction('分数', '分母 2–12，含 half / quarter / over 规则'),
  percent('百分数', '整数或一位小数百分数'),
  temperature('温度', '摄氏 / 华氏，含零下'),
  clock('时刻', '整点、quarter / half、逐字读'),
  money('货币', '美元 / 英镑 / 欧元 / 日元，含辅币'),
  date('日期', '日期格式，英式与美式读法不同'),
  phone('电话号码', '分组号码，含 0 读 oh、double / triple'),
  mixed('混合', '以上类型随机组合');

  final String labelZh;
  final String hint;
  const TrainingKind(this.labelZh, this.hint);

  /// The concrete kinds [mixed] draws from.
  static final List<TrainingKind> concrete =
      values.where((kind) => kind != TrainingKind.mixed).toList();
}

/// One row of the drill.
///
/// A row usually holds a single number (`4,812`, `£12.50`), but integer mode's
/// 多组 option makes each row a **run** of [NumbersLimits.minRunLength]…
/// [NumbersLimits.maxRunLength] numbers that the drill reads back to back.
class NumberTrainingItem {
  /// The numbers of this row, in the order they are read.
  final List<NumberReading> numbers;

  /// What the drill asked for (e.g. `cardinal` in 整数 mode) — the speller may
  /// report a finer interpretation for the same digits, but a row is labelled with
  /// the kind it was generated as.
  final NumberCategory? _requested;

  const NumberTrainingItem(this.numbers, {NumberCategory? category})
      : _requested = category;

  factory NumberTrainingItem.one(NumberReading reading, {NumberCategory? category}) =>
      NumberTrainingItem(<NumberReading>[reading], category: category);

  factory NumberTrainingItem.run(List<NumberReading> readings,
          {NumberCategory? category}) =>
      NumberTrainingItem(List<NumberReading>.unmodifiable(readings), category: category);

  /// True when this row is a run rather than a single number.
  bool get isRun => numbers.length > 1;

  /// How the row is written down: `4,812` or `4,812 · 37 · 1,205`.
  String get input => numbers.map((reading) => reading.input).join(separator);

  NumberCategory get category => _requested ?? numbers.first.category;

  /// The first number — the reading a card or a single-item playback wants.
  NumberReading get reading => numbers.first;

  /// The whole row as one sentence, e.g. `four thousand …, thirty-seven, …`.
  String sentenceFor(String accent) =>
      numbers.map((reading) => reading.textFor(accent)).join(', ');

  /// The row split into one sentence per number (the recorded-word path).
  List<String> textsFor(String accent) =>
      numbers.map((reading) => reading.textFor(accent)).toList(growable: false);

  String get ukText => sentenceFor('uk');
  String get usText => sentenceFor('us');
  String textFor(String accent) => sentenceFor(accent);

  /// Written between the numbers of a run.
  static const String separator = ' · ';
}

/// Builds the random numbers the training module drills.
///
/// Two rules the drill is specified with:
///  * **the requested count is what you get** — a batch is always as long as asked
///    for, up to [NumbersLimits.maxTrainingCount];
///  * **no repeats while the pool allows it** — different numbers are drawn first,
///    and only once the kind's space is exhausted (one-digit integers: nine
///    values, fractions: about a hundred) is the rest topped up with repeats,
///    walked in shuffled rounds so the same number never lands right behind
///    itself. The UI reports how many of the batch were distinct;
///  * **every kind is a real reading** — each item's sentence comes from
///    [NumberSpeller], never from a table, so what the drill speaks is exactly
///    what the module would say for that number anywhere else.
///
/// Kept out of the provider so all of it is testable: the same seed produces the
/// same batch.
class NumberTraining {
  const NumberTraining._();

  /// A batch of the requested kind: [count] rows, each a single number.
  static List<NumberTrainingItem> generate({
    required TrainingKind kind,
    required int digits,
    required int count,
    Random? random,
  }) {
    final rng = random ?? Random();
    final safeDigits = digits.clamp(1, 9);
    return _fill(
      wanted: count.clamp(NumbersLimits.minTrainingCount, NumbersLimits.maxTrainingCount),
      rng: rng,
      draw: () {
        final concrete = kind == TrainingKind.mixed
            ? TrainingKind.concrete[rng.nextInt(TrainingKind.concrete.length)]
            : kind;
        return _candidate(concrete, safeDigits, rng);
      },
    );
  }

  /// A batch in which every row is a **run** of integers read back to back: the
  /// length of a run is drawn per row from [minLength]…[maxLength], so a batch of
  /// 6 with 3–7 gives runs of any length in between.
  static List<NumberTrainingItem> generateRuns({
    required int digits,
    required int count,
    required int minLength,
    required int maxLength,
    Random? random,
  }) {
    final rng = random ?? Random();
    final safeDigits = digits.clamp(1, 9);
    final low = minLength.clamp(NumbersLimits.minRunLength, NumbersLimits.maxRunLength);
    final high = maxLength.clamp(low, NumbersLimits.maxRunLength);
    return _fill(
      wanted: count.clamp(NumbersLimits.minTrainingCount, NumbersLimits.maxTrainingCount),
      rng: rng,
      draw: () {
        final length = low + rng.nextInt(high - low + 1);
        final readings = <NumberReading>[];
        for (var i = 0; i < length; i++) {
          // A run is fast listening practice, so the same number must not come
          // twice in a row — bounded retries keep a small pool (nine one-digit
          // integers) from spinning here.
          NumberReading? chosen;
          for (var attempt = 0; attempt < 12 && chosen == null; attempt++) {
            final candidate = _candidate(TrainingKind.integer, safeDigits, rng)?.reading;
            if (candidate == null) continue;
            if (readings.isNotEmpty && readings.last.input == candidate.input) continue;
            chosen = candidate;
          }
          chosen ??= _candidate(TrainingKind.integer, safeDigits, rng)?.reading;
          if (chosen == null) break;
          readings.add(chosen);
        }
        return readings.isEmpty
            ? null
            : NumberTrainingItem.run(readings, category: NumberCategory.cardinal);
      },
    );
  }

  /// Fills a batch with [draw]: different rows first, then — only once the kind's
  /// space is exhausted — the same rows again in shuffled rounds, never twice in a
  /// row. The requested length wins over the no-repeats rule.
  static List<NumberTrainingItem> _fill({
    required int wanted,
    required NumberTrainingItem? Function() draw,
    required Random rng,
  }) {
    final seen = <String>{};
    final items = <NumberTrainingItem>[];
    // Bounded so a small pool cannot spin forever: once the draws keep colliding the
    // space is exhausted and the repeat rounds below take over.
    final maxAttempts = wanted * 20;
    for (var attempt = 0; attempt < maxAttempts && items.length < wanted; attempt++) {
      final item = draw();
      if (item == null || !seen.add(item.input)) continue;
      items.add(item);
    }

    var pool = List.of(items)..shuffle(rng);
    var cursor = 0;
    while (items.length < wanted && pool.isNotEmpty) {
      if (cursor >= pool.length) {
        pool = List.of(pool)..shuffle(rng);
        cursor = 0;
        // Keep the row that just played from closing a round and opening the next.
        if (pool.length > 1 && pool.first.input == items.last.input) {
          final swap = 1 + rng.nextInt(pool.length - 1);
          final first = pool[0];
          pool[0] = pool[swap];
          pool[swap] = first;
        }
      }
      items.add(pool[cursor++]);
    }
    return items;
  }

  static NumberTrainingItem? _candidate(TrainingKind kind, int digits, Random rng) {
    switch (kind) {
      case TrainingKind.integer:
        return _withReading(_group(_randomDigits(rng, digits)), NumberCategory.cardinal);
      case TrainingKind.large:
        return _withReading(
          _group(_randomDigits(rng, 7 + rng.nextInt(2))),
          NumberCategory.cardinal,
        );
      case TrainingKind.decimal:
        final whole = _randomDigits(rng, digits.clamp(1, 6));
        final fraction = rng.nextInt(90) + 10; // always two decimal places
        return _withReading('$whole.$fraction', NumberCategory.decimal);
      case TrainingKind.year:
        // 1000–2099 covers every reading rule: pair-split, "oh five", "hundred",
        // "two thousand and five", "twenty twenty-six".
        return _withReading('${1000 + rng.nextInt(1100)}', NumberCategory.year);
      case TrainingKind.ordinal:
        final value = 1 + rng.nextInt(120);
        return _withReading('$value${_ordinalSuffix(value)}', NumberCategory.ordinal);
      case TrainingKind.fraction:
        final denominator = 2 + rng.nextInt(11); // 2–12, so "over" shows up too
        final numerator = 1 + rng.nextInt(denominator + 1);
        return _withReading('$numerator/$denominator', NumberCategory.fraction);
      case TrainingKind.percent:
        final input = rng.nextBool()
            ? '${1 + rng.nextInt(150)}%'
            : '${1 + rng.nextInt(99)}.${1 + rng.nextInt(9)}%';
        return _withReading(input, NumberCategory.percent);
      case TrainingKind.temperature:
        final value = -20 + rng.nextInt(61); // −20…40
        return _withReading(
          '$value°${rng.nextBool() ? 'C' : 'F'}',
          NumberCategory.temperature,
        );
      case TrainingKind.clock:
        final hour = rng.nextInt(24).toString().padLeft(2, '0');
        final minute = rng.nextInt(60).toString().padLeft(2, '0');
        return _withReading('$hour:$minute', NumberCategory.clock);
      case TrainingKind.money:
        const symbols = [r'$', '£', '€', '¥'];
        final symbol = symbols[rng.nextInt(symbols.length)];
        final cents = rng.nextInt(100).toString().padLeft(2, '0');
        return _withReading('$symbol${rng.nextInt(1000)}.$cents', NumberCategory.money);
      case TrainingKind.date:
        final month = 1 + rng.nextInt(12);
        final day = 1 + rng.nextInt(28); // every month has 28 days
        final year = 2000 + rng.nextInt(30);
        return _withReading(
          '$year-${_two(month)}-${_two(day)}',
          NumberCategory.date,
        );
      case TrainingKind.phone:
        // Grouped like a real number, so the pauses are part of the drill.
        return _withReading(
          '0${_randomDigits(rng, 3)}-${_randomDigits(rng, 4)}-${_randomDigits(rng, 4)}',
          NumberCategory.phone,
        );
      case TrainingKind.mixed:
        return null; // resolved before the call
    }
  }

  static String _two(int value) => value.toString().padLeft(2, '0');

  /// A number with exactly [digits] digits and no leading zero.
  static String _randomDigits(Random rng, int digits) {
    final buffer = StringBuffer();
    for (var i = 0; i < digits; i++) {
      var digit = rng.nextInt(10);
      if (i == 0 && digit == 0) digit = rng.nextInt(9) + 1;
      buffer.write(digit);
    }
    return buffer.toString();
  }

  /// `4812` → `4,812`, the way the module displays large numbers.
  static String _group(String digits) {
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  /// 1st / 2nd / 3rd / 4th … 11th / 12th / 13th … 21st — the suffix rule.
  static String _ordinalSuffix(int value) {
    if (value % 100 >= 11 && value % 100 <= 13) return 'th';
    return switch (value % 10) {
      1 => 'st',
      2 => 'nd',
      3 => 'rd',
      _ => 'th',
    };
  }

  /// Null when the speller cannot read what was drawn (the caller just draws
  /// again), which keeps a generation bug from putting nonsense in the drill.
  static NumberTrainingItem? _withReading(String input, NumberCategory category) {
    final reading = NumberSpeller.read(input, as: category);
    if (reading == null || reading.ukText.isEmpty || reading.usText.isEmpty) {
      return null;
    }
    return NumberTrainingItem.one(reading, category: category);
  }
}
