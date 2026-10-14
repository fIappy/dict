import 'number_model.dart';

/// Turns a written number into the sentence an English speaker actually says.
///
/// Nothing here is a phrase book: every reading is generated from the digits, so
/// the module can speak a number nobody typed before ("输入任意数字" in the
/// feature request). Only the *words* are pre-recorded
/// (`tool/generate_number_audio.py`), never the sentences.
///
/// British and American readings are produced side by side, because the
/// difference is real and not cosmetic (Cambridge, Help → Phonetics):
///
/// * `1,234` — 英音 one thousand two hundred **and** thirty-four /
///   美音 one thousand two hundred thirty-four. The `and` also appears across
///   scales: 英音 `1,023` = "one thousand **and** twenty-three".
/// * `0.5` — 英音 "**nought** point five" / 美音 "**zero** point five".
/// * `0:30` — 英音 "half **past** twelve" / 美音 same, but `3:15` is
///   英音 "quarter **past** three" / 美音 "quarter **after** three".
///
/// A comma or space inside a phone number is written as a `,` in the spoken text
/// so [NumberSpeaker] can drop a short pause at each group boundary, the way a
/// person reads a phone number aloud.
class NumberSpeller {
  const NumberSpeller._();

  static const List<String> _ones = [
    'zero', 'one', 'two', 'three', 'four', 'five',
    'six', 'seven', 'eight', 'nine',
  ];
  static const List<String> _teens = [
    'ten', 'eleven', 'twelve', 'thirteen', 'fourteen', 'fifteen',
    'sixteen', 'seventeen', 'eighteen', 'nineteen',
  ];
  static const List<String> _tens = [
    '', '', 'twenty', 'thirty', 'forty', 'fifty',
    'sixty', 'seventy', 'eighty', 'ninety',
  ];
  static const List<String> _ordinalOnes = [
    'zeroth', 'first', 'second', 'third', 'fourth', 'fifth', 'sixth', 'seventh',
    'eighth', 'ninth', 'tenth', 'eleventh', 'twelfth', 'thirteenth', 'fourteenth',
    'fifteenth', 'sixteenth', 'seventeenth', 'eighteenth', 'nineteenth',
  ];
  static const List<String> _ordinalTens = [
    '', '', 'twentieth', 'thirtieth', 'fortieth', 'fiftieth',
    'sixtieth', 'seventieth', 'eightieth', 'ninetieth',
  ];
  static const List<String> _scales = [
    '', 'thousand', 'million', 'billion', 'trillion', 'quadrillion',
  ];

