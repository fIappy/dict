enum IpaCategory {
  monophthong('单元音', 'Monophthongs'),
  diphthong('双元音', 'Diphthongs'),
  plosive('爆破音', 'Plosives'),
  fricative('摩擦音', 'Fricatives'),
  affricate('破擦音', 'Affricates'),
  nasal('鼻音', 'Nasals'),
  approximant('近音/流音', 'Approximants');

  final String labelZh;
  final String labelEn;
  const IpaCategory(this.labelZh, this.labelEn);
}

enum IpaAccent {
  both('英美通用', 'UK & US', '🌐'),
  ukOnly('英音专有', 'UK Only', '🇬🇧'),
  usOnly('美音专有', 'US Only', '🇺🇸');

  final String labelZh;
  final String labelEn;
  final String icon;
  const IpaAccent(this.labelZh, this.labelEn, this.icon);
}

class IpaExampleWord {
  final String word;
  final String ukPhonetic;
  final String usPhonetic;
  final String spellingPattern; // e.g. "ee", "ea"
  final String? meaning;

  /// Backward-compatible getter returning UK phonetic by default or US.
  String get phonetic => ukPhonetic.isNotEmpty ? ukPhonetic : usPhonetic;

  const IpaExampleWord({
    required this.word,
    String? phonetic,
    String? ukPhonetic,
    String? usPhonetic,
    required this.spellingPattern,
    this.meaning,
  })  : ukPhonetic = ukPhonetic ?? phonetic ?? '',
        usPhonetic = usPhonetic ?? phonetic ?? '';
}

class IpaCombination {
  final String formula; // e.g. "/p/ + /iː/ → /piː/"
  final String category; // e.g. "声母拼读", "辅音连缀", "尾音闭合", "浊化/连音"
  final String explanation;
  final List<IpaExampleWord> words;

  const IpaCombination({
    required this.formula,
    required this.category,
    required this.explanation,
    required this.words,
  });
}

class IpaPhoneme {
  final String symbol; // e.g. "/iː/"
  final String rawSymbol; // e.g. "iː"
  final IpaCategory category;
  final String subCategory; // e.g. "前元音 · 长元音"
  final String voiceType; // e.g. "浊音", "清辅音", "浊辅音"
  final String audioAssetKey; // 音标本身的发音音频资源键
  final IpaAccent accent; // 🇬🇧 英音标准, 🇺🇸 美音标准, 或 🌐 英美通用
  final String cambridgeExampleWord; // 剑桥基准代表例词 (e.g. "sheep", "ship", "sock", "bird", "cutting")
  final String cambridgeUkPhonetic; // 剑桥例词英音音标
  final String cambridgeUsPhonetic; // 剑桥例词美音音标
  final String? counterpartSymbol; // 对应方言音标 (如 /ɒ/ 对应美音 /ɑː/ 或 /ɔː/)
  final String? counterpartExplanation; // 英美对应发音差异说明与规则指导
  final String description; // 发音要领与技巧
  final String mouthShape; // 唇形与舌位
  final List<String> commonSpellings; // 常见字母组合
  final List<IpaExampleWord> examples;
  final List<IpaCombination> combinations;

  const IpaPhoneme({
    required this.symbol,
    required this.rawSymbol,
    required this.category,
    required this.subCategory,
    required this.voiceType,
    required this.audioAssetKey,
    this.accent = IpaAccent.both,
    this.cambridgeExampleWord = '',
    this.cambridgeUkPhonetic = '',
    this.cambridgeUsPhonetic = '',
    this.counterpartSymbol,
    this.counterpartExplanation,
    required this.description,
    required this.mouthShape,
    this.commonSpellings = const [],
    this.examples = const [],
    this.combinations = const [],
  });

  /// Bare IPA of [counterpartSymbol]: '/ɑː/ (美音)' -> '/ɑː/'.
  ///
  /// Used to find the phoneme entry that carries the other accent's clip, so a
  /// UK-only row's US button plays a real recording instead of nothing.
  String? get counterpartIpa {
    final match = RegExp(r'/[^/]+/').firstMatch(counterpartSymbol ?? '');
    return match?.group(0);
  }
}
