import 'number_model.dart';
import 'number_speller.dart';

/// The teaching examples shown in the 分类展示 grid.
///
/// Every card stores only *what is written*; the sentence is produced by
/// [NumberSpeller], so a card can never disagree with the rule it demonstrates.
class NumberData {
  const NumberData._();

  static const List<NumberExample> allExamples = [
    // ------------------------------------------------------------- cardinals
    //
    // English cardinal words are irregular up to twelve and regular from
    // twenty-one on, so the irregular ones are listed one by one and every
    // regular range is taught as a single rule card.
    NumberExample.word(
      input: 'zero', value: '0', category: NumberCategory.cardinal,
      hint: '0：单独读 zero；电话号码里读 oh，比分读 nil，网球读 love',
    ),
    NumberExample.word(input: 'one', value: '1', category: NumberCategory.cardinal, hint: '1：一个音节 /wʌn/'),
    NumberExample.word(input: 'two', value: '2', category: NumberCategory.cardinal, hint: '2：/tuː/'),
    NumberExample.word(input: 'three', value: '3', category: NumberCategory.cardinal, hint: '3：/θriː/，th 是咬舌清音'),
    NumberExample.word(input: 'four', value: '4', category: NumberCategory.cardinal, hint: '4：/fɔː/，英音不卷舌'),
    NumberExample.word(input: 'five', value: '5', category: NumberCategory.cardinal, hint: '5：/faɪv/，词尾 v 要出声'),
    NumberExample.word(input: 'six', value: '6', category: NumberCategory.cardinal, hint: '6：/sɪks/，词尾 ks'),
    NumberExample.word(input: 'seven', value: '7', category: NumberCategory.cardinal, hint: '7：/ˈsevn/，两个音节'),
    NumberExample.word(input: 'eight', value: '8', category: NumberCategory.cardinal, hint: '8：/eɪt/，gh 不发音'),
    NumberExample.word(input: 'nine', value: '9', category: NumberCategory.cardinal, hint: '9：/naɪn/'),
    NumberExample.word(input: 'ten', value: '10', category: NumberCategory.cardinal, hint: '10：/ten/'),
    NumberExample.word(input: 'eleven', value: '11', category: NumberCategory.cardinal, hint: '11：重音在第二音节 /ɪˈlevn/'),
    NumberExample.word(input: 'twelve', value: '12', category: NumberCategory.cardinal, hint: '12：/twelv/，ve 结尾'),

    // 13–19: the -teen family, with three spelling traps.
    NumberExample.word(input: 'thirteen', value: '13', category: NumberCategory.cardinal, hint: '13：-teen 结尾，重音后移 /ˌθɜːˈtiːn/'),
    NumberExample.word(input: 'fourteen', value: '14', category: NumberCategory.cardinal, hint: '14：-teen 结尾，重音后移'),
    NumberExample.word(input: 'fifteen', value: '15', category: NumberCategory.cardinal, hint: '15：five → fif-，不是 fiveteen'),
    NumberExample.word(input: 'sixteen', value: '16', category: NumberCategory.cardinal, hint: '16：-teen 结尾'),
    NumberExample.word(input: 'seventeen', value: '17', category: NumberCategory.cardinal, hint: '17：-teen 结尾'),
    NumberExample.word(input: 'eighteen', value: '18', category: NumberCategory.cardinal, hint: '18：eighteen，只写一个 t'),
    NumberExample.word(input: 'nineteen', value: '19', category: NumberCategory.cardinal, hint: '19：-teen 结尾'),

    // The tens: -ty, again with spelling traps.
    NumberExample.word(input: 'twenty', value: '20', category: NumberCategory.cardinal, hint: '20：不是 twoty；-ty 结尾重音在前'),
    NumberExample.word(input: 'thirty', value: '30', category: NumberCategory.cardinal, hint: '30：three → thir-'),
    NumberExample.word(input: 'forty', value: '40', category: NumberCategory.cardinal, hint: '40：forty，没有 u（fourty 是错的）'),
    NumberExample.word(input: 'fifty', value: '50', category: NumberCategory.cardinal, hint: '50：five → fif-'),
    NumberExample.word(input: 'sixty', value: '60', category: NumberCategory.cardinal, hint: '60：-ty 结尾'),
    NumberExample.word(input: 'seventy', value: '70', category: NumberCategory.cardinal, hint: '70：-ty 结尾'),
    NumberExample.word(input: 'eighty', value: '80', category: NumberCategory.cardinal, hint: '80：eight → eigh-，只有一个 t'),
    NumberExample.word(input: 'ninety', value: '90', category: NumberCategory.cardinal, hint: '90：nine → nine-ty，去掉 e'),

    // 21–99 is one rule, not eighty cards.
    NumberExample.pattern(
      input: '21–99',
      category: NumberCategory.cardinal,
      hint: '规则：十位 + 个位，中间加连字符。twenty-one、thirty-four、ninety-nine —— 21 以上全是这个规则，不用逐个数背。',
      samples: ['twenty-one', 'thirty-four', 'ninety-nine'],
    ),
    NumberExample.word(input: 'hundred', value: '100', category: NumberCategory.cardinal, hint: '100：hundred，前面要有数字（one hundred；英式口语也可说 a hundred）'),
    NumberExample.word(input: 'thousand', value: '1,000', category: NumberCategory.cardinal, hint: '1,000：thousand，千位以上每三位一组'),
    NumberExample.pattern(
      input: 'hundred 以上',
      category: NumberCategory.cardinal,
      hint: '规则：英音在百位与尾数之间加 and（one hundred and one、one thousand and twenty-three），美音省略；每三位一组接 thousand / million / billion。',
      samples: ['1,023', '1,234', '2,500,000'],
    ),

    // -------------------------------------------------------------- ordinals
    //
    // Same split: 1st–12th are irregular, 21st and up only change the last word.
    NumberExample.word(input: 'first', value: '1st', category: NumberCategory.ordinal, hint: '1st：不是 oneth'),
    NumberExample.word(input: 'second', value: '2nd', category: NumberCategory.ordinal, hint: '2nd：second'),
    NumberExample.word(input: 'third', value: '3rd', category: NumberCategory.ordinal, hint: '3rd：third'),
    NumberExample.word(input: 'fourth', value: '4th', category: NumberCategory.ordinal, hint: '4th：fourth，不是 forth'),
    NumberExample.word(input: 'fifth', value: '5th', category: NumberCategory.ordinal, hint: '5th：five → fifth，f 变 v'),
    NumberExample.word(input: 'sixth', value: '6th', category: NumberCategory.ordinal, hint: '6th：sixth'),
    NumberExample.word(input: 'seventh', value: '7th', category: NumberCategory.ordinal, hint: '7th：seventh'),
    NumberExample.word(input: 'eighth', value: '8th', category: NumberCategory.ordinal, hint: '8th：eighth，eight 只加 h'),
    NumberExample.word(input: 'ninth', value: '9th', category: NumberCategory.ordinal, hint: '9th：nine → ninth，去掉 e'),
    NumberExample.word(input: 'tenth', value: '10th', category: NumberCategory.ordinal, hint: '10th：tenth'),
    NumberExample.word(input: 'eleventh', value: '11th', category: NumberCategory.ordinal, hint: '11th：eleventh'),
    NumberExample.word(input: 'twelfth', value: '12th', category: NumberCategory.ordinal, hint: '12th：twelve → twelfth，全表最麻烦的拼写'),
    NumberExample.word(input: 'thirteenth', value: '13th', category: NumberCategory.ordinal, hint: '13th：-teenth 结尾，重音在词尾'),
    NumberExample.word(input: 'fourteenth', value: '14th', category: NumberCategory.ordinal, hint: '14th：-teenth 结尾'),
    NumberExample.word(input: 'fifteenth', value: '15th', category: NumberCategory.ordinal, hint: '15th：-teenth 结尾'),
    NumberExample.word(input: 'sixteenth', value: '16th', category: NumberCategory.ordinal, hint: '16th：-teenth 结尾'),
    NumberExample.word(input: 'seventeenth', value: '17th', category: NumberCategory.ordinal, hint: '17th：-teenth 结尾'),
    NumberExample.word(input: 'eighteenth', value: '18th', category: NumberCategory.ordinal, hint: '18th：-teenth 结尾'),
    NumberExample.word(input: 'nineteenth', value: '19th', category: NumberCategory.ordinal, hint: '19th：-teenth 结尾'),
    NumberExample.word(input: 'twentieth', value: '20th', category: NumberCategory.ordinal, hint: '20th：twenty → twentieth，y 变 ie'),
    NumberExample.word(input: 'thirtieth', value: '30th', category: NumberCategory.ordinal, hint: '30th：-tieth 结尾'),
    NumberExample.word(input: 'fortieth', value: '40th', category: NumberCategory.ordinal, hint: '40th：-tieth 结尾'),
    NumberExample.word(input: 'fiftieth', value: '50th', category: NumberCategory.ordinal, hint: '50th：-tieth 结尾'),
    NumberExample.word(input: 'sixtieth', value: '60th', category: NumberCategory.ordinal, hint: '60th：-tieth 结尾'),
    NumberExample.word(input: 'seventieth', value: '70th', category: NumberCategory.ordinal, hint: '70th：-tieth 结尾'),
    NumberExample.word(input: 'eightieth', value: '80th', category: NumberCategory.ordinal, hint: '80th：-tieth 结尾'),
    NumberExample.word(input: 'ninetieth', value: '90th', category: NumberCategory.ordinal, hint: '90th：-tieth 结尾'),
    NumberExample.pattern(
      input: '21st–99th',
      category: NumberCategory.ordinal,
      hint: '规则：只把最后一段变成序数，前面不动。twenty-first、thirty-second、ninety-ninth。',
      samples: ['twenty-first', 'thirty-second', 'ninety-ninth'],
    ),
    NumberExample.word(input: 'hundredth', value: '100th', category: NumberCategory.ordinal, hint: '100th：hundredth'),
    NumberExample.word(input: 'thousandth', value: '1,000th', category: NumberCategory.ordinal, hint: '1,000th：thousandth'),
    NumberExample.word(input: 'millionth', value: '1,000,000th', category: NumberCategory.ordinal, hint: '1,000,000th：millionth'),

    // ----------------------------------------------------------- large numbers
    NumberExample.word(input: 'million', value: '1,000,000', category: NumberCategory.large, hint: '百万：前面有数字时不加 -s（two million）'),
    NumberExample.word(input: 'billion', value: '1,000,000,000', category: NumberCategory.large, hint: '十亿：billion（英美同为短级差）'),
    NumberExample.word(input: 'trillion', value: '1,000,000,000,000', category: NumberCategory.large, hint: '万亿：trillion'),
    NumberExample(input: '1,500,000', category: NumberCategory.large, hint: 'one million five hundred thousand'),
    NumberExample(input: '2,500,000', category: NumberCategory.large, hint: 'two million five hundred thousand'),
    NumberExample(input: '3,000,000,000', category: NumberCategory.large, hint: 'three billion'),
    NumberExample(input: '1,000,000,000,000', category: NumberCategory.large, hint: 'one trillion'),
    NumberExample.pattern(
      input: '三位一组',
      category: NumberCategory.large,
      hint: '从右往左每三位一组，接 thousand / million / billion / trillion；million 等前面有数字时不加 -s（two million），复数 -s 只出现在最后的名词上。',
      samples: ['1,000,000', '2,500,000', '3,000,000,000'],
    ),

    // --------------------------------------------------------------- decimals
    NumberExample(
      input: '0.5',
      category: NumberCategory.decimal,
      as: NumberCategory.decimal,
      hint: '零的读法：英 nought / 美 zero',
    ),
    NumberExample(input: '3.14', category: NumberCategory.decimal, hint: '小数点后逐位读 one four'),
    NumberExample(input: '-1.5', category: NumberCategory.decimal, hint: '负数先读 minus'),
    NumberExample(input: '0.05', category: NumberCategory.decimal, hint: '0.05 = point oh five'),
    NumberExample(input: '0.007', category: NumberCategory.decimal, hint: '连续的零逐个读：point nought nought seven'),
    NumberExample(input: '1,234.56', category: NumberCategory.decimal, hint: '整数部分照常读，再接 point + 逐位小数'),
    NumberExample.pattern(
      input: '0 的读法',
      category: NumberCategory.decimal,
      hint: '小数点前后的 0：英音 nought，美音 zero，口语也读 oh（point oh five）。整数部分是 0 时常直接省略：0.5 = point five。',
      samples: ['0.5', '0.05', '1.05'],
    ),
    NumberExample.pattern(
      input: '逐位读',
      category: NumberCategory.decimal,
      hint: '小数点后一位一位读：3.14 = three point one four（不读 fourteen）；数学课上也会说 decimal point。',
      samples: ['3.14', '0.007', '1,234.56'],
    ),

    // -------------------------------------------------------------- fractions
    NumberExample(input: '1/2', category: NumberCategory.fraction, hint: 'one half（口语常说 a half）'),
    NumberExample(input: '1/3', category: NumberCategory.fraction, hint: '分子 1：分母用单数 third'),
    NumberExample(input: '3/4', category: NumberCategory.fraction, hint: 'three quarters（英式最爱用的分数）'),
    NumberExample(input: '2/5', category: NumberCategory.fraction, hint: '分子 >1：分母加 -s，two fifths'),
    NumberExample(input: '1 1/2', category: NumberCategory.fraction, hint: '带分数：one and a half'),
    NumberExample(input: '7/8', category: NumberCategory.fraction, hint: '分母 8：seven eighths（/ts/ /θs/ 连读要多练）'),
    NumberExample.pattern(
      input: '分母的规律',
      category: NumberCategory.fraction,
      hint: '分母 2 用 half/halves、4 用 quarter(s)，其余用序数词；分子大于 1 时分母加 -s：two thirds、three fifths。',
      samples: ['1/2', '1/4', '2/3', '3/5'],
    ),
    NumberExample.pattern(
      input: 'over 的用法',
      category: NumberCategory.fraction,
      hint: '分母大于 10 或分数较复杂时改用 over：3/12 = three over twelve；假分数也常这样读。',
      samples: ['3/12', '12/7', '23/100'],
    ),
    NumberExample.pattern(
      input: 'of 搭配与弱读',
      category: NumberCategory.fraction,
      hint: '分数接名词要加 of：2/3 of the students；口语里 1/2、1/4 常弱读成 a half / a quarter。',
      samples: ['1/3', '2/3', '3/4'],
    ),

    // ------------------------------------------------------------ percentages
    NumberExample(
      input: '25%',
      category: NumberCategory.percent,
      as: NumberCategory.percent,
      hint: 'percent 没有复数，也不加 of'),
    NumberExample(
      input: '99.9%',
      category: NumberCategory.percent,
      as: NumberCategory.percent,
      hint: '小数百分数逐位读：point nine'),
    NumberExample(
      input: '100%',
      category: NumberCategory.percent,
      as: NumberCategory.percent,
      hint: 'one hundred percent（也可说 a hundred percent）'),
    NumberExample(
      input: '0.5%',
      category: NumberCategory.percent,
      as: NumberCategory.percent,
      hint: '小数百分数逐位读：英 nought point five / 美 zero point five'),
    NumberExample(
      input: '150%',
      category: NumberCategory.percent,
      as: NumberCategory.percent,
      hint: '超过 100% 照常读：one hundred and fifty percent'),
    NumberExample.pattern(
      input: 'per cent / percent',
      category: NumberCategory.percent,
      hint: '英式写作 per cent（两个词），美式写作 percent（一个词），读法一样；percent 没有复数。',
      samples: ['20%', '75%'],
    ),
    NumberExample.pattern(
      input: 'X percent of',
      category: NumberCategory.percent,
      hint: '接名词时加 of，名词通常用复数：80% of the students / 50% of the water。',
      samples: ['80%', '50%'],
    ),

    // ------------------------------------------------------------ temperature
    NumberExample(input: '0°C', category: NumberCategory.temperature, hint: '冰点：zero degrees Celsius（也说 freezing）'),
    NumberExample(input: '25°C', category: NumberCategory.temperature, hint: '常温：twenty-five degrees Celsius（口语常省略温标）'),
    NumberExample(input: '1°C', category: NumberCategory.temperature, hint: '单数：one degree，不加 -s'),
    NumberExample(input: '-5°C', category: NumberCategory.temperature, hint: '零下：minus five degrees Celsius'),
    NumberExample(input: '37°C', category: NumberCategory.temperature, hint: '体温：thirty-seven degrees'),
    NumberExample(input: '98.6°F', category: NumberCategory.temperature, hint: '华氏小数：ninety-eight point six degrees Fahrenheit'),
    NumberExample.pattern(
      input: '摄氏度 / 华氏度',
      category: NumberCategory.temperature,
      hint: '°C 读 Celsius（英式口语也说 Centigrade），°F 读 Fahrenheit；口语常省略温标，只说 twenty-five degrees。',
      samples: ['25°C', '32°F', '98.6°F'],
    ),
    NumberExample.pattern(
      input: '零下的说法',
      category: NumberCategory.temperature,
      hint: '零下两种说法：minus five degrees（正式）或 five degrees below zero（口语，也说 five below）。',
      samples: ['-5°C', '-12°C'],
    ),

    // ------------------------------------------------------ multiples & times
    NumberExample(input: '1x', category: NumberCategory.multiple, hint: '一次：once（不说 one time）'),
    NumberExample(input: '2x', category: NumberCategory.multiple, hint: '两次：twice（不是 two times）'),
    NumberExample(input: '3x', category: NumberCategory.multiple, hint: '三次起：three times'),
    NumberExample(input: '1.5x', category: NumberCategory.multiple, hint: '一倍半：one and a half times'),
    NumberExample.word(input: 'once a week', value: '1/week', category: NumberCategory.multiple, hint: '频率：每周一次，也说 weekly'),
    NumberExample.word(input: 'twice a day', value: '2/day', category: NumberCategory.multiple, hint: '频率：每天两次'),
    NumberExample.word(input: 'three times a week', value: '3/week', category: NumberCategory.multiple, hint: '频率：每周三次'),
    NumberExample.word(input: 'once every two weeks', value: '1/2w', category: NumberCategory.multiple, hint: '每两周一次，也说 fortnightly'),
    NumberExample.pattern(
      input: 'once / twice / N times',
      category: NumberCategory.multiple,
      hint: '一次 once、两次 twice 是不规则说法；三次起用 数字 + times（three times、ten times）。',
      samples: ['1x', '2x', '3x', '10x'],
    ),
    NumberExample.pattern(
      input: '倍数比较',
      category: NumberCategory.multiple,
      hint: '“是…的两倍”说 twice as much as（不可数）/ twice as many（可数）；三倍以上 three times as …；动词用 double / triple。',
      samples: ['2x', '3x'],
    ),
    NumberExample.pattern(
      input: '频率表达',
      category: NumberCategory.multiple,
      hint: '频率 = once / twice / N times + a day | week | month | year，或 once every two weeks；也常用 every + 时间。',
      samples: ['once a week', 'twice a day', 'three times a week'],
    ),

    // ----------------------------------------------------------------- ratios
    NumberExample(input: '2:1', category: NumberCategory.ratio, hint: '比例/赔率：two to one'),
    NumberExample(input: '3:2', category: NumberCategory.ratio, hint: 'three to two（比分同样用 to）'),
    NumberExample(input: '4:3', category: NumberCategory.ratio, hint: '画幅：four to three，也说 four by three'),
    NumberExample(input: '1 in 10', category: NumberCategory.ratio, hint: '十中之一：one in ten'),
    NumberExample(input: '9 out of 10', category: NumberCategory.ratio, hint: '十分之九：nine out of ten（命中率/通过率常用）'),
    NumberExample.pattern(
      input: '「:」读 to',
      category: NumberCategory.ratio,
      hint: '2:1 = two to one、3:2 = three to two；尺寸用 by（4 by 3）；两位数分钟的时间（3:30）会先被当成时刻，可用「比例」标签强制。',
      samples: ['2:1', '3:2', '4:3'],
    ),
    NumberExample.pattern(
      input: 'in / out of',
      category: NumberCategory.ratio,
      hint: '“几个里有几个”用 in 或 out of：1 in 10、9 out of 10；也可说 the ratio of nine to ten。',
      samples: ['1 in 10', '9 out of 10'],
    ),

    // ------------------------------------------------------------------ years
    NumberExample(input: '1999', category: NumberCategory.year, hint: '两位一组：nineteen ninety-nine'),
    NumberExample(input: '1905', category: NumberCategory.year, hint: '中间有零用 oh：nineteen oh five'),
    NumberExample(input: '1900', category: NumberCategory.year, hint: '整百年：nineteen hundred'),
    NumberExample(input: '2005', category: NumberCategory.year, hint: '英 two thousand and five / 美省略 and'),
    NumberExample(input: '2026', category: NumberCategory.year, hint: 'twenty twenty-six（也说 two thousand and …）'),
    NumberExample(input: '1066', category: NumberCategory.year, hint: '1000–1099：ten sixty-six'),
    NumberExample(input: '1100', category: NumberCategory.year, hint: '整百：eleven hundred'),
    NumberExample.pattern(
      input: '2010 起两种读法',
      category: NumberCategory.year,
      hint: '2010 之后 twenty ten 与 two thousand and ten（美音 two thousand ten）都正确。',
      samples: ['2010', '2026'],
    ),
    NumberExample.pattern(
      input: '年代',
      category: NumberCategory.year,
      hint: '年代 = 整十词复数 + the：1990s = the nineteen nineties、80s = the eighties、2010s = the twenty tens；2000–2009 读 the two thousands（英式口语 the noughties），前面用 in。',
      samples: ['1990s', '80s', '2000s'],
    ),
    NumberExample.pattern(
      input: 'BC / AD',
      category: NumberCategory.year,
      hint: 'BC 跟在数字后（500 BC = five hundred BC），AD 多在数字前（AD 800）；字母按名称读 bee see / ay dee。',
      samples: ['500 BC', 'AD 800'],
    ),

    // ------------------------------------------------------------ clock time
    NumberExample(input: '3:00', category: NumberCategory.clock, hint: "整点：three o'clock"),
    NumberExample(input: '3:15', category: NumberCategory.clock, hint: '英 quarter past / 美 quarter after'),
    NumberExample(input: '3:30', category: NumberCategory.clock, hint: 'half past three'),
    NumberExample(input: '3:45', category: NumberCategory.clock, hint: 'quarter to four'),
    NumberExample(input: '7:05', category: NumberCategory.clock, hint: 'seven oh five'),
    NumberExample(input: '15:30', category: NumberCategory.clock, hint: '24 小时制会自动转成下午说法'),
    NumberExample(input: '12:00', category: NumberCategory.clock, hint: "正午：twelve o'clock，也说 noon / midday"),
    NumberExample(input: '0:00', category: NumberCategory.clock, hint: "午夜：twelve o'clock at night，也说 midnight"),
    NumberExample.pattern(
      input: 'past / to 规则',
      category: NumberCategory.clock,
      hint: '15 分 quarter past、30 分 half past、45 分 quarter to；10–25 分用 N past，35–55 分用 N to；其余直接读时与分（3:23 = three twenty-three）。',
      samples: ['3:15', '3:30', '3:45', '3:20', '3:40'],
    ),
    NumberExample.pattern(
      input: 'a.m. / p.m.',
      category: NumberCategory.clock,
      hint: '上午 7:05 = seven oh five in the morning（也可读字母 ay em）；下午 3 = three in the afternoon；24 小时制会自动换算。',
      samples: ['7:05 a.m.', '3 pm', '15:30'],
    ),

    // ------------------------------------------------------------------ money
    NumberExample(input: r'$12.50', category: NumberCategory.money, hint: 'twelve dollars fifty'),
    NumberExample(input: '£3.99', category: NumberCategory.money, hint: 'three pounds ninety-nine'),
    NumberExample(input: '€20', category: NumberCategory.money, hint: 'twenty euros（复数加 -s）'),
    NumberExample(input: r'$0.99', category: NumberCategory.money, hint: '不足一元读辅币：ninety-nine cents'),
    NumberExample(input: r'$1', category: NumberCategory.money, hint: 'one dollar（单数不加 -s）'),
    NumberExample(input: '£0.50', category: NumberCategory.money, hint: '英式辅币用 pence：fifty pence'),
    NumberExample(input: '£1.50', category: NumberCategory.money, hint: 'one pound fifty'),
    NumberExample(input: r'$2,000,000', category: NumberCategory.money, hint: 'two million dollars（million 不加 -s）'),
    NumberExample.pattern(
      input: '符号与单位',
      category: NumberCategory.money,
      hint: r'符号读单位名：$ → dollar(s)、£ → pound(s)、€ → euro(s)、¥ → yuan；一个单位用单数，两个以上加 -s。',
      samples: [r'$1', '£1', '€5', '¥10'],
    ),
    NumberExample.pattern(
      input: '口语省略单位',
      category: NumberCategory.money,
      hint: r'口语常省掉后面的单位：$12.50 = twelve fifty、$9.99 = nine ninety-nine；完整说法是 twelve dollars and fifty cents。',
      samples: [r'$12.50', r'$9.99', '£3.99'],
    ),
    NumberExample.pattern(
      input: '复数位置',
      category: NumberCategory.money,
      hint: r'复数 -s 只加在最后那个单位上，million/thousand 不变：$2,000,000 = two million dollars。',
      samples: [r'$2,000,000', r'$1,500'],
    ),

    // ---------------------------------------------------------------- phone
    NumberExample(
      input: '+44 20 7946 0958',
      category: NumberCategory.phone,
      as: NumberCategory.phone,
      hint: '逐位读，分组处停顿，+ 读 plus',
    ),
    NumberExample(
      input: '0755-1234-5678',
      category: NumberCategory.phone,
      as: NumberCategory.phone,
      hint: '0 读 oh；英音连续两位读 double',
    ),
    NumberExample(
      input: '007',
      category: NumberCategory.phone,
      as: NumberCategory.phone,
      hint: '英 double oh seven / 美 oh oh seven',
    ),
    NumberExample(
      input: '203',
      category: NumberCategory.phone,
      as: NumberCategory.phone,
      hint: '房间号/门牌/公交：two oh three（0 读 oh）',
    ),
    NumberExample(
      input: '1001',
      category: NumberCategory.phone,
      as: NumberCategory.phone,
      hint: '编号/密码：one double oh one（英）/ one oh oh one（美）',
    ),
    NumberExample(
      input: '1-800-555-0199',
      category: NumberCategory.phone,
      as: NumberCategory.phone,
      hint: '美式免费号：1-800 读 one eight hundred，不是 one eight oh oh',
    ),
    NumberExample.pattern(
      input: '分组与停顿',
      category: NumberCategory.phone,
      hint: '逐位读，输入里的空格与短横变成停顿；0 读 oh，前面的 + 读 plus；分机号说 extension。',
      samples: ['+44 20 7946 0958', '0755-1234-5678'],
    ),
    NumberExample.pattern(
      input: 'double / triple',
      category: NumberCategory.phone,
      hint: '英音把连续两位读 double、三位读 triple（007 = double oh seven、555 = triple five）；美音通常逐个重复。',
      samples: ['007', '0800 123 456'],
    ),
    NumberExample.pattern(
      input: '800 号段',
      category: NumberCategory.phone,
      hint: '末尾是 00 的三位数按数值读：美式 1-800 读 one eight hundred，英式 0800 读 oh eight hundred。',
      samples: ['1-800-555-0199', '0800 123 456'],
    ),

    // ------------------------------------------------------------------ dates
    NumberExample(input: '2026-10-08', category: NumberCategory.date, hint: '英 the 8th of October / 美 October 8th'),
    NumberExample(input: '2026-01-01', category: NumberCategory.date, hint: '序数词读日，年份两位一组'),
    NumberExample(input: '2026-05-03', category: NumberCategory.date, hint: '月份用专有名词，首字母大写'),

    // The twelve months and the seven weekdays. Dates are the one place these
    // words turn up, and they are proper nouns: capitalised, with their own
    // recordings, and irregular enough to be learnt one by one.
    NumberExample.word(input: 'January', value: '一月', category: NumberCategory.date, hint: '一月：Jan.，/ˈdʒænjuəri/，重音在首音节'),
    NumberExample.word(input: 'February', value: '二月', category: NumberCategory.date, hint: '二月：Feb.，/ˈfebruəri/，第一个 r 常被略读'),
    NumberExample.word(input: 'March', value: '三月', category: NumberCategory.date, hint: '三月：Mar.，/mɑːtʃ/，英式元音是长音 /ɑː/'),
    NumberExample.word(input: 'April', value: '四月', category: NumberCategory.date, hint: '四月：Apr.，/ˈeɪprəl/，重音在首音节'),
    NumberExample.word(input: 'May', value: '五月', category: NumberCategory.date, hint: '五月：May 三个字母，不缩写，/meɪ/'),
    NumberExample.word(input: 'June', value: '六月', category: NumberCategory.date, hint: '六月：Jun.，/dʒuːn/，u 读 /uː/ 不是 /juː/'),
    NumberExample.word(input: 'July', value: '七月', category: NumberCategory.date, hint: '七月：Jul.，/dʒuˈlaɪ/，重音在第二音节'),
    NumberExample.word(input: 'August', value: '八月', category: NumberCategory.date, hint: '八月：Aug.，英 /ɔːˈɡʌst/、美 /ˈɔːɡəst/，重音不同'),
    NumberExample.word(input: 'September', value: '九月', category: NumberCategory.date, hint: '九月：英 Sept. / 美 Sep.，/sepˈtembə(r)/，重音在中间'),
    NumberExample.word(input: 'October', value: '十月', category: NumberCategory.date, hint: '十月：Oct.，/ɒkˈtəʊbə(r)/，重音在中间'),
    NumberExample.word(input: 'November', value: '十一月', category: NumberCategory.date, hint: '十一月：Nov.，/nəʊˈvembə(r)/，重音在中间'),
    NumberExample.word(input: 'December', value: '十二月', category: NumberCategory.date, hint: '十二月：Dec.，/dɪˈsembə(r)/，重音在中间'),

    NumberExample.word(input: 'Monday', value: '星期一', category: NumberCategory.date, hint: '星期一：Mon.，/ˈmʌndeɪ/，前面用 on（on Monday）'),
    NumberExample.word(input: 'Tuesday', value: '星期二', category: NumberCategory.date, hint: '星期二：Tue. / Tues.，英 /ˈtjuːzdeɪ/、美 /ˈtuːzdeɪ/'),
    NumberExample.word(input: 'Wednesday', value: '星期三', category: NumberCategory.date, hint: '星期三：Wed.，d 不发音 /ˈwenzdeɪ/'),
    NumberExample.word(input: 'Thursday', value: '星期四', category: NumberCategory.date, hint: '星期四：Thu. / Thur.，/ˈθɜːzdeɪ/，开头是咬舌 /θ/'),
    NumberExample.word(input: 'Friday', value: '星期五', category: NumberCategory.date, hint: '星期五：Fri.，/ˈfraɪdeɪ/，前面用 on'),
    NumberExample.word(input: 'Saturday', value: '星期六', category: NumberCategory.date, hint: '星期六：Sat.，英 /ˈsætədeɪ/、美 /ˈsætərdeɪ/'),
    NumberExample.word(input: 'Sunday', value: '星期日', category: NumberCategory.date, hint: '星期日：Sun.，/ˈsʌndeɪ/，英美日历里是一周的第一天'),

    NumberExample.pattern(
      input: '英美写法不同',
      category: NumberCategory.date,
      hint: '纯数字写法英美顺序相反：03/05/2026 英式 = 3 May，美式 = March 5 —— 写月份名或用 ISO 2026-03-05 最保险。',
      samples: ['2026-03-05', '2026-05-03'],
    ),
    NumberExample.pattern(
      input: '星期与介词',
      category: NumberCategory.date,
      hint: '星期用 on（on Monday）、具体某天用 on（on the 8th of October）、月份年份用 in（in October、in 2026）。',
      samples: ['on Monday', 'on Friday'],
    ),
    NumberExample.pattern(
      input: '世纪与年代',
      category: NumberCategory.date,
      hint: '世纪用序数词：the 21st century = the twenty-first century；年代用整十复数：in the nineties、in the 1980s。',
      samples: ['1990s', '2000s'],
    ),

    // ------------------------------------------------------------ saying zero
    NumberExample(input: '0', category: NumberCategory.zero, hint: '单独的数字：zero', zeroContext: 'plain'),
    NumberExample(input: '0（电话）', category: NumberCategory.zero, hint: '号码里的 0：oh', zeroContext: 'phone'),
    NumberExample(input: '0.5', category: NumberCategory.zero, hint: '英 nought / 美 zero', zeroContext: 'decimal'),
    NumberExample(input: '3-0', category: NumberCategory.zero, hint: '比分：英 three nil', zeroContext: 'score'),
    NumberExample(input: '40-0', category: NumberCategory.zero, hint: '网球：forty love', zeroContext: 'tennis'),
    NumberExample(input: '0°C', category: NumberCategory.zero, hint: '温度：zero degrees', zeroContext: 'temperature'),
    NumberExample.pattern(
      input: '五套读法',
      category: NumberCategory.zero,
      hint: 'zero（单独/科学/温度）、nought（英式小数）、oh（号码/编号）、nil（英式比分）、nothing（美式比分）、love（网球）——按场景选。',
      samples: ['0', '0.5', '0.05'],
    ),
  ];