  static const List<String> _months = [
    '', 'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  // ---------------------------------------------------------------- cardinals

  /// `1234` → "one thousand two hundred and thirty-four" (英) or
  /// "one thousand two hundred thirty-four" (美).
  ///
  /// [insertAnd] is the only difference between the two accents: British inserts
  /// `and` before the final sub-hundred remainder — "two hundred **and** five",
  /// and across scales "one thousand **and** twenty-three".
  static String cardinal(int value, {required bool insertAnd}) {
    if (value == 0) return 'zero';
    if (value < 0) return 'minus ${cardinal(-value, insertAnd: insertAnd)}';

    // Split into groups of three digits, least significant first.
    final groups = <int>[];
    var rest = value;
    while (rest > 0) {
      groups.insert(0, rest % 1000);
      rest ~/= 1000;
    }
    if (groups.length > _scales.length) {
      // 10^18 and up: no scale word exists, so say the digits instead.
      return value.toString().split('').map((d) => _ones[int.parse(d)]).join(' ');
    }

    final parts = <String>[];
    for (var i = 0; i < groups.length; i++) {
      final group = groups[i];
      if (group == 0) continue;
      final isLast = i == groups.length - 1;
      // The British `and` only ever precedes a final group below one hundred
      // ("one thousand and twenty-three"); a full last group carries its own
      // `and` inside it ("one thousand two hundred and thirty-four").
      if (insertAnd && isLast && parts.isNotEmpty && group < 100) {
        parts.add('and');
      }
      parts.add(_under1000(group, insertAnd: insertAnd));
      final scale = _scales[groups.length - 1 - i];
      if (scale.isNotEmpty) parts.add(scale);
    }
    return parts.join(' ');
  }

  static String _under1000(int value, {required bool insertAnd}) {
    final hundreds = value ~/ 100;
    final rest = value % 100;
    if (hundreds == 0) return _under100(rest);
    final head = '${_ones[hundreds]} hundred';
    if (rest == 0) return head;
    return '$head ${insertAnd ? 'and ' : ''}${_under100(rest)}';
  }

  static String _under100(int value) {
    if (value < 10) return _ones[value];
    if (value < 20) return _teens[value - 10];
    final tens = value ~/ 10;
    final ones = value % 10;
    // 21 → "twenty-one": the hyphen is the written form, and the audio
    // tokenizer splits on it, so one clip is reused for every compound.
    return ones == 0 ? _tens[tens] : '${_tens[tens]}-${_ones[ones]}';
  }

  // ----------------------------------------------------------------- ordinals

  /// `21` → "twenty-first"; `1,000` → "one thousandth".
  static String ordinal(int value, {required bool insertAnd}) {
    if (value < 0) return 'minus ${ordinal(-value, insertAnd: insertAnd)}';
    if (value < 20) return _ordinalOnes[value];
    if (value < 100) {
      final tens = value ~/ 10;
      final ones = value % 10;
      return ones == 0 ? _ordinalTens[tens] : '${_tens[tens]}-${_ordinalOnes[ones]}';
    }
    // Everywhere else only the last spoken word changes:
    // "two hundred and thirty-four" → "two hundred and thirty-fourth".
    final words = cardinal(value, insertAnd: insertAnd).split(' ');
    final last = words.removeLast();
    return [...words, _ordinalWord(last)].join(' ');
  }

  static String _ordinalWord(String word) {
    const scales = {
      'hundred': 'hundredth',
      'thousand': 'thousandth',
      'million': 'millionth',
      'billion': 'billionth',
      'trillion': 'trillionth',
      'quadrillion': 'quadrillionth',
    };
    final scale = scales[word];
    if (scale != null) return scale;
    final onesIndex = _ones.indexOf(word);
    if (onesIndex >= 0) return _ordinalOnes[onesIndex];
    final teensIndex = _teens.indexOf(word);
    if (teensIndex >= 0) return _ordinalOnes[teensIndex + 10];
    final tensIndex = _tens.indexOf(word);
    if (tensIndex >= 0) return _ordinalTens[tensIndex];
    // Compound like "twenty-one": ordinalize the tail only.
    final dash = word.lastIndexOf('-');
    if (dash > 0) return '${word.substring(0, dash)}-${_ordinalWord(word.substring(dash + 1))}';
    return word;
  }

  // ------------------------------------------------------------------ reading

  /// Reads [raw] and returns the sentence for both accents, or null when the
  /// input is not a number this module understands.
  ///
  /// [as] forces one interpretation; without it the format is detected (the
  /// order below is the tie-breaker, and `2026` deliberately reads as a year).
  static NumberReading? read(String raw, {NumberCategory? as}) {
    final input = raw.trim();
    if (input.isEmpty) return null;
    final kind = as ?? _detect(input);
    if (kind == null) return null;

    switch (kind) {
      case NumberCategory.percent:
        return _readPercent(input);
      case NumberCategory.money:
        return _readMoney(input);
      case NumberCategory.temperature:
        return _readTemperature(input);
      case NumberCategory.multiple:
        return _readMultiple(input);
      case NumberCategory.ratio:
        return _readRatio(input);
      case NumberCategory.fraction:
        return _readFraction(input);
      case NumberCategory.clock:
        return _readClock(input);
      case NumberCategory.date:
        return _readDate(input);
      case NumberCategory.phone:
        return _readPhone(input);
      case NumberCategory.ordinal:
        return _readOrdinal(input);
      case NumberCategory.year:
        if (RegExp(r"^'?\d{2,4}s$").hasMatch(input)) return _readDecade(input);
        if (RegExp(r'^\d+\s*(bc|ad)$|^ad\s*\d+$', caseSensitive: false).hasMatch(input)) {
          return _readEra(input);
        }
        return _readYear(input);
      case NumberCategory.decimal:
        return _readDecimal(input);
      case NumberCategory.zero:
      case NumberCategory.cardinal:
      case NumberCategory.large:
        return _readCardinal(input, kind);
    }
  }

  static NumberCategory? _detect(String input) {
    if (RegExp(r'^[-+]?[\d.,]+\s*%$').hasMatch(input)) return NumberCategory.percent;
    // 25°C / 98.6°F / 30° / 25 degrees C — a bare number is never a temperature.
    if (RegExp(r'^-?\d+(?:\.\d+)?\s*(?:°\s*)?(?:deg(?:rees?)?\s*)?(?:c|f)\s*$', caseSensitive: false)
        .hasMatch(input)) {
      return NumberCategory.temperature;
    }
    if (RegExp(r'^-?\d+(?:\.\d+)?\s*°$').hasMatch(input)) return NumberCategory.temperature;
    if (RegExp(r'^-?\d+(?:\.\d+)?\s*deg(?:rees?)?$', caseSensitive: false).hasMatch(input)) {
      return NumberCategory.temperature;
    }
    // 2x / 1.5× — a multiple or a count of times.
    if (RegExp(r'^\d+(?:\.\d+)?\s*[x×]$', caseSensitive: false).hasMatch(input)) {
      return NumberCategory.multiple;
    }
    // "9 out of 10" is a ratio; `a:b` is checked after the clock rules below,
    // because 3:30 is a time and 2:1 is not.
    if (RegExp(r'^\d+\s+(?:in|out of)\s+\d+$', caseSensitive: false).hasMatch(input)) {
      return NumberCategory.ratio;
    }
    if (RegExp(r'^[$£€¥]\s*[\d,]+(\.\d+)?$').hasMatch(input)) return NumberCategory.money;
    if (RegExp(r'^-?\d+\s*/\s*\d+$').hasMatch(input)) return NumberCategory.fraction;
    if (RegExp(r'^-?\d+\s+\d+\s*/\s*\d+$').hasMatch(input)) return NumberCategory.fraction;
    if (RegExp(r'^\d{1,2}(:\d{2})?\s*(a\.?m\.?|p\.?m\.?)$', caseSensitive: false).hasMatch(input)) {
      return NumberCategory.clock;
    }
    if (RegExp(r'^\d{1,2}:\d{2}$').hasMatch(input)) return NumberCategory.clock;
    // Only now: anything else separated by a colon is a ratio (`2:1`, `10:3`).
    if (RegExp(r'^\d+\s*:\s*\d+$').hasMatch(input)) return NumberCategory.ratio;
    // Decades ("1990s", "80s") and eras ("500 BC", "AD 800") are years.
    if (RegExp(r"^'?\d{2,4}s$").hasMatch(input)) return NumberCategory.year;
    if (RegExp(r'^\d+\s*(bc|ad)$', caseSensitive: false).hasMatch(input)) {
      return NumberCategory.year;
    }
    if (RegExp(r'^ad\s*\d+$', caseSensitive: false).hasMatch(input)) {
      return NumberCategory.year;
    }
    if (RegExp(r'^\d{4}-\d{1,2}-\d{1,2}$').hasMatch(input)) return NumberCategory.date;
    if (_looksLikePhone(input)) return NumberCategory.phone;
    if (RegExp(r'^\d+(st|nd|rd|th)$', caseSensitive: false).hasMatch(input)) {
      return NumberCategory.ordinal;
    }
    // Four digits between 1000 and 2999 are far more likely a year in speech
    // than a "one thousand ..." quantity; the input box lets the user override.
    if (RegExp(r'^\d{4}$').hasMatch(input)) {
      final value = int.parse(input);
      if (value >= 1000 && value <= 2999) return NumberCategory.year;
    }
    if (RegExp(r'^-?[\d,]+\.\d+$').hasMatch(input)) return NumberCategory.decimal;
    if (RegExp(r'^-?[\d,]+$').hasMatch(input)) {
      final digits = input.replaceAll(RegExp(r'[^0-9]'), '');
      return digits.length > 15 ? NumberCategory.cardinal : NumberCategory.cardinal;
    }
    return null;
  }

  /// `+44 20 7946 0958`, `0755-1234-5678`, `(020) 7946 0958`.
  ///
  /// A bare run of digits is *not* treated as a phone number: it reads as a
  /// quantity unless the user picks 电话号码 explicitly.
  static bool _looksLikePhone(String input) {
    final digits = input.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 7) return false;
    final grouped = RegExp(r'[\s\-().]').hasMatch(input);
    return input.startsWith('+') || grouped;
  }

