/// Which engine reads text aloud.
///
/// One switch for the whole app — the dictionary, the AI cards, the custom
/// passages and the number drill all read through it, which is why it lives in
/// the settings panel rather than inside one module.
enum SpeechEngine {
  kokoro(
    'Kokoro',
    '本机神经语音：三端同一音色，完全离线；每句要合成几百毫秒',
  ),
  system(
    '系统语音',
    '操作系统自带的语音合成：点下即读，音色随机器的语音包而变',
  );

  const SpeechEngine(this.label, this.hint);

  final String label;
  final String hint;

  static SpeechEngine byName(String? name) => values.firstWhere(
        (engine) => engine.name == name,
        orElse: () => SpeechEngine.kokoro,
      );
}
