class MdxTab {
  final String label;
  final String tag;

  const MdxTab({required this.label, required this.tag});

  Map<String, dynamic> toJson() => {'label': label, 'tag': tag};

  factory MdxTab.fromJson(Map<String, dynamic> json) => MdxTab(
        label: json['label'] as String? ?? '',
        tag: json['tag'] as String? ?? '',
      );
}

class MdxEntry {
  final String word;
  final String rawHtml;
  final String phonetic;
  final List<String> phonetics;
  final String? soundKey;
  final List<String> soundKeys;
  final List<MdxTab> tabs;
  final Map<String, String> panels;
  final List<String> exampleSentences;
  final List<String> definitions;

  MdxEntry({
    required this.word,
    required this.rawHtml,
    required this.phonetic,
    this.phonetics = const [],
    required this.soundKey,
    this.soundKeys = const [],
    required this.tabs,
    required this.panels,
    required this.exampleSentences,
    required this.definitions,
  });

  /// Wire format shared by the backend API and the web client.
  Map<String, dynamic> toJson() => {
        'word': word,
        'rawHtml': rawHtml,
        'phonetic': phonetic,
        'phonetics': phonetics,
        'soundKey': soundKey,
        'soundKeys': soundKeys,
        'tabs': tabs.map((t) => t.toJson()).toList(),
        'panels': panels,
        'exampleSentences': exampleSentences,
        'definitions': definitions,
      };

  factory MdxEntry.fromJson(Map<String, dynamic> json) {
    return MdxEntry(
      word: json['word'] as String? ?? '',
      rawHtml: json['rawHtml'] as String? ?? '',
      phonetic: json['phonetic'] as String? ?? '',
      phonetics: (json['phonetics'] as List?)?.cast<String>() ?? const [],
      soundKey: json['soundKey'] as String?,
      soundKeys: (json['soundKeys'] as List?)?.cast<String>() ?? const [],
      tabs: (json['tabs'] as List?)
              ?.whereType<Map>()
              .map((e) => MdxTab.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          const [],
      panels: (json['panels'] as Map?)
              ?.map((k, v) => MapEntry(k.toString(), v.toString())) ??
          const {},
      exampleSentences:
          (json['exampleSentences'] as List?)?.cast<String>() ?? const [],
      definitions: (json['definitions'] as List?)?.cast<String>() ?? const [],
    );
  }

  factory MdxEntry.parse(String queryWord, String html) {
    // 1. Extract headword
    String hw = queryWord;
    final hwRegex = RegExp(r"""<h1[^>]*class=['"]?[^'">]*hw[^'">]*['"]?[^>]*>(.*?)</h1>""", caseSensitive: false);
    final hwMatch = hwRegex.firstMatch(html) ?? RegExp(r'<h1[^>]*>(.*?)</h1>', caseSensitive: false).firstMatch(html);
    if (hwMatch != null) {
      final text = _stripTags(hwMatch.group(1)!).trim();
      if (text.isNotEmpty) hw = text;
    }

    // 2. Extract all phonetic transcriptions
    final pronList = <String>[];
    final pronRegex = RegExp(r"""<span[^>]*class=['"]?[^'">]*pron[^'">]*['"]?[^>]*>(.*?)</span>""", caseSensitive: false);
    for (final m in pronRegex.allMatches(html)) {
      final p = _stripTags(m.group(1)!).trim();
      if (p.isNotEmpty && !pronList.contains(p)) {
        pronList.add(p);
      }
    }
    final primaryPron = pronList.isNotEmpty ? pronList.first : '';

    // 3. Extract all sound file keys
    final soundList = <String>[];
    final soundRegex = RegExp(r"""sound://([^"'&?#\s<>]+)""", caseSensitive: false);
    for (final m in soundRegex.allMatches(html)) {
      final s = m.group(1)!;
      if (!soundList.contains(s)) {
        soundList.add(s);
      }
    }
    if (soundList.isEmpty) {
      final audioRegex = RegExp(r"""href=['"]([^'"]+\.(?:mp3|wav|ogg))['"]""", caseSensitive: false);
      for (final m in audioRegex.allMatches(html)) {
        final s = m.group(1)!;
        if (!soundList.contains(s)) {
          soundList.add(s);
        }
      }
    }
    final primarySound = soundList.isNotEmpty ? soundList.first : null;

    // 4. Extract tabs: <button ... data-t="tag">Label</button>
    final tabs = <MdxTab>[];
    final tabRegex = RegExp(r"""data-t=['"]([^'"]+)['"][^>]*>([^<]+)</button>""", caseSensitive: false);
    for (final match in tabRegex.allMatches(html)) {
      final tag = match.group(1)!;
      final label = match.group(2)!.trim();
      if (label.isNotEmpty && !tabs.any((t) => t.tag == tag)) {
        tabs.add(MdxTab(label: label, tag: tag));
      }
    }

    // 5. Extract panels: <div class='panel ...' data-p='tag'>...</div>
    final panels = <String, String>{};
    final panelRegex = RegExp(r"""data-p=['"]([^'"]+)['"][^>]*>(.*?)(?=<div[^>]*data-p=|\z|$)""", dotAll: true, caseSensitive: false);
    for (final match in panelRegex.allMatches(html)) {
      final tag = match.group(1)!;
      final content = match.group(2)!.trim();
      panels[tag] = content;
    }

    if (panels.isEmpty) {
      panels['default'] = html;
    }

    // 6. Extract example sentences
    final examples = <String>[];
    final exRegex = RegExp(r"""<span[^>]*class=['"]?ex['"]?[^>]*>(.*?)</span>""", dotAll: true, caseSensitive: false);
    for (final match in exRegex.allMatches(html)) {
      final ex = _stripTags(match.group(1)!).trim();
      if (ex.isNotEmpty && !examples.contains(ex)) {
        examples.add(ex);
      }
    }

    // 7. Extract definitions
    final defs = <String>[];
    final defRegex = RegExp(r'<li[^>]*>(.*?)</li>', dotAll: true, caseSensitive: false);
    for (final match in defRegex.allMatches(html)) {
      String rawLi = match.group(1)!;
      rawLi = rawLi.replaceAll(RegExp(r"""<span[^>]*class=['"]?ex['"]?[^>]*>.*?</span>""", dotAll: true, caseSensitive: false), '');
      final defText = _stripTags(rawLi).trim();
      if (defText.isNotEmpty && defText.length > 3) {
        defs.add(defText);
        if (defs.length >= 8) break;
      }
    }

    return MdxEntry(
      word: hw,
      rawHtml: html,
      phonetic: primaryPron,
      phonetics: pronList,
      soundKey: primarySound,
      soundKeys: soundList,
      tabs: tabs,
      panels: panels,
      exampleSentences: examples,
      definitions: defs,
    );
  }

  static String _stripTags(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