  /// A reading that explains the failure instead of throwing.
  ///
  /// [read] can be asked for any interpretation (`as:` comes straight from the
  /// input box's chips), so a reader may legally be handed something it cannot
  /// parse — `25%` read as a clock time, for instance. Empty text is what the UI
  /// shows as “无法识别”.
  static NumberReading _unreadable(String input, NumberCategory category, String note) =>
      NumberReading(input: input, ukText: '', usText: '', note: note, category: category);

  static String _digitsOnly(String input) => input.replaceAll(RegExp(r'[^0-9]'), '');

  static NumberReading _readCardinal(String input, NumberCategory as) {
    final negative = input.startsWith('-');
    final digits = _digitsOnly(input);
    final value = int.tryParse((negative ? '-' : '') + digits);
    if (value == null) {
      return NumberReading(
        input: input,
        ukText: '',
        usText: '',
        note: '数字超出可朗读范围（最多支持 10¹⁵ 级别）。',
        category: as,
      );
    }
    final note = value.abs() >= 1000000
        ? '大数字按三位一组加刻度词读：thousand → million → billion → trillion；'
            '英音在末尾小组前加 and，美音省略。'
        : (value.abs() >= 100
            ? '英音在百位与尾数之间加 and（one hundred and five）；美音省略（one hundred five）。'
            : '基数词直接读出；13–19 以 -teen 结尾，整十以 -ty 结尾，注意重音位置。');
    return NumberReading(
      input: input,
      ukText: cardinal(value, insertAnd: true),
      usText: cardinal(value, insertAnd: false),
      note: note,
      category: value.abs() >= 1000000 ? NumberCategory.large : as,
    );
  }

  static NumberReading _readOrdinal(String input) {
    final match = RegExp(r'^(\d+)(st|nd|rd|th)$', caseSensitive: false).firstMatch(input);
    if (match == null) return _readCardinal(input, NumberCategory.cardinal);
    final value = int.parse(match.group(1)!);
    final suffix = match.group(2)!.toLowerCase();
    return NumberReading(
      input: input,
      ukText: 'the ${ordinal(value, insertAnd: true)}',
      usText: 'the ${ordinal(value, insertAnd: false)}',
      note: '序数词多用于日期与次序：the $suffix 结尾的写法对应 $value 的序数读法；'
          '英音同样保留 and（the one hundred and fifth），美音省略。',
      category: NumberCategory.ordinal,
    );
  }

  static NumberReading _readDecimal(String input) {
    final trimmed = input.trim();
    if (!trimmed.contains('.')) return _readCardinal(trimmed, NumberCategory.decimal);
    final match = RegExp(r'^(-?)([\d,]+)\.(\d+)$').firstMatch(trimmed);
    if (match == null) {
      return _unreadable(
        trimmed,
        NumberCategory.decimal,
        '不能按小数解析：请使用 3.14、-0.5 这样的写法。',
      );
    }
    final negative = match.group(1) == '-';
    final intPartText = match.group(2)!.replaceAll(',', '');
    final fracPart = match.group(3)!;
    final intPart = int.tryParse(intPartText) ?? 0;
    final sign = negative ? 'minus ' : '';

    String digits(String zeroWord) =>
        fracPart.split('').map((d) => _ones[int.parse(d)] == 'zero' ? zeroWord : _ones[int.parse(d)]).join(' ');

    final ukInt = intPart == 0 ? 'nought' : cardinal(intPart, insertAnd: true);
    final usInt = intPart == 0 ? 'zero' : cardinal(intPart, insertAnd: false);
    final ukFloat = digits('nought');
    final usFloat = digits('zero');
    return NumberReading(
      input: input,
      ukText: '$sign$ukInt point $ukFloat',
      usText: '$sign$usInt point $usFloat',
      note: '小数点读作 point，小数位逐位读出（3.14 = three point one four）。'
          '整数部分为 0 时：英音 nought，美音 zero；口语中也常直接说 point five。',
      category: NumberCategory.decimal,
    );
  }

