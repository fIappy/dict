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

class IpaExampleWord {
  final String word;
  final String phonetic;
  final String spellingPattern; // e.g. "ee", "ea"
  final String? meaning;

  const IpaExampleWord({
    required this.word,
    required this.phonetic,
    required this.spellingPattern,
    this.meaning,
  });
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
  final String description; // 发音要领
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
    required this.description,
    required this.mouthShape,
    this.commonSpellings = const [],
    this.examples = const [],
    this.combinations = const [],
  });
}
