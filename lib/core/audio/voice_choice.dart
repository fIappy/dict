/// Which engine a voice belongs to.
///
/// Windows ships two generations of speech voices: the modern OneCore / "Mobile"
/// voices (the ones Narrator uses — Mark, Jenny, Aria, Hazel, George…) and the
/// ancient SAPI 5 "Desktop" ones (Zira, David). The modern ones sound noticeably
/// less robotic, so they win whenever both are installed.
///
/// Android and the browser bring exactly one kind each. The order of the values
/// is the preference order, so a host that offers several still picks the best
/// one it has.
enum VoiceEngine {
  oneCore('自然语音', 'Windows 新一代语音（Narrator 用的那一批）'),
  sapi('桌面语音', '旧版 SAPI 桌面语音'),
  androidTts('系统语音', 'Android 系统语音合成（android.speech.tts）'),
  browser('浏览器语音', '浏览器内置语音合成（speechSynthesis）');

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

  /// Whether the voice can speak with the network unplugged.
  ///
  /// Android voices say so outright, and browsers distinguish the engine's own
  /// voices from cloud ones ("Google US English" is cloud-backed). The module
  /// prefers an offline voice over a cloud one: a drill that stops mid-number
  /// because the wifi dropped is worse than a slightly wrong timbre.
  final bool offline;

  const SentenceVoice({
    required this.name,
    required this.language,
    required this.engine,
    this.offline = true,
  });

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

/// Picks the voice to speak [accent] with, or null when the host has no English
/// voice at all (then the module plays its recordings instead).
///
/// Passes, best first — inside every pass the engine order decides, so Windows
/// keeps preferring its modern OneCore voices:
///   1. the accent's own language, offline;
///   2. any English, offline;
///   3. the accent's own language, cloud-backed;
///   4. any English, cloud-backed.
///
/// Offline outranks the accent on purpose: the module has to keep speaking with
/// the network unplugged, and landing on a cloud voice (browsers offer several)
/// would go silent in the middle of a drill. A wrong timbre merely sounds off.
///
/// Falling back to the other accent keeps the *wording* right ("one hundred and
/// twenty-three" vs "one hundred twenty-three"); the UI says so by showing which
/// voice is in use.
SentenceVoice? chooseSentenceVoice(List<SentenceVoice> voices, String accent) {
  final wanted = accent == 'uk' ? 'en-GB' : 'en-US';

  final passes = <bool Function(SentenceVoice)>[
    (v) => v.offline && v.language.equalsIgnoreCase(wanted),
    (v) => v.offline && v.isEnglish,
    (v) => v.language.equalsIgnoreCase(wanted),
    (v) => v.isEnglish,
  ];

  for (final pass in passes) {
    for (final engine in VoiceEngine.values) {
      for (final voice in voices) {
        if (voice.engine == engine && pass(voice)) return voice;
      }
    }
  }
  return null;
}

/// The text a speech engine should read for [text].
///
/// Engines take their sentence prosody from punctuation, so a bare phrase gets a
/// capital and a full stop even though the card shows it without them.
String sentenceForSpeech(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return trimmed;
  final capitalised =
      trimmed[0].toUpperCase() + (trimmed.length > 1 ? trimmed.substring(1) : '');
  return RegExp(r'[.!?]$').hasMatch(capitalised) ? capitalised : '$capitalised.';
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
  if (!voice.offline) {
    buffer.write('；这条语音要联网');
  }
  if (voice.engine == VoiceEngine.sapi) {
    buffer.write('；想更自然：设置 → 时间和语言 → 语音 → 管理语音 → 添加语音（English）');
  }
  return buffer.toString();
}

extension on String {
  bool equalsIgnoreCase(String other) => toLowerCase() == other.toLowerCase();
}