  static NumberReading _readYear(String input) {
    final value = int.tryParse(_digitsOnly(input));
    if (value == null) {
      return _unreadable(input, NumberCategory.year, '不能按年份解析：请输入 1000–2999 的四位数字。');
    }
    final pairHigh = value ~/ 100;
    final pairLow = value % 100;

    String pair() {
      if (pairLow == 0) return '${cardinal(pairHigh, insertAnd: false)} hundred';
      if (pairLow < 10) {
        return '${cardinal(pairHigh, insertAnd: false)} oh ${_ones[pairLow]}';
      }
      return '${cardinal(pairHigh, insertAnd: false)} ${_under100(pairLow)}';
    }

    String uk;
    String us;
    if (value >= 2000 && value <= 2009) {
      final tail = value % 10 == 0 ? '' : ' ${_ones[value % 10]}';
      uk = 'two thousand${value % 10 == 0 ? '' : ' and'}$tail';
      us = 'two thousand$tail';
    } else if (value >= 2010) {
      // 2026 → "twenty twenty-six" (both accents); "two thousand and twenty-six"
      // is equally correct in British English and is mentioned in the note.
      uk = pair();
      us = pair();
    } else {
      uk = pair();
      us = pair();
    }
    return NumberReading(
      input: input,
      ukText: uk,
      usText: us,
      note: '年份按两位一组读：1999 = nineteen ninety-nine，1905 = nineteen oh five，'
          '1900 = nineteen hundred；2000–2009 用 two thousand (and) five；'
          '2010 起读 twenty ten / twenty twenty-six（也可说 two thousand and twenty-six）。'
          '若作为普通数量（1,234）请切换为「基数词」。',
      category: NumberCategory.year,
    );
  }

  /// `1990s` → "the nineteen nineties"; `80s` → "the eighties"; `2000s` → "the
  /// two thousands". The decade words are the plural tens, so `2020s` needs no
  /// new vocabulary either.
  static NumberReading _readDecade(String input) {
    final digits = input.replaceAll(RegExp(r"[^0-9]"), '');
    final value = int.parse(digits);
    final short = value < 100 ? value : value % 100;
    final head = value < 100 ? '' : '${cardinal(value ~/ 100, insertAnd: false)} ';

    String tail;
    if (value >= 2000 && value < 2010) {
      tail = 'thousands';
    } else if (short == 0) {
      tail = 'hundreds';
    } else if (short % 10 == 0 && short >= 20) {
      tail = _decadeWord(short);
    } else {
      // "the twenty tens" (2010s), "the nineteen hundreds" handled above.
      tail = short < 20 ? '${_under100(short)}s' : '${_under100(short)}s';
    }
    final phrase = 'the $head$tail';
    return NumberReading(
      input: input,
      ukText: phrase,
      usText: phrase,
      note: '年代用整十词的复数：1990s = the nineteen nineties、80s = the eighties、'
          '2010s = the twenty tens；2000–2009 美式 the two thousands，'
          '英式口语戏称 the noughties。前面加 in the 表示"在…年代"。',
      category: NumberCategory.year,
    );
  }

  /// The plural tens used by decades: 20 → twenties … 90 → nineties.
  static String _decadeWord(int tens) {
    const words = {
      20: 'twenties', 30: 'thirties', 40: 'forties', 50: 'fifties',
      60: 'sixties', 70: 'seventies', 80: 'eighties', 90: 'nineties',
    };
    return words[tens] ?? '${_tens[tens ~/ 10]}s';
  }

  /// `500 BC` → "five hundred BC"; `AD 800` → "AD eight hundred".
  ///
  /// Both are read as letter names (bee see / ay dee); BC follows the number and
  /// AD usually precedes it.
  static NumberReading _readEra(String input) {
    final match = RegExp(r'^\s*(?:(?<prefix>ad)\s*)?(?:(?<number>\d+)\s*)?(?<suffix>bc|ad)?\s*$',
            caseSensitive: false)
        .firstMatch(input);
    final prefix = match?.namedGroup('prefix')?.toLowerCase();
    final number = match?.namedGroup('number');
    final suffix = match?.namedGroup('suffix')?.toLowerCase();
    if (number == null) {
      return _unreadable(input, NumberCategory.year, '不能按纪年解析：请使用 500 BC 或 AD 800。');
    }
    final words = cardinal(int.parse(number), insertAnd: true);
    final us = cardinal(int.parse(number), insertAnd: false);
    // AD is usually said before the number (AD eight hundred) but is also written
    // after it (800 AD); BC always follows. Both are letter names.
    final before = prefix == 'ad';
    final marker = before ? 'AD ' : suffix == 'bc' ? ' BC' : ' AD';
    return NumberReading(
      input: input,
      ukText: before ? '$marker$words' : '$words$marker',
      usText: before ? '$marker$us' : '$us$marker',
      note: before
          ? 'AD 多在数字前面（AD eight hundred），字母按名称读作 ay dee。'
          : suffix == 'bc'
              ? 'BC 跟在数字后面（five hundred BC），字母读作 bee see。'
              : 'AD 写在数字后面时读作 eight hundred AD；更常见的是写在前面（AD eight hundred）。',
      category: NumberCategory.year,
    );
  }

