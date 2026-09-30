import 'dart:convert';
import 'package:flutter/services.dart';

class WordFrequencyInfo {
  final String word;
  final int? rank;
  final String? cefr;
  final int? collins;
  final List<String> examTags;
  final String? briefZh;

  const WordFrequencyInfo({
    required this.word,
    this.rank,
    this.cefr,
    this.collins,
    this.examTags = const [],
    this.briefZh,
  });

  String get frequencyLabel {
    if (rank == null) return '低频';
    if (rank! <= 1000) return 'Top 1000';
    if (rank! <= 2500) return 'Top 2500';
    if (rank! <= 5000) return 'Top 5000';
    if (rank! <= 10000) return 'Top 10000';
    if (rank! <= 20000) return 'Top 20000';
    return 'COCA #$rank';
  }

  String get collinsStars {
    final c = collins ?? (rank != null && rank! <= 2000 ? 5 : (rank != null && rank! <= 5000 ? 4 : (rank != null && rank! <= 10000 ? 3 : 2)));
    return '★' * c + '☆' * (5 - c);
  }

  bool get isHighFrequency => rank != null && rank! <= 5000;
}

class FrequencyService {
  static final FrequencyService _instance = FrequencyService._();
  factory FrequencyService() => _instance;
  FrequencyService._();

  final Map<String, WordFrequencyInfo> _freqMap = {};
  final List<String> _rankedWords = [];
  final Map<String, int> _wordToRank = {};
  bool _initialized = false;