  static List<NumberExample> getByCategory(NumberCategory category) =>
      allExamples.where((example) => example.category == category).toList();

  /// The vocabulary cards: every word the module teaches one by one.
  static List<NumberExample> get wordCards =>
      allExamples.where((example) => example.kind == NumberCardKind.word).toList();

  /// The rule cards, each standing in for a whole regular range.
  static List<NumberExample> get patternCards =>
      allExamples.where((example) => example.kind == NumberCardKind.pattern).toList();

  /// The sentence for one card, in both accents.
  ///
  /// A word card is spoken as the word itself — that is what the card teaches,
  /// and the recording of exactly that word is what the module ships. A pattern
  /// card has no single sentence: it teaches a rule, so it returns null and the
  /// UI shows the rule plus its samples.
  static NumberReading? readingOf(NumberExample example) {
    switch (example.kind) {
      case NumberCardKind.pattern:
        return null;
      case NumberCardKind.word:
        return NumberReading(
          input: example.value ?? example.input,
          ukText: example.input,
          usText: example.input,
          note: example.hint,
          category: example.category,
        );
      case NumberCardKind.number:
        return example.zeroContext != null
            ? NumberSpeller.zeroReading(example.zeroContext!)
            : NumberSpeller.read(example.input, as: example.as);
    }
  }

  /// How one sample of a pattern card is spoken: a written number through the
  /// speller, a word (`twenty-one`, `ninety-ninth`) as its own word.
  static NumberReading sampleReading(NumberExample card, String sample) {
    // The sample's own format decides how it is read (`0.5` in the zero card is
    // still a decimal); anything unparseable — `on Monday`, `twenty-first` — is
    // spoken as words. The speller answers those with *empty* text, not null.
    final numeric = NumberSpeller.read(sample);
    if (numeric != null && numeric.ukText.isNotEmpty) return numeric;
    return NumberReading(
      input: sample,
      ukText: sample,
      usText: sample,
      note: '',
      category: card.category,
    );
  }
}