  /// Spells a positive magnitude: an integer as a cardinal, otherwise with its
  /// digits after "point" — the same rule the decimal reader uses, shared by the
  /// temperature and multiple readers.
  static String _spellMagnitude(double value, {required bool insertAnd}) {
    if (value == value.roundToDouble()) {
      return cardinal(value.round(), insertAnd: insertAnd);
    }
    final parts = value.toString().split('.');
    final whole = int.parse(parts[0]);
    final head = whole == 0
        ? (insertAnd ? 'nought' : 'zero')
        : cardinal(whole, insertAnd: insertAnd);
    final tail = parts[1]
        .split('')
        .map((digit) => _ones[int.parse(digit)] == 'zero'
            ? (insertAnd ? 'nought' : 'zero')
            : _ones[int.parse(digit)])
        .join(' ');
    return '$head point $tail';
  }

  /// `25°C` → "twenty-five degrees Celsius"; `-5°C` → "minus five degrees
  /// Celsius"; `1°C` → "one degree Celsius".
  static NumberReading _readTemperature(String input) {
    final match = RegExp(
      r'^(-?\d+(?:\.\d+)?)\s*(?:°|deg(?:rees?)?)?\s*(?:c|f)?\s*$',
      caseSensitive: false,
    ).firstMatch(input.trim());
    if (match == null) {
      return _unreadable(input, NumberCategory.temperature, '不能按温度解析：请使用 25°C、98.6°F 这样的写法。');
    }
    final value = double.parse(match.group(1)!);
    final scale = RegExp(r'(c|f)\s*$', caseSensitive: false).firstMatch(input.trim())?.group(1)?.toLowerCase();
    final negative = value < 0;
    final magnitude = value.abs();
    final unit = magnitude == 1 ? 'degree' : 'degrees';
    final scaleWord = scale == 'c' ? ' Celsius' : scale == 'f' ? ' Fahrenheit' : '';
    return NumberReading(
      input: input,
      ukText: '${negative ? 'minus ' : ''}${_spellMagnitude(magnitude, insertAnd: true)} $unit$scaleWord',
      usText: '${negative ? 'minus ' : ''}${_spellMagnitude(magnitude, insertAnd: false)} $unit$scaleWord',
      note: '温度 = 数字 + degree(s) + 温标：°C 读 Celsius（英式口语也说 Centigrade）、°F 读 Fahrenheit；'
          '口语常省略温标，只说 twenty-five degrees。零下说 minus five degrees，也说 five degrees below zero。'
          '注意 1 度是 one degree，不加 -s。',
      category: NumberCategory.temperature,
    );
  }

  /// `2x` → "twice"; `1x` → "once"; `3x` → "three times"; `1.5x` → "one and a
  /// half times".
  static NumberReading _readMultiple(String input) {
    final match = RegExp(r'^(\d+(?:\.\d+)?)\s*[x×]\s*$', caseSensitive: false).firstMatch(input.trim());
    if (match == null) {
      return _unreadable(input, NumberCategory.multiple, '不能按倍数解析：请使用 2x、1.5x 这样的写法。');
    }
    final value = double.parse(match.group(1)!);

    String words({required bool insertAnd}) {
      if (value == 1) return 'once';
      if (value == 2) return 'twice';
      if (value == 0.5) return 'half';
      // 1.5x is "one and a half times", not "one point five times": a half is
      // said as a fraction in this context.
      final whole = value.floor();
      if (value - whole == 0.5 && whole >= 1) {
        return '${cardinal(whole, insertAnd: insertAnd)} and a half times';
      }
      return '${_spellMagnitude(value, insertAnd: insertAnd)} times';
    }

    return NumberReading(
      input: input,
      ukText: words(insertAnd: true),
      usText: words(insertAnd: false),
      note: '一次说 once、两次说 twice（不用 two times，虽然口语也能听到）；三次起用 数字 + times。'
          '倍数比较：twice as much as（是…的两倍）、three times as many；动词用 double / triple。'
          '频率说法：once a week（每周一次）、twice a day、three times a week、once every two weeks。',
      category: NumberCategory.multiple,
    );
  }

  /// `2:1` → "two to one"; `9 out of 10` → "nine out of ten"; `1 in 10` → "one in ten".
  static NumberReading _readRatio(String input) {
    final colon = RegExp(r'^(\d+)\s*:\s*(\d+)$').firstMatch(input.trim());
    if (colon != null) {
      final left = int.parse(colon.group(1)!);
      final right = int.parse(colon.group(2)!);
      return NumberReading(
        input: input,
        ukText: '${cardinal(left, insertAnd: true)} to ${cardinal(right, insertAnd: true)}',
        usText: '${cardinal(left, insertAnd: false)} to ${cardinal(right, insertAnd: false)}',
        note: '比例与比分都用 to：2:1 = two to one、3:2 = three to two；尺寸用 by（4 by 3）。'
            '两位数分钟的时间（3:30）会先被当成时刻，比例可用输入框的「比例」标签强制。',
        category: NumberCategory.ratio,
      );
    }
    final inOut = RegExp(r'^(\d+)\s+(in|out of)\s+(\d+)$', caseSensitive: false).firstMatch(input.trim());
    if (inOut != null) {
      final left = int.parse(inOut.group(1)!);
      final right = int.parse(inOut.group(3)!);
      final connector = inOut.group(2)!.toLowerCase() == 'in' ? 'in' : 'out of';
      return NumberReading(
        input: input,
        ukText: '${cardinal(left, insertAnd: true)} $connector ${cardinal(right, insertAnd: true)}',
        usText: '${cardinal(left, insertAnd: false)} $connector ${cardinal(right, insertAnd: false)}',
        note: '“几个里有几个”用 in / out of：1 in 10 = one in ten、9 out of 10 = nine out of ten；'
            '也可说 the ratio of nine to ten。',
        category: NumberCategory.ratio,
      );
    }
    return _unreadable(input, NumberCategory.ratio, '不能按比例解析：请使用 2:1、3:2、9 out of 10 这样的写法。');
  }

