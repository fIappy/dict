/// Which engine reads text aloud.
///
/// One switch for the whole app — the dictionary, the AI cards, the custom
/// passages and the number drill all read through it, which is why it lives in
/// the settings panel rather than inside one module.
///
/// The first two run on this machine; the rest fetch the line from a free
/// service that needs no key ([isOnline]). The online ones are ordered by how
/// natural they sound, and the last two answer from inside China, so a blocked
/// route still has a voice.
enum SpeechEngine {
  kokoro(
    'Kokoro',
    '本机神经语音：三端同一音色，完全离线；每句要合成几百毫秒',
  ),
  system(
    '系统语音',
    '操作系统自带的语音合成：点下即读，音色随机器的语音包而变',
  ),
  edge(
    'Edge 神经语音',
    '微软 Edge 的朗读音色：免费、无需密钥，最接近真人；语速由服务端合成，'
        '不会变调；需联网（境外）',
  ),
  google(
    'Google 语音',
    'Google 翻译的朗读接口：免费、无需密钥，语速偏快；'
        '它的接口不接受语速，由播放器变速（不保调）；需联网（境外）',
  ),
  baidu(
    '百度翻译语音',
    '百度翻译的朗读接口：免费、无需密钥，国内直连；语速由服务端合成，'
        '不会变调；音色偏合成',
  );

  const SpeechEngine(this.label, this.hint);

  final String label;
  final String hint;

  /// Whether this engine needs the network; those lines leave the machine.
  bool get isOnline => switch (this) {
        SpeechEngine.edge || SpeechEngine.google || SpeechEngine.baidu =>
          true,
        SpeechEngine.kokoro || SpeechEngine.system => false,
      };

  /// Whether this engine reads on this machine without a round trip.
  bool get isLocal => !isOnline;

  /// Whether the service bakes the speed into the audio it returns.
  ///
  /// Those lines play at the player's own rate (1.0): scaling an already slowed
  /// clip a second time is how 语速 ends up at double the value asked for.
  bool get bakesRate => switch (this) {
        SpeechEngine.edge || SpeechEngine.baidu => true,
        SpeechEngine.google ||
        SpeechEngine.kokoro ||
        SpeechEngine.system =>
          false,
      };

  static SpeechEngine byName(String? name) => values.firstWhere(
        (engine) => engine.name == name,
        orElse: () => SpeechEngine.kokoro,
      );
}
