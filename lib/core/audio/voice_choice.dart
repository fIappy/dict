/// Which engine a voice belongs to.
///
/// Windows ships two generations of speech voices: the modern OneCore / "Mobile"
/// voices (the ones Narrator uses — Mark, Jenny, Aria, Hazel, George…) and the
/// ancient SAPI 5 "Desktop" ones (Zira, David). The modern ones sound noticeably
/// less robotic, so they win whenever both are installed.
enum VoiceEngine {
  oneCore('自然语音', 'Windows 新一代语音（Narrator 用的那一批）'),
  sapi('桌面语音', '旧版 SAPI 桌面语音');

  final String labelZh;
  final String hint;
  const VoiceEngine(this.labelZh, this.hint);
}

/// One installed speech voice, as the module sees it.
class SentenceVoice {
  final String name;

  /// BCP-47 tag the platform reports (`en-US`, `en-GB`, `zh-CN`…).
  final String language;

  final VoiceEngine engine;

  const SentenceVoice({required this.name, required this.language, required this.engine});

  bool get isEnglish => language.toLowerCase().startsWith('en');
  bool get isBritish => language.equalsIgnoreCase('en-GB');
  bool get isAmerican => language.equalsIgnoreCase('en-US');

  /// 中文标签用来说明这条语音是哪一种英语。
  String get accentLabel {
    if (isBritish) return '英音';
    if (isAmerican) return '美音';
    final lower = language.toLowerCase();
    if (lower.startsWith('en')) return '英语（$language）';
    return language;
  }

  @override
  String toString() => '$name [$language, ${engine.labelZh}]';
}

/// Picks the voice to speak [accent] with, or null when the machine has no
/// English voice at all (then the module plays its recordings instead).
///
/// Order, best first:
///   1. the requested accent's own language, modern engine before old;
///   2. any English voice, modern engine before old.
///
/// Falling back to the other accent keeps the *wording* right ("one hundred and
/// twenty-three" vs "one hundred twenty-three") while the timbre may differ; the
/// UI says so by showing which voice is in use.
SentenceVoice? chooseSentenceVoice(List<SentenceVoice> voices, String accent) {
  final wanted = accent == 'uk' ? 'en-GB' : 'en-US';

  SentenceVoice? best;
  for (final engine in VoiceEngine.values) {
    for (final voice in voices) {
      if (voice.engine != engine) continue;
      if (voice.language.equalsIgnoreCase(wanted)) return voice;
      if (best == null && voice.isEnglish) best = voice;
    }
  }
  return best;
}

/// The UI label for [voice]: the name, plus a note when it is not the accent the
/// user asked for, plus how to get a better one.
String sentenceVoiceDescription(SentenceVoice voice, String accent) {
  final wanted = accent == 'uk' ? 'en-GB' : 'en-US';
  final matches = voice.language.equalsIgnoreCase(wanted);
  final buffer = StringBuffer('${voice.name}（${voice.engine.labelZh} · ${voice.accentLabel}）');
  if (!matches) {
    buffer.write(' —— 本机没有${accent == 'uk' ? '英音' : '美音'}语音，用词仍是'
        '${accent == 'uk' ? '英式' : '美式'}，只是音色不同');
  }
  if (voice.engine == VoiceEngine.sapi) {
    buffer.write('；想更自然：设置 → 时间和语言 → 语音 → 管理语音 → 添加语音（English）');
  }
  return buffer.toString();
}

extension on String {
  bool equalsIgnoreCase(String other) => toLowerCase() == other.toLowerCase();
}