  static NumberReading _readFraction(String input) {
    final simple = RegExp(r'^(-?\d+)\s*/\s*(\d+)$').firstMatch(input);
    final mixed = RegExp(r'^(-?\d+)\s+(\d+)\s*/\s*(\d+)$').firstMatch(input);
    var whole = 0;
    var numerator = 0;
    var denominator = 0;
    if (simple != null) {
      numerator = int.parse(simple.group(1)!);
      denominator = int.parse(simple.group(2)!);
    } else if (mixed != null) {
      whole = int.parse(mixed.group(1)!);
      numerator = int.parse(mixed.group(2)!);
      denominator = int.parse(mixed.group(3)!);
    } else {
      return _readCardinal(input, NumberCategory.fraction);
    }
    if (denominator == 0) {
      return NumberReading(
        input: input,
        ukText: '',
        usText: '',
        note: '分母不能为 0。',
        category: NumberCategory.fraction,
      );
    }

    String plural(String word) {
      if (word == 'half') return 'halves';
      if (word.endsWith('f')) return '${word.substring(0, word.length - 1)}ves';
      if (word.endsWith('y')) return '${word.substring(0, word.length - 1)}ies';
      return '${word}s';
    }

    String fractionOf(int num, int den, {required bool insertAnd, bool article = false}) {
      // 1/2 → "one half" (also "a half"), 3/4 → "three quarters".
      // A mixed number drops the "one": "one and a half", not "one and one half".
      final head = article ? 'a' : cardinal(num, insertAnd: insertAnd);
      if (den == 2) return num == 1 ? '$head half' : '$head halves';
      if (den == 4) return num == 1 ? '$head quarter' : '$head quarters';
      // Above ten, and for improper fractions like 12/7, the ordinal plural
      // stops being natural ("twelve sevenths") and English says "over".
      if (den > 10 || num >= den) {
        return '${cardinal(num, insertAnd: insertAnd)} over ${cardinal(den, insertAnd: insertAnd)}';
      }
      final denominatorWord = ordinal(den, insertAnd: insertAnd);
      return num == 1 ? '$head $denominatorWord' : '$head ${plural(denominatorWord)}';
    }

    final ukFraction = whole != 0 && numerator == 1
        ? fractionOf(numerator, denominator, insertAnd: true, article: true)
        : fractionOf(numerator, denominator, insertAnd: true);
    final usFraction = whole != 0 && numerator == 1
        ? fractionOf(numerator, denominator, insertAnd: false, article: true)
        : fractionOf(numerator, denominator, insertAnd: false);
    final uk = whole == 0 ? ukFraction : '${cardinal(whole, insertAnd: true)} and $ukFraction';
    final us = whole == 0 ? usFraction : '${cardinal(whole, insertAnd: false)} and $usFraction';
    return NumberReading(
      input: input,
      ukText: uk,
      usText: us,
      note: '分子用基数词，分母用序数词；分子大于 1 时分母加 -s（two thirds、three quarters）。'
          '1/2 与 1/4 最常说 half / quarter；分母大于 10 时英语改用 over：three over twelve。',
      category: NumberCategory.fraction,
    );
  }

  static NumberReading _readPercent(String input) {
    final number = input.replaceAll('%', '').trim();
    if (!RegExp(r'^-?[\d.,]+$').hasMatch(number)) {
      return _unreadable(input, NumberCategory.percent, '不能按百分数解析：请使用 25% 这样的写法。');
    }
    final inner = _readDecimal(number.contains('.') ? number : number.replaceAll(',', ''));
    final uk = '${inner.ukText} percent';
    final us = '${inner.usText} percent';
    return NumberReading(
      input: input,
      ukText: uk,
      usText: us,
      note: '百分数 = 数字 + percent（英式也写 per cent）；小数位同样逐位读：'
          '99.9% = ninety-nine point nine percent。',
      category: NumberCategory.percent,
    );
  }

