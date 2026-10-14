/// One kind of number expression the module teaches. The list mirrors the
/// categories the Cambridge phonetics help groups numbers into: cardinal and
/// ordinal forms, the very large numbers, decimals, fractions, percentages,
/// years, clock times, money, phone numbers, dates — plus how English says `0`
/// (`zero` / `nought` / `nil` / `love` / `oh`), which is the one every learner
/// asks about.
enum NumberCategory {
  cardinal('基数词', 'Cardinal numbers'),
  ordinal('序数词', 'Ordinal numbers'),
  large('大数字', 'Very large numbers'),
  decimal('小数', 'Decimals'),
  fraction('分数', 'Fractions'),
  percent('百分数', 'Percentages'),
  temperature('温度', 'Temperature'),
  multiple('倍数与次数', 'Multiples & frequency'),
  ratio('比例', 'Ratios'),
  year('年份', 'Years'),
  clock('时刻', 'Clock time'),
  money('货币', 'Money'),
  phone('电话号码', 'Phone numbers'),
  date('日期', 'Dates'),
  zero('零的读法', 'Saying zero');

  final String labelZh;
  final String labelEn;
  const NumberCategory(this.labelZh, this.labelEn);
}

/// A number written down and the sentence that says it, in both accents.
///
/// The two texts are not translations of each other: British English keeps the
/// `and` of "one hundred and twenty-three" and reads a decimal zero as
/// "nought", American English drops the `and` and says "zero"
/// (<https://dictionary.cambridge.org/help/phonetics.html>).
class NumberReading {
  /// The number as the user wrote it, e.g. `1,234` or `£3.99`.
  final String input;

  /// How British English says [input].
  final String ukText;

  /// How American English says [input].
  final String usText;

  /// 中文说明: which rule produced this reading and what to watch out for.
  final String note;

  /// The interpretation finally used, e.g. `year` when `2026` was read as a year.
  final NumberCategory category;

  const NumberReading({
    required this.input,
    required this.ukText,
    required this.usText,
    required this.note,
    required this.category,
  });

  /// The reading for [accent] (`uk` or anything else for American).
  String textFor(String accent) => accent == 'uk' ? ukText : usText;
}

/// What a card in the 分类展示 grid teaches.
///
/// The distinction is what keeps the inventory honest: English number words are
/// irregular exactly up to twelve (plus a handful of spelling traps later on),
/// and completely regular from twenty-one upwards. Listing "one … twelve" and
/// the tens one by one, but teaching "21–99" as a single rule, is the whole
/// organisation of the module.
enum NumberCardKind {
  /// A written number — the sentence comes from [NumberSpeller] ("1,234").
  number,

  /// One vocabulary word that has to be learnt on its own: `one`…`twelve`,
  /// `forty` (no `u`), `twelfth`, `eighth`. The card shows the word, its value
  /// and plays that word's own recording.
  word,

  /// A rule that covers a whole range at once: `21–99`, `1st–12th`, hundreds and
  /// above. Shown once with a few samples instead of every member.
  pattern,
}

/// A teaching card: a written number, one vocabulary word, or a rule.
///
/// Sentences are never stored — [NumberSpeller.read] derives them, so a card can
/// never drift away from the rule it is supposed to demonstrate.
class NumberExample {
  /// What is written on the card: the number (`1,234`), the word (`thirteen`) or
  /// the range a pattern covers (`21–99`).
  final String input;
  final NumberCategory category;
  final NumberCardKind kind;

  /// Forces an interpretation for inputs that are ambiguous on their own
  /// (`0.5` is a decimal, but `0` in a phone number is "oh").
  final NumberCategory? as;

  /// 中文一句话说明, shown on the card: the rule for a pattern, the spelling or
  /// pronunciation trap for a word.
  final String hint;

  /// [NumberCardKind.word] only: the value the word stands for (`13`).
  final String? value;

  /// [NumberCardKind.pattern] only: sample members of the range, each one
  /// playable on its own.
  final List<String> samples;

  /// Set for the “零的读法” cards, which are not numbers at all: they are the
  /// contexts (phone, score, tennis, …) that decide how `0` is said. The reading
  /// then comes from [NumberSpeller.zeroReading] instead of the digits.
  final String? zeroContext;

  const NumberExample({
    required this.input,
    required this.category,
    this.kind = NumberCardKind.number,
    this.as,
    required this.hint,
    this.value,
    this.samples = const [],
    this.zeroContext,
  });

  /// A word card, e.g. `thirteen` = 13.
  const NumberExample.word({
    required this.input,
    required this.category,
    required this.value,
    required this.hint,
  })  : kind = NumberCardKind.word,
        as = null,
        samples = const [],
        zeroContext = null;

  /// A pattern card, e.g. `21–99` with three samples.
  const NumberExample.pattern({
    required this.input,
    required this.category,
    required this.hint,
    required this.samples,
  })  : kind = NumberCardKind.pattern,
        as = null,
        value = null,
        zeroContext = null;
}