  List<String> get rankedWords => List.unmodifiable(_rankedWords);
  int get totalRankedWords => _rankedWords.length;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    _loadBuiltInLexicon();
    await _loadRankedWordsAsset();
  }

  Future<void> _loadRankedWordsAsset() async {
    try {
      final jsonStr = await rootBundle.loadString('assets/data/frequency_5000.json');
      final list = (json.decode(jsonStr) as List).cast<String>();
      _rankedWords.clear();
      _wordToRank.clear();
      for (int i = 0; i < list.length; i++) {
        final w = list[i].toLowerCase();
        final rank = i + 1;
        _rankedWords.add(w);
        _wordToRank[w] = rank;
        if (_freqMap.containsKey(w)) {
          final old = _freqMap[w]!;
          _freqMap[w] = WordFrequencyInfo(
            word: old.word,
            rank: rank,
            cefr: old.cefr,
            collins: old.collins,
            examTags: old.examTags,
            briefZh: old.briefZh,
          );
        }
      }
    } catch (_) {
      _loadFallbackRanked();
    }
  }
  void _loadFallbackRanked() {
    if (_rankedWords.isNotEmpty) return;
    final sorted = _freqMap.values.toList()
      ..sort((a, b) => (a.rank ?? 9999).compareTo(b.rank ?? 9999));
    for (int i = 0; i < sorted.length; i++) {
      final w = sorted[i].word.toLowerCase();
      _rankedWords.add(w);
      _wordToRank[w] = i + 1;
    }
  }

  WordFrequencyInfo? getFrequency(String word) {
    if (!_initialized) {
      _loadBuiltInLexicon();
      _loadFallbackRanked();
    }
    final lower = word.trim().toLowerCase();
    if (_freqMap.containsKey(lower)) {
      return _freqMap[lower];
    }

    if (_wordToRank.containsKey(lower)) {
      return _synthesizeFrequencyInfo(lower, _wordToRank[lower]!);
    }

    // Try stem or basic singular
    if (lower.endsWith('s') && _freqMap.containsKey(lower.substring(0, lower.length - 1))) {
      return _freqMap[lower.substring(0, lower.length - 1)];
    }
    if (lower.endsWith('es') && _freqMap.containsKey(lower.substring(0, lower.length - 2))) {
      return _freqMap[lower.substring(0, lower.length - 2)];
    }
    if (lower.endsWith('ed') && _freqMap.containsKey(lower.substring(0, lower.length - 2))) {
      return _freqMap[lower.substring(0, lower.length - 2)];
    }
    if (lower.endsWith('ing') && _freqMap.containsKey(lower.substring(0, lower.length - 3))) {
      return _freqMap[lower.substring(0, lower.length - 3)];
    }

    return null;
  }

  List<WordFrequencyInfo> getWordsByRange(int startRank, int endRank) {
    if (_rankedWords.isEmpty) {
      _loadFallbackRanked();
    }
    if (_rankedWords.isEmpty) return const [];

    final start = startRank.clamp(1, _rankedWords.length);
    final end = endRank.clamp(start, _rankedWords.length);
    final result = <WordFrequencyInfo>[];

    for (int r = start; r <= end; r++) {
      final w = _rankedWords[r - 1];
      final existing = _freqMap[w];
      final synth = _synthesizeFrequencyInfo(w, r);
      final info = WordFrequencyInfo(
        word: w,
        rank: r, // Strictly guaranteed monotonic sequence matching row position
        cefr: existing?.cefr ?? synth.cefr,
        collins: existing?.collins ?? synth.collins,
        examTags: (existing != null && existing.examTags.isNotEmpty)
            ? existing.examTags
            : synth.examTags,
        briefZh: existing?.briefZh,
      );
      result.add(info);
    }
    return result;
  }
  WordFrequencyInfo _synthesizeFrequencyInfo(String word, int rank) {
    final String cefr;
    if (rank <= 600) {
      cefr = 'A1';
    } else if (rank <= 1500) {
      cefr = 'A2';
    } else if (rank <= 3000) {
      cefr = 'B1';
    } else if (rank <= 5500) {
      cefr = 'B2';
    } else if (rank <= 10000) {
      cefr = 'C1';
    } else {
      cefr = 'C2';
    }

    final int collins;
    if (rank <= 1000) {
      collins = 5;
    } else if (rank <= 2500) {
      collins = 4;
    } else if (rank <= 5500) {
      collins = 3;
    } else if (rank <= 10000) {
      collins = 2;
    } else {
      collins = 1;
    }

    final List<String> tags;
    if (rank <= 1500) {
      tags = const ['初中', '高中', 'CET4'];
    } else if (rank <= 3500) {
      tags = const ['高中', 'CET4', 'CET6', 'IELTS'];
    } else if (rank <= 6000) {
      tags = const ['CET6', '考研', 'IELTS', 'TOEFL'];
    } else if (rank <= 12000) {
      tags = const ['考研', 'GRE', 'TOEFL'];
    } else {
      tags = const ['GRE', 'SAT', '高级'];
    }
    return WordFrequencyInfo(
      word: word,
      rank: rank,
      cefr: cefr,
      collins: collins,
      examTags: tags,
      briefZh: _freqMap[word]?.briefZh,
    );
  }

  void _loadBuiltInLexicon() {
    const rawData = [
      ["the", 1, "A1", 5, ["初中", "高中", "CET4"], "art. 这; 那; 这些; 那些"],
      ["be", 2, "A1", 5, ["初中", "高中", "CET4"], "v. 是; 有; 存在"],
      ["and", 3, "A1", 5, ["初中", "高中", "CET4"], "conj. 和; 与; 而且"],
      ["of", 4, "A1", 5, ["初中", "高中", "CET4"], "prep. 的; 关于; 由...制成"],
      ["a", 5, "A1", 5, ["初中", "高中", "CET4"], "art. 一个; 一件; 任何一个"],
      ["in", 6, "A1", 5, ["初中", "高中", "CET4"], "prep. 在...里; 在...期间"],
      ["to", 7, "A1", 5, ["初中", "高中", "CET4"], "prep. 向; 到; 给; 对"],
      ["have", 8, "A1", 5, ["初中", "高中", "CET4"], "v. 有; 拥有; 经历"],
      ["it", 9, "A1", 5, ["初中", "高中", "CET4"], "pron. 它; 这; 那"],
      ["i", 10, "A1", 5, ["初中", "高中", "CET4"], "pron. 我"],
      ["that", 11, "A1", 5, ["初中", "高中", "CET4"], "pron./conj. 那个; 那些; 引导从句"],
      ["for", 12, "A1", 5, ["初中", "高中", "CET4"], "prep. 为了; 给; 代表"],
      ["you", 13, "A1", 5, ["初中", "高中", "CET4"], "pron. 你; 你们"],
      ["he", 14, "A1", 5, ["初中", "高中", "CET4"], "pron. 他"],
      ["with", 15, "A1", 5, ["初中", "高中", "CET4"], "prep. 和...一起; 具有; 用"],
      ["on", 16, "A1", 5, ["初中", "高中", "CET4"], "prep. 在...上面; 关于"],
      ["do", 17, "A1", 5, ["初中", "高中", "CET4"], "v. 做; 干; 进行"],
      ["say", 18, "A1", 5, ["初中", "高中", "CET4"], "v. 说; 讲; 表明"],
      ["this", 19, "A1", 5, ["初中", "高中", "CET4"], "pron. 这个; 这件事"],
      ["they", 20, "A1", 5, ["初中", "高中", "CET4"], "pron. 他们; 她们; 它们"],
      ["at", 21, "A1", 5, ["初中", "高中", "CET4"], "prep. 在...点; 在...处"],
      ["but", 22, "A1", 5, ["初中", "高中", "CET4"], "conj. 但是; 然而"],
      ["we", 23, "A1", 5, ["初中", "高中", "CET4"], "pron. 我们"],
      ["his", 24, "A1", 5, ["初中", "高中", "CET4"], "pron. 他的"],
      ["from", 25, "A1", 5, ["初中", "高中", "CET4"], "prep. 来自; 从...起"],
      ["not", 27, "A1", 5, ["初中", "高中", "CET4"], "adv. 不; 没有"],
      ["by", 28, "A1", 5, ["初中", "高中", "CET4"], "prep. 通过; 被; 在...旁"],
      ["she", 29, "A1", 5, ["初中", "高中", "CET4"], "pron. 她"],
      ["or", 30, "A1", 5, ["初中", "高中", "CET4"], "conj. 或者; 还是"],
      ["as", 31, "A1", 5, ["初中", "高中", "CET4"], "prep./conj. 作为; 如同; 因为"],
      ["what", 32, "A1", 5, ["初中", "高中", "CET4"], "pron. 什么; ...的事物"],
      ["go", 33, "A1", 5, ["初中", "高中", "CET4"], "v. 去; 走; 进行"],
      ["their", 34, "A1", 5, ["初中", "高中", "CET4"], "pron. 他们的"],
      ["can", 35, "A1", 5, ["初中", "高中", "CET4"], "modal. 能; 可以; 会"],
      ["who", 36, "A1", 5, ["初中", "高中", "CET4"], "pron. 谁; ...的人"],
      ["get", 37, "A1", 5, ["初中", "高中", "CET4"], "v. 得到; 获得; 变成"],
      ["if", 38, "A1", 5, ["初中", "高中", "CET4"], "conj. 如果; 是否"],
      ["would", 39, "A1", 5, ["初中", "高中", "CET4"], "modal. 将要; 愿意; 总是"],
      ["her", 40, "A1", 5, ["初中", "高中", "CET4"], "pron. 她的; 她"],
      ["all", 41, "A1", 5, ["初中", "高中", "CET4"], "det./pron. 全部; 所有"],
      ["my", 42, "A1", 5, ["初中", "高中", "CET4"], "pron. 我的"],
      ["make", 43, "A1", 5, ["初中", "高中", "CET4"], "v. 制作; 使成为; 造成"],
      ["about", 44, "A1", 5, ["初中", "高中", "CET4"], "prep./adv. 关于; 大约"],
      ["know", 45, "A1", 5, ["初中", "高中", "CET4"], "v. 知道; 了解; 认识"],
      ["will", 46, "A1", 5, ["初中", "高中", "CET4"], "modal/n. 将; 愿意; 意志"],
      ["up", 48, "A1", 5, ["初中", "高中", "CET4"], "adv./prep. 向上; 起来"],
      ["one", 49, "A1", 5, ["初中", "高中", "CET4"], "num./pron. 一; 某个人或物"],
      ["time", 50, "A1", 5, ["初中", "高中", "CET4"], "n. 时间; 次数; 时代"],

      // Frequently looked up words, academic & test vocabulary
      ["abandon", 2862, "B2", 4, ["CET4", "CET6", "IELTS", "TOEFL", "GRE", "考研"], "v. 放弃; 抛弃; 遗弃"],
      ["abundant", 4210, "B2", 3, ["CET4", "CET6", "IELTS", "TOEFL", "考研"], "adj. 丰富的; 充裕的; 盛产的"],
      ["academic", 1120, "B1", 4, ["CET4", "CET6", "IELTS", "TOEFL", "考研"], "adj. 学术的; 学院的 n. 学者"],
      ["accelerate", 3980, "B2", 3, ["CET4", "CET6", "IELTS", "TOEFL", "GRE", "考研"], "v. 加速; 促进; 增加"],
      ["accept", 412, "A2", 5, ["初中", "高中", "CET4", "IELTS"], "v. 接受; 同意; 认可"],
      ["access", 780, "B1", 4, ["高中", "CET4", "CET6", "IELTS", "TOEFL", "考研"], "n./v. 入口; 通道; 存取; 获得"],
      ["accommodate", 3410, "B2", 3, ["CET4", "CET6", "IELTS", "TOEFL", "考研"], "v. 容纳; 提供住宿; 适应"],
      ["accommodation", 4850, "B1", 3, ["CET4", "CET6", "IELTS"], "n. 住处; 膳宿; 调节"],
      ["accompany", 2310, "B2", 4, ["高中", "CET4", "CET6", "IELTS", "考研"], "v. 陪伴; 伴随; 伴奏"],
      ["accomplish", 2650, "B2", 4, ["高中", "CET4", "CET6", "IELTS", "TOEFL", "考研"], "v. 完成; 实现; 达到"],
      ["accurate", 2150, "B2", 4, ["高中", "CET4", "CET6", "IELTS", "TOEFL", "考研"], "adj. 精确的; 准确无误的"],
      ["achieve", 650, "A2", 5, ["初中", "高中", "CET4", "IELTS", "TOEFL"], "v. 取得; 获得; 实现"],
      ["acknowledge", 2120, "B2", 4, ["CET4", "CET6", "IELTS", "TOEFL", "GRE", "考研"], "v. 承认; 确认; 致谢"],
      ["acquire", 1430, "B2", 4, ["高中", "CET4", "CET6", "IELTS", "TOEFL", "考研"], "v. 获得; 购得; 学到"],
      ["adapt", 2430, "B2", 4, ["高中", "CET4", "CET6", "IELTS", "TOEFL", "考研"], "v. 适应; 改编; 调整"],
      ["adequate", 2390, "B2", 4, ["CET4", "CET6", "IELTS", "TOEFL", "考研"], "adj. 充足的; 适当的; 胜任的"],
      ["adjust", 1820, "B2", 4, ["高中", "CET4", "CET6", "IELTS", "TOEFL", "考研"], "v. 调整; 适应; 校准"],
      ["admire", 3210, "B1", 3, ["初中", "高中", "CET4", "IELTS"], "v. 钦佩; 赞美; 仰慕"],
      ["adopt", 1250, "B2", 4, ["高中", "CET4", "CET6", "IELTS", "TOEFL", "考研"], "v. 采纳; 收养; 采用"],
      ["advance", 1150, "B1", 4, ["初中", "高中", "CET4", "CET6", "IELTS"], "v./n. 前进; 进展; 预先"],
      ["advantage", 920, "A2", 5, ["初中", "高中", "CET4", "IELTS"], "n. 优势; 有利条件; 利益"],
      ["advocate", 2280, "C1", 4, ["CET4", "CET6", "IELTS", "TOEFL", "GRE", "考研"], "v. 提倡; 主张 n. 拥护者; 辩护律师"],
      ["aesthetic", 4650, "C1", 3, ["CET6", "IELTS", "TOEFL", "GRE", "考研"], "adj. 美学的; 审美的 n. 美感"],
      ["affect", 790, "A2", 5, ["初中", "高中", "CET4", "IELTS"], "v. 影响; 感动; 侵袭"],
      ["afford", 1310, "B1", 4, ["初中", "高中", "CET4", "IELTS"], "v. 买得起; 承担得起; 提供"],
      ["aggressive", 2350, "B2", 4, ["高中", "CET4", "CET6", "IELTS", "TOEFL", "考研"], "adj. 侵略性的; 咄咄逼人的; 进取的"],
      ["allocate", 4120, "B2", 3, ["CET4", "CET6", "IELTS", "TOEFL", "考研"], "v. 分配; 配给; 拨出"],
      ["alternative", 1290, "B1", 4, ["高中", "CET4", "CET6", "IELTS", "TOEFL", "考研"], "adj. 可供选择的 n. 可替代方案"],
      ["ambiguous", 5620, "C1", 3, ["CET6", "IELTS", "TOEFL", "GRE", "考研"], "adj. 模棱两可的; 含糊不清的"],
      ["ambition", 3280, "B1", 3, ["高中", "CET4", "CET6", "IELTS"], "n. 野心; 雄心; 抱负"],
      ["analyze", 1480, "B1", 4, ["高中", "CET4", "CET6", "IELTS", "TOEFL", "考研"], "v. 分析; 解析"],
      ["ancient", 1540, "A2", 4, ["初中", "高中", "CET4", "IELTS"], "adj. 古代的; 古老的; 远古的"],
      ["annual", 1280, "B1", 4, ["高中", "CET4", "CET6", "IELTS", "TOEFL", "考研"], "adj. 每年的; 年度的 n. 年刊"],
      ["anticipate", 2530, "B2", 4, ["CET4", "CET6", "IELTS", "TOEFL", "考研"], "v. 预期; 期望; 预见"],
      ["apparent", 1880, "B2", 4, ["高中", "CET4", "CET6", "IELTS", "TOEFL", "考研"], "adj. 明显的; 显而易见的; 表面上的"],
      ["appeal", 1210, "B2", 4, ["高中", "CET4", "CET6", "IELTS", "TOEFL", "考研"], "v./n. 呼吁; 上诉; 吸引力"],
      ["approach", 680, "B1", 5, ["高中", "CET4", "CET6", "IELTS", "TOEFL", "考研"], "v./n. 接近; 靠近; 方法; 途径"],
      ["appropriate", 1350, "B2", 4, ["高中", "CET4", "CET6", "IELTS", "TOEFL", "考研"], "adj. 恰当的; 合适的 v. 拨出; 占用"],
      ["approximate", 4180, "B2", 3, ["高中", "CET4", "CET6", "IELTS", "TOEFL", "考研"], "adj. 近似的; 大约的 v. 接近"],
      ["arbitrary", 5420, "C1", 3, ["CET6", "IELTS", "TOEFL", "GRE", "考研"], "adj. 任意的; 专断的; 武断的"],
      ["architecture", 2320, "B1", 4, ["高中", "CET4", "CET6", "IELTS", "TOEFL"], "n. 建筑学; 建筑风格; 结构架构"],
      ["artificial", 3210, "B2", 3, ["初中", "高中", "CET4", "IELTS", "TOEFL"], "adj. 人造的; 虚伪的; 假装的"],
      ["aspect", 1160, "B2", 4, ["高中", "CET4", "CET6", "IELTS", "TOEFL", "考研"], "n. 方面; 朝向; 面貌"],
      ["assert", 3890, "C1", 3, ["CET4", "CET6", "IELTS", "TOEFL", "GRE", "考研"], "v. 断言; 宣称; 维护"],
      ["assess", 1680, "B2", 4, ["CET4", "CET6", "IELTS", "TOEFL", "考研"], "v. 评估; 评价; 估价"],
      ["associate", 1190, "B2", 4, ["高中", "CET4", "CET6", "IELTS", "TOEFL", "考研"], "v. 联合; 联系; 结交 n. 伙伴"],
      ["assume", 980, "B2", 5, ["高中", "CET4", "CET6", "IELTS", "TOEFL", "考研"], "v. 假设; 假定; 承担; 呈现"],
      ["attitude", 1100, "B1", 4, ["初中", "高中", "CET4", "IELTS", "TOEFL"], "n. 态度; 看法; 姿势"],
      ["attribute", 2980, "B2", 4, ["CET4", "CET6", "IELTS", "TOEFL", "GRE", "考研"], "v. 归因于 n. 属性; 特质"],
      ["authentic", 4320, "B2", 3, ["CET6", "IELTS", "TOEFL", "GRE", "考研"], "adj. 真正的; 真实的; 可信的"],
      ["authority", 910, "B2", 5, ["高中", "CET4", "CET6", "IELTS", "TOEFL", "考研"], "n. 权威; 权力; 当局"],
      ["available", 590, "A2", 5, ["高中", "CET4", "CET6", "IELTS", "TOEFL"], "adj. 可获得的; 有空的; 可用的"],
      ["benefit", 720, "B1", 5, ["初中", "高中", "CET4", "CET6", "IELTS", "TOEFL"], "n. 益处; 救济金 v. 受益; 得益"],
      ["bias", 3950, "B2", 3, ["CET6", "IELTS", "TOEFL", "GRE", "考研"], "n. 偏见; 偏爱 v. 使有偏见"],
      ["category", 1750, "B1", 4, ["高中", "CET4", "CET6", "IELTS", "TOEFL", "考研"], "n. 种类; 分类; 范畴"],
      ["challenge", 820, "B1", 5, ["初中", "高中", "CET4", "CET6", "IELTS", "TOEFL"], "n./v. 挑战; 质疑; 难题"],
      ["circumstance", 2210, "B2", 4, ["高中", "CET4", "CET6", "IELTS", "TOEFL", "考研"], "n. 环境; 情况; 境遇"],
      ["clarify", 3760, "B2", 3, ["CET4", "CET6", "IELTS", "TOEFL", "考研"], "v. 阐明; 澄清; 使清楚"],
      ["collaborate", 4520, "B2", 3, ["CET6", "IELTS", "TOEFL", "考研"], "v. 合作; 协作; 通敌"],
      ["community", 380, "A2", 5, ["初中", "高中", "CET4", "CET6", "IELTS"], "n. 社区; 群体; 共同体"],
      ["complex", 1090, "B1", 4, ["初中", "高中", "CET4", "CET6", "IELTS", "TOEFL"], "adj. 复杂的; 复合的 n. 复合体"],
      ["comprehend", 5210, "B2", 3, ["CET4", "CET6", "IELTS", "TOEFL", "考研"], "v. 理解; 领会; 包含"],
      ["computer", 450, "A1", 5, ["初中", "高中", "CET4", "IELTS"], "n. 计算机; 电脑"],
      ["concept", 1270, "B2", 4, ["高中", "CET4", "CET6", "IELTS", "TOEFL", "考研"], "n. 概念; 观念; 设想"],
      ["conclude", 1890, "B1", 4, ["初中", "高中", "CET4", "CET6", "IELTS", "考研"], "v. 总结; 推断; 结束"],
      ["consistent", 2040, "B2", 4, ["高中", "CET4", "CET6", "IELTS", "TOEFL", "考研"], "adj. 一致的; 连贯的; 坚持的"],
      ["contemporary", 2180, "B2", 4, ["CET4", "CET6", "IELTS", "TOEFL", "GRE", "考研"], "adj. 当代的; 同时代的 n. 同代人"],
      ["crucial", 2090, "B2", 4, ["CET4", "CET6", "IELTS", "TOEFL", "GRE", "考研"], "adj. 至关重要的; 关键的"],
      ["data", 420, "A2", 5, ["初中", "高中", "CET4", "IELTS", "TOEFL"], "n. 数据; 资料"],
      ["demonstrate", 1230, "B2", 4, ["高中", "CET4", "CET6", "IELTS", "TOEFL", "考研"], "v. 证明; 示范; 示威"],
      ["derive", 2930, "B2", 4, ["CET4", "CET6", "IELTS", "TOEFL", "GRE", "考研"], "v. 源于; 获得; 衍生"],
      ["determine", 1010, "B1", 5, ["初中", "高中", "CET4", "CET6", "IELTS", "考研"], "v. 决定; 查明; 测定"],
      ["dictionary", 3120, "A2", 4, ["初中", "高中", "CET4"], "n. 词典; 字典"],
      ["diverse", 2510, "B2", 4, ["CET4", "CET6", "IELTS", "TOEFL", "GRE", "考研"], "adj. 多种多样的; 不同的"],
      ["dominate", 2410, "B2", 4, ["CET4", "CET6", "IELTS", "TOEFL", "考研"], "v. 支配; 占优势; 俯视"],
      ["economy", 530, "B1", 5, ["初中", "高中", "CET4", "CET6", "IELTS", "TOEFL"], "n. 经济; 节约"],
      ["efficient", 2140, "B1", 4, ["高中", "CET4", "CET6", "IELTS", "TOEFL", "考研"], "adj. 高效的; 有能力的"],
      ["elaborate", 3910, "C1", 3, ["CET6", "IELTS", "TOEFL", "GRE", "考研"], "adj. 精心制作的; 详尽的 v. 详述"],
      ["environment", 410, "A2", 5, ["初中", "高中", "CET4", "IELTS", "TOEFL"], "n. 环境; 自然环境; 周围状况"],
      ["establish", 740, "B2", 5, ["初中", "高中", "CET4", "CET6", "IELTS", "TOEFL", "考研"], "v. 建立; 确立; 创办"],
      ["estimate", 1360, "B2", 4, ["高中", "CET4", "CET6", "IELTS", "TOEFL", "考研"], "v./n. 估计; 估价; 预算"],
      ["evaluate", 2080, "B2", 4, ["高中", "CET4", "CET6", "IELTS", "TOEFL", "考研"], "v. 评价; 估价; 评估"],
      ["evidence", 510, "B1", 5, ["高中", "CET4", "CET6", "IELTS", "TOEFL", "考研"], "n. 证据; 迹象; 证明"],
      ["exceed", 3340, "B2", 3, ["CET4", "CET6", "IELTS", "TOEFL", "考研"], "v. 超过; 超出; 超越"],
      ["facilitate", 3620, "C1", 3, ["CET4", "CET6", "IELTS", "TOEFL", "GRE", "考研"], "v. 促进; 使便利; 推动"],
      ["flexible", 2890, "B2", 4, ["高中", "CET4", "CET6", "IELTS", "TOEFL", "考研"], "adj. 灵活的; 柔韧的; 易弯曲的"],
      ["fluctuate", 6150, "C1", 2, ["CET6", "IELTS", "TOEFL", "GRE", "考研"], "v. 波动; 变动; 动摇"],
      ["fundamental", 1950, "B2", 4, ["高中", "CET4", "CET6", "IELTS", "TOEFL", "考研"], "adj. 基础的; 根本的 n. 基本原则"],
      ["generate", 1320, "B2", 4, ["高中", "CET4", "CET6", "IELTS", "TOEFL", "考研"], "v. 产生; 引起; 发电"],
      ["global", 970, "B1", 5, ["高中", "CET4", "CET6", "IELTS", "TOEFL"], "adj. 全球的; 总体的; 全局的"],
      ["guarantee", 2450, "B2", 4, ["高中", "CET4", "CET6", "IELTS", "TOEFL", "考研"], "v./n. 保证; 担保; 保修单"],
      ["hello", 2500, "A1", 5, ["初中", "高中", "CET4"], "int. 你好; 喂"],
      ["hierarchy", 5120, "C1", 3, ["CET6", "IELTS", "TOEFL", "GRE", "考研"], "n. 等级制度; 阶层; 层级"],
      ["hypothesis", 3870, "B2", 3, ["CET4", "CET6", "IELTS", "TOEFL", "GRE", "考研"], "n. 假设; 假说; 前提"],
      ["identify", 760, "B1", 5, ["高中", "CET4", "CET6", "IELTS", "TOEFL", "考研"], "v. 识别; 鉴别; 认同"],
      ["illustrate", 2620, "B2", 4, ["高中", "CET4", "CET6", "IELTS", "TOEFL", "考研"], "v. 说明; 阐明; 加插图"],
      ["impact", 640, "B1", 5, ["高中", "CET4", "CET6", "IELTS", "TOEFL", "考研"], "n./v. 影响; 冲击; 撞击"],
      ["implement", 1980, "B2", 4, ["CET4", "CET6", "IELTS", "TOEFL", "考研"], "v. 实施; 执行 n. 工具; 器具"],
      ["imply", 2250, "B2", 4, ["高中", "CET4", "CET6", "IELTS", "TOEFL", "考研"], "v. 暗示; 意味着; 必然包含"],
      ["incentive", 3140, "B2", 3, ["CET4", "CET6", "IELTS", "TOEFL", "GRE", "考研"], "n. 激励; 鼓励; 刺激"],
      ["indicate", 840, "B1", 5, ["初中", "高中", "CET4", "CET6", "IELTS", "考研"], "v. 表明; 指示; 显示"],
      ["inevitable", 3450, "B2", 3, ["高中", "CET4", "CET6", "IELTS", "TOEFL", "GRE", "考研"], "adj. 不可避免的; 必然的"],
      ["infrastructure", 2540, "B2", 4, ["CET6", "IELTS", "TOEFL", "考研"], "n. 基础设施; 公共建设"],
      ["initial", 1620, "B2", 4, ["高中", "CET4", "CET6", "IELTS", "TOEFL", "考研"], "adj. 最初的; 首字母的"],
      ["insight", 2260, "B2", 4, ["CET4", "CET6", "IELTS", "TOEFL", "GRE", "考研"], "n. 洞察力; 深刻见解"],
      ["integrate", 2740, "B2", 4, ["CET4", "CET6", "IELTS", "TOEFL", "GRE", "考研"], "v. 整合; 融入; 使一体化"],
      ["interpret", 2380, "B2", 4, ["高中", "CET4", "CET6", "IELTS", "TOEFL", "考研"], "v. 解释; 理解; 口译"],
      ["intervene", 4380, "C1", 3, ["CET6", "IELTS", "TOEFL", "GRE", "考研"], "v. 介入; 干预; 调停"],
      ["investigate", 2170, "B1", 4, ["初中", "高中", "CET4", "CET6", "IELTS", "考研"], "v. 调查; 审查; 探究"],
      ["justify", 2850, "B2", 4, ["高中", "CET4", "CET6", "IELTS", "TOEFL", "考研"], "v. 证明...是正当的; 为...辩护"],
      ["legislation", 1720, "B2", 4, ["CET4", "CET6", "IELTS", "TOEFL", "考研"], "n. 法律; 立法; 法规"],
      ["maintain", 890, "B2", 5, ["初中", "高中", "CET4", "CET6", "IELTS", "考研"], "v. 维持; 保持; 维修; 坚称"],
      ["manipulate", 4610, "C1", 3, ["CET6", "IELTS", "TOEFL", "GRE", "考研"], "v. 操纵; 控制; 熟练操作"],
      ["mechanism", 2310, "B2", 4, ["高中", "CET4", "CET6", "IELTS", "TOEFL", "考研"], "n. 机制; 原理; 机构"],
      ["method", 830, "A2", 5, ["初中", "高中", "CET4", "IELTS", "TOEFL"], "n. 方法; 条理"],
      ["modify", 3050, "B2", 3, ["CET4", "CET6", "IELTS", "TOEFL", "考研"], "v. 修改; 调整; 修饰"],
      ["monitor", 1920, "B2", 4, ["初中", "高中", "CET4", "IELTS", "TOEFL"], "v. 监控; 监视 n. 监视器; 班长"],
      ["neglect", 3790, "B2", 3, ["初中", "高中", "CET4", "CET6", "IELTS", "考研"], "v./n. 忽视; 疏忽; 遗漏"],
      ["nevertheless", 2810, "B2", 4, ["高中", "CET4", "CET6", "IELTS", "TOEFL", "考研"], "adv. 尽管如此; 然而"],
      ["norm", 3910, "B2", 3, ["CET6", "IELTS", "TOEFL", "GRE", "考研"], "n. 规范; 标准; 准则"],
      ["obtain", 1460, "B2", 4, ["高中", "CET4", "CET6", "IELTS", "TOEFL", "考研"], "v. 获得; 赢得; 流行"],
      ["obvious", 1240, "B1", 4, ["初中", "高中", "CET4", "IELTS", "TOEFL"], "adj. 明显的; 显而易见的"],
      ["participate", 1370, "B1", 4, ["高中", "CET4", "CET6", "IELTS", "TOEFL", "考研"], "v. 参加; 参与; 分享"],
      ["perceive", 2670, "B2", 4, ["高中", "CET4", "CET6", "IELTS", "TOEFL", "GRE", "考研"], "v. 感知; 察觉; 认为"],
      ["perspective", 1630, "B2", 4, ["高中", "CET4", "CET6", "IELTS", "TOEFL", "GRE", "考研"], "n. 观点; 视角; 远景; 透视法"],
      ["phenomenon", 2840, "B2", 4, ["高中", "CET4", "CET6", "IELTS", "TOEFL", "GRE", "考研"], "n. 现象; 杰出人才"],
      ["potential", 1020, "B2", 5, ["高中", "CET4", "CET6", "IELTS", "TOEFL", "考研"], "adj. 潜在的; 可能的 n. 潜能; 潜力"],
      ["precise", 3110, "B2", 4, ["高中", "CET4", "CET6", "IELTS", "TOEFL", "考研"], "adj. 精确的; 确切的; 严谨的"],
      ["primary", 960, "B1", 5, ["初中", "高中", "CET4", "IELTS", "TOEFL"], "adj. 首要的; 主要的; 初级的"],
      ["principle", 1180, "B2", 4, ["初中", "高中", "CET4", "CET6", "IELTS", "考研"], "n. 原则; 原理; 道义"],
      ["priority", 1690, "B2", 4, ["高中", "CET4", "CET6", "IELTS", "TOEFL", "考研"], "n. 优先事项; 优先权"],
      ["procedure", 1520, "B2", 4, ["高中", "CET4", "CET6", "IELTS", "TOEFL", "考研"], "n. 程序; 手续; 步骤"],
      ["proportion", 2730, "B2", 4, ["高中", "CET4", "CET6", "IELTS", "TOEFL", "考研"], "n. 比例; 部分; 均衡"],
      ["prospective", 4710, "C1", 3, ["CET6", "IELTS", "TOEFL", "GRE", "考研"], "adj. 未来的; 预期的; 潜在的"],
      ["psychological", 2420, "B2", 4, ["高中", "CET4", "CET6", "IELTS", "TOEFL"], "adj. 心理的; 心理学的"],
      ["radical", 3360, "B2", 3, ["CET4", "CET6", "IELTS", "TOEFL", "GRE", "考研"], "adj. 激进的; 根本的 n. 激进分子"],
      ["random", 2830, "B2", 4, ["高中", "CET4", "CET6", "IELTS", "TOEFL"], "adj. 随机的; 随意的"],
      ["recover", 1380, "B1", 4, ["初中", "高中", "CET4", "IELTS"], "v. 恢复; 康复; 找回"],
      ["regulate", 2960, "B2", 4, ["高中", "CET4", "CET6", "IELTS", "TOEFL", "考研"], "v. 调整; 规定; 控制"],
      ["reinforce", 3740, "B2", 3, ["CET4", "CET6", "IELTS", "TOEFL", "考研"], "v. 加固; 强化; 增援"],
      ["relevant", 1470, "B2", 4, ["高中", "CET4", "CET6", "IELTS", "TOEFL", "考研"], "adj. 相关的; 切题的; 有意义的"],
      ["rely", 1550, "B1", 4, ["初中", "高中", "CET4", "IELTS", "TOEFL"], "v. 依赖; 依靠; 信任"],
      ["require", 470, "B1", 5, ["初中", "高中", "CET4", "IELTS", "TOEFL"], "v. 需要; 要求; 命令"],
      ["research", 430, "A2", 5, ["初中", "高中", "CET4", "IELTS", "TOEFL"], "n./v. 研究; 调查"],
      ["resource", 770, "B1", 5, ["初中", "高中", "CET4", "CET6", "IELTS", "TOEFL"], "n. 资源; 财力; 机智"],
      ["respond", 940, "B1", 5, ["初中", "高中", "CET4", "IELTS", "TOEFL"], "v. 回应; 反应; 作答"],
      ["restrict", 3190, "B2", 3, ["高中", "CET4", "CET6", "IELTS", "TOEFL", "考研"], "v. 限制; 约束; 管制"],
      ["retain", 2490, "B2", 4, ["CET4", "CET6", "IELTS", "TOEFL", "GRE", "考研"], "v. 保持; 保留; 记住"],
      ["reveal", 1060, "B2", 5, ["高中", "CET4", "CET6", "IELTS", "TOEFL", "考研"], "v. 揭露; 展现; 显示"],
      ["revenue", 1810, "B2", 4, ["CET4", "CET6", "IELTS", "TOEFL", "考研"], "n. 财政收入; 税收; 收益"],
      ["significant", 870, "B2", 5, ["高中", "CET4", "CET6", "IELTS", "TOEFL", "考研"], "adj. 重大的; 显著的; 有意义的"],
      ["similar", 690, "A2", 5, ["初中", "高中", "CET4", "IELTS"], "adj. 相似的; 类似的"],
      ["source", 670, "A2", 5, ["初中", "高中", "CET4", "IELTS", "TOEFL"], "n. 来源; 出处; 源头"],
      ["specific", 810, "B1", 5, ["高中", "CET4", "CET6", "IELTS", "TOEFL", "考研"], "adj. 具体的; 特定的; 明确的"],
      ["strategy", 750, "B2", 5, ["高中", "CET4", "CET6", "IELTS", "TOEFL", "考研"], "n. 策略; 战略; 计谋"],
      ["structure", 730, "B1", 5, ["初中", "高中", "CET4", "CET6", "IELTS", "TOEFL"], "n. 结构; 建筑物 v. 构造"],
      ["subsequent", 3250, "B2", 3, ["CET4", "CET6", "IELTS", "TOEFL", "GRE", "考研"], "adj. 随后的; 后来的"],
      ["sufficient", 2690, "B2", 4, ["高中", "CET4", "CET6", "IELTS", "TOEFL", "考研"], "adj. 充分的; 足够的"],
      ["sustain", 2950, "B2", 4, ["CET4", "CET6", "IELTS", "TOEFL", "GRE", "考研"], "v. 维持; 支撑; 遭受"],
      ["theory", 930, "B1", 5, ["初中", "高中", "CET4", "CET6", "IELTS", "TOEFL"], "n. 理论; 学说; 推测"],
      ["transform", 1930, "B2", 4, ["高中", "CET4", "CET6", "IELTS", "TOEFL", "考研"], "v. 改变; 转变; 改造"],
      ["ultimate", 2570, "B2", 4, ["CET4", "CET6", "IELTS", "TOEFL", "GRE", "考研"], "adj. 最终的; 极限的; 根本的"],
      ["undertake", 4230, "B2", 3, ["CET4", "CET6", "IELTS", "TOEFL", "考研"], "v. 承担; 从事; 答应"],
      ["valid", 3010, "B2", 4, ["高中", "CET4", "CET6", "IELTS", "TOEFL", "考研"], "adj. 有效的; 合理的; 正当的"],
      ["vary", 1790, "B2", 4, ["高中", "CET4", "CET6", "IELTS", "TOEFL", "考研"], "v. 改变; 变化; 使多样化"],
      ["virtual", 2640, "B2", 4, ["高中", "CET4", "CET6", "IELTS", "TOEFL"], "adj. 虚拟的; 实质上的"],
      ["visible", 2160, "B1", 4, ["初中", "高中", "CET4", "IELTS"], "adj. 可见的; 明显的; 看得见的"],
      ["voluntary", 4190, "B2", 3, ["高中", "CET4", "CET6", "IELTS", "TOEFL", "考研"], "adj. 自愿的; 志愿的"],
      ["welfare", 2790, "B2", 4, ["高中", "CET4", "CET6", "IELTS", "TOEFL", "考研"], "n. 福利; 幸福; 安宁"],
      ["yield", 3150, "B2", 3, ["CET4", "CET6", "IELTS", "TOEFL", "GRE", "考研"], "v. 出产; 屈服 n. 产量; 收益"],
    ];

    for (final item in rawData) {
      final word = item[0] as String;
      final rank = item[1] as int;
      final cefr = item[2] as String;
      final collins = item[3] as int;
      final tags = (item[4] as List).cast<String>();
      final zh = item[5] as String;

      _freqMap[word.toLowerCase()] = WordFrequencyInfo(
        word: word,
        rank: rank,
        cefr: cefr,
        collins: collins,
        examTags: tags,
        briefZh: zh,
      );
    }
  }
}