  static NumberReading _readMoney(String input) {
    final symbol = input.substring(0, 1);
    final match = RegExp(r'^([\d,]*)(?:\.(\d{1,2}))?$').firstMatch(input.substring(1).trim());
    if (match == null || (match.group(1)!.isEmpty && (match.group(2) ?? '').isEmpty)) {
      return _unreadable(input, NumberCategory.money, '不能按金额解析：请使用 \$12.50 这样的写法。');
    }
    final whole = int.tryParse(match.group(1)!.replaceAll(',', '') ) ?? 0;
    var cents = match.group(2) ?? '';
    // "3.9" is nine tenths, i.e. ninety cents; "3.90" is the same amount.
    if (cents.length == 1) cents = '${cents}0';
    final centValue = cents.isEmpty ? 0 : int.parse(cents);

    const units = {
      r'$': ('dollar', 'cent'),
      '£': ('pound', 'penny'),
      '€': ('euro', 'cent'),
      '¥': ('yuan', 'fen'),
    };
    final (unit, sub) = units[symbol] ?? ('dollar', 'cent');
    // yuan / yen are invariant (no -s), and a penny becomes pence.
    const invariant = {'yuan', 'fen', 'yen'};
    String unitWord(int count) =>
        invariant.contains(unit) || count == 1 ? unit : '${unit}s';
    String subWord(int count) {
      if (sub == 'penny') return 'pence';
      if (invariant.contains(sub) || count == 1) return sub;
      return '${sub}s';
    }

    String words({required bool insertAnd}) {
      final wholeWords = cardinal(whole, insertAnd: insertAnd);
      if (whole == 0 && centValue > 0) return '${cardinal(centValue, insertAnd: insertAnd)} ${subWord(centValue)}';
      if (centValue == 0) return '$wholeWords ${unitWord(whole)}';
      // "twelve dollars fifty" is the everyday reading; below ten the cents are
      // spelled out so that "five" cannot be mistaken for fifty.
      if (centValue < 10) {
        return '$wholeWords ${unitWord(whole)} and ${cardinal(centValue, insertAnd: insertAnd)} ${subWord(centValue)}';
      }
      return '$wholeWords ${unitWord(whole)} ${_under100(centValue)}';
    }

    return NumberReading(
      input: input,
      ukText: words(insertAnd: true),
      usText: words(insertAnd: false),
      note: '金额先读整数部分与货币单位（复数加 -s），小数部分按两位数读：'
          r'$12.50 = twelve dollars fifty，也可说 twelve dollars and fifty cents；'
          '不足一元时直接读辅币：99¢ = ninety-nine cents。',
      category: NumberCategory.money,
    );
  }

  static NumberReading _readClock(String input) {
    // `7:05 a.m.`, `3 pm` and the bare 24-hour `15:30` all land here. The suffix
    // is what the spoken form needs: English says "seven oh five in the morning"
    // (or, reading the letters, "…ay em").
    final trimmed = input.trim();
    final meridiem = RegExp(r'(a\.?m\.?|p\.?m\.?)\s*$', caseSensitive: false).firstMatch(trimmed);
    final meridiemText = meridiem?.group(1)?.toLowerCase().replaceAll('.', '');
    final clockPart = meridiem == null
        ? trimmed
        : trimmed.substring(0, meridiem.start).trim();
    final match = RegExp(r'^(\d{1,2})(?::(\d{2}))?$').firstMatch(clockPart);
    if (match == null) {
      return _unreadable(input, NumberCategory.clock, '不能按时刻解析：请使用 3:30、15:30、7:05 a.m. 这样的写法。');
    }
    var hour = int.parse(match.group(1)!);
    final minute = match.group(2) == null ? 0 : int.parse(match.group(2)!);
    if (hour > 23 || minute > 59) {
      return NumberReading(
        input: input,
        ukText: '',
        usText: '',
        note: '时刻格式为 24 小时制 hh:mm，例如 15:30。',
        category: NumberCategory.clock,
      );
    }

    // 13:00–23:59 read as the 12-hour clock plus a part of the day; an explicit
    // a.m./p.m. decides it instead.
    var dayPart = '';
    if (meridiemText == 'am') {
      dayPart = ' in the morning';
    } else if (meridiemText == 'pm') {
      dayPart = hour >= 12 && hour < 18 ? ' in the afternoon' : ' in the evening';
    } else if (hour >= 12 && hour < 18) {
      dayPart = ' in the afternoon';
    } else if (hour >= 18) {
      dayPart = ' in the evening';
    }
    if (hour == 12 && minute == 0) {
      return const NumberReading(
        input: '12:00',
        ukText: "twelve o'clock",
        usText: "twelve o'clock",
        note: "正午读 twelve o'clock，也可说 midday / noon。",
        category: NumberCategory.clock,
      );
    }
    if (hour > 12) {
      hour -= 12;
    }
    if (hour == 0) {
      hour = 12;
    }

    final hourWord = cardinal(hour, insertAnd: false);
    String body;
    String note;
    if (minute == 0) {
      body = "$hourWord o'clock";
      note = "整点用 o'clock：three o'clock。";
    } else if (minute == 15) {
      body = 'quarter past $hourWord';
      note = '英音用 past / to；美音同一位置常说 after / of：quarter after three。';
    } else if (minute == 30) {
      body = 'half past $hourWord';
      note = '半点统一说 half past three（美音也说 half after three）。';
    } else if (minute == 45) {
      body = 'quarter to ${cardinal(hour % 12 + 1, insertAnd: false)}';
      note = '45 分说 quarter to + 下一个钟点；美音也说 quarter of / quarter till。';
    } else if (minute % 5 == 0 && minute >= 10 && minute < 30) {
      body = '${_under100(minute)} past $hourWord';
      note = '5 的倍数用 past 表达（twenty past three）；不足 10 分直接读数字。';
    } else if (minute > 30 && minute % 5 == 0) {
      body = '${_under100(60 - minute)} to ${cardinal(hour % 12 + 1, insertAnd: false)}';
      note = '超过 30 分时用 to + 下一个钟点（twenty to four = 3:40）。';
    } else {
      body = '$hourWord ${minute < 10 ? 'oh ${_ones[minute]}' : _under100(minute)}';
      note = '不是 5 的倍数时直接读时分：three twenty-three、seven oh five。';
    }

    return NumberReading(
      input: input,
      ukText: '$body$dayPart',
      usText: '$body$dayPart',
      note: note,
      category: NumberCategory.clock,
    );
  }

  static NumberReading _readDate(String input) {
    final match = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(input.trim());
    if (match == null) {
      return _unreadable(input, NumberCategory.date, '不能按日期解析：请使用 2026-10-08 这样的写法。');
    }
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    if (month < 1 || month > 12 || day < 1 || day > 31) {
      return NumberReading(
        input: input,
        ukText: '',
        usText: '',
        note: '日期格式为 yyyy-mm-dd，例如 2026-10-08。',
        category: NumberCategory.date,
      );
    }
    final yearReading = _readYear('$year');
    return NumberReading(
      input: input,
      ukText: 'the ${ordinal(day, insertAnd: true)} of ${_months[month]} ${yearReading.ukText}',
      usText: '${_months[month]} ${ordinal(day, insertAnd: false)}, ${yearReading.usText}',
      note: '英式先说日再说月（the 8th of October），美式先说月（October 8th）；'
          '书写顺序差异正是英美日期最容易混淆的地方。',
      category: NumberCategory.date,
    );
  }

  static NumberReading _readPhone(String input) {
    final groups = input
        .split(RegExp(r'[\s\-().]+'))
        .where((g) => _digitsOnly(g).isNotEmpty || g == '+')
        .map((g) => g.replaceAll('+', ''))
        .toList();

    /// Three digits ending in `00` are said as a number: `1-800-…` is
    /// "one eight hundred …" in American English, `0800` is "oh eight hundred".
    String? groupedReading(String digits, String? previous) {
      if (digits.length == 3 && digits.endsWith('00') && previous == '1') {
        return '${_ones[int.parse(digits[0])]} hundred';
      }
      if (digits.length == 4 && digits.startsWith('0') && digits.endsWith('00')) {
        return 'oh ${_ones[int.parse(digits[1])]} hundred';
      }
      return null;
    }

    String digitsToWords(String digits, {required bool uk}) {
      final words = <String>[];
      var i = 0;
      while (i < digits.length) {
        final digit = digits[i];
        // A run of the same digit: British English says "double seven" /
        // "triple seven", American English normally repeats the digit.
        var run = 1;
        while (i + run < digits.length && digits[i + run] == digit) {
          run++;
        }
        final word = digit == '0' ? 'oh' : _ones[int.parse(digit)];
        if (uk && run == 2) {
          words.add('double $word');
        } else if (uk && run == 3) {
          words.add('triple $word');
        } else {
          for (var k = 0; k < run; k++) {
            words.add(word);
          }
        }
        i += run;
      }
      return words.join(' ');
    }

    final ukParts = <String>[];
    final usParts = <String>[];
    final international = input.trimLeft().startsWith('+');
    var previousDigits = '';
    for (var i = 0; i < groups.length; i++) {
      final digits = _digitsOnly(groups[i]);
      if (digits.isEmpty) continue;
      final grouped = groupedReading(digits, previousDigits);
      // A country code is read digit by digit ("plus four four"); the
      // double/triple compression belongs to the subscriber number.
      final compress = !(international && i == 0);
      ukParts.add(grouped ?? digitsToWords(digits, uk: compress));
      usParts.add(grouped ?? digitsToWords(digits, uk: false));
      previousDigits = digits;
    }
    return NumberReading(
      input: input,
      ukText: international ? 'plus ${ukParts.join(', ')}' : ukParts.join(', '),
      usText: international ? 'plus ${usParts.join(', ')}' : usParts.join(', '),
      note: '电话号码逐位读出，0 读 oh，国际区号前的 + 读 plus；'
          '英音把连续两位读作 double（007 → double oh seven），美音通常逐个重复。'
          '输入中的空格与短横会转换成朗读时的自然停顿。',
      category: NumberCategory.phone,
    );
  }

  /// The one-word readings of `0` that English uses in different contexts.
  static NumberReading zeroReading(String context) {
    switch (context) {
      case 'phone':
        return const NumberReading(
          input: '0（电话号码中）',
          ukText: 'oh',
          usText: 'oh',
          note: '电话号码、房间号里的 0 读 oh（007 = double oh seven）。',
          category: NumberCategory.zero,
        );
      case 'decimal':
        return const NumberReading(
          input: '0（小数点前后）',
          ukText: 'nought',
          usText: 'zero',
          note: '0.5：英音 nought point five，美音 zero point five。',
          category: NumberCategory.zero,
        );
      case 'score':
        return const NumberReading(
          input: '3-0（比分）',
          ukText: 'three nil',
          usText: 'three nothing',
          note: '英式比分用 nil（three nil），美式常说 nothing / zero。',
          category: NumberCategory.zero,
        );
      case 'tennis':
        return const NumberReading(
          input: '40-0（网球）',
          ukText: 'forty love',
          usText: 'forty love',
          note: '网球比分 0 读 love。',
          category: NumberCategory.zero,
        );
      case 'temperature':
        return const NumberReading(
          input: '0°C',
          ukText: 'zero degrees',
          usText: 'zero degrees',
          note: '温度中的 0 读 zero degrees；零下说 minus five degrees。',
          category: NumberCategory.zero,
        );
      default:
        return const NumberReading(
          input: '0',
          ukText: 'zero',
          usText: 'zero',
          note: '单独的数字 0 英美都读 zero；英音也常用 nought 表示“零”。',
          category: NumberCategory.zero,
        );
    }
  }
}
