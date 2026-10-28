import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

/// One speakable line of an entry: a phrase (词语搭配) or an example sentence
/// (权威例句 / Dictionary.com's `ex`).
///
/// The reader's job is to turn what is on screen into what a voice can say:
/// the entries interleave Chinese glosses and source-book labels with the
/// English, and both would be read out if the markup were passed through
/// verbatim. [text] is therefore the English line only, whitespace-collapsed.
class EntryUtterance {
  const EntryUtterance({
    required this.text,
    required this.isPhrase,
    this.itemId,
    this.sentenceIndex,
  });

  /// English text, ready for speech synthesis.
  final String text;

  /// True for a 词语搭配 line, false for an example sentence.
  final bool isPhrase;

  /// Optional ID of the item this utterance belongs to (e.g. [CustomText.id]).
  final String? itemId;

  /// Optional 0-based index of this sentence within the parent item.
  final int? sentenceIndex;

  @override
  bool operator ==(Object other) =>
      other is EntryUtterance &&
      other.text == text &&
      other.isPhrase == isPhrase &&
      other.itemId == itemId &&
      other.sentenceIndex == sentenceIndex;

  @override
  int get hashCode => Object.hash(text, isPhrase, itemId, sentenceIndex);

  @override
  String toString() =>
      '${isPhrase ? 'phrase' : 'sentence'}: $text'
      '${itemId != null ? ' (item: $itemId, #$sentenceIndex)' : ''}';
}
/// Elements whose text is *not* part of what the entry says: the Chinese
/// translation, the source book, the 〔keyword〕 label, the 中文显隐 button, and
/// the audio bar at the top of an SIO record.
const Set<String> _silentClasses = {
  'zh_cn',
  'pg_book',
  'pg_key',
  'comment',
  'tio_forvo',
};

/// Tags that never carry speech text. `zh_cn` is SIO's *tag* for the Chinese
/// side of a bilingual line (it also shows up as a class in older records).
const Set<String> _silentTags = {
  'zh_cn',
  'script',
  'style',
  'link',
  'audio',
  'img',
  'video',
  'button',
};

/// The phrases and example sentences of [html], in the order the page shows
/// them.
///
/// Two archives are covered: SIO 双向双解词典 marks each line with `pg_exam`
/// inside `pg_phrase` / `pg_sentence` sections, and Dictionary.com marks its
/// examples with `ex`. Anything else yields an empty list, and the entry then
/// simply has no playback affordance.
List<EntryUtterance> extractEntryUtterances(String html) =>
    prepareEntrySpeech(html).utterances;

/// [html] with a small speaker link appended to every speakable line, plus the
/// utterances those links address.
///
/// [speaking] is the index of the line being read; that line is marked with a
/// `speaking` class so the reader can colour it (the CSS lives in the view).
///
/// The index in `speech://<n>` is the index in [utterances], so the view can
/// hand a tapped link straight to the player. The markup is rewritten rather
/// than the lines being rendered as separate widgets because the entry is drawn
/// by `HtmlWidget` from one HTML string — pointing at the original elements
/// keeps every existing style rule and the surrounding flow intact.
({String html, List<EntryUtterance> utterances}) prepareEntrySpeech(
  String html, {
  int? speaking,
}) {
  if (html.trim().isEmpty) return (html: html, utterances: const []);

  final document = html_parser.parse(html);
  final utterances = <EntryUtterance>[];
  final seen = <String>{};
  var isPhrase = false;

  // Document order, so the sequential playback follows the page: SIO writes the
  // 词语搭配 section before the 权威例句 one.
  final lines = document.querySelectorAll(
    'span.pg_exam, span.ex, span.pg_phrase, span.pg_sentence',
  );

  for (final element in lines) {
    if (element.classes.contains('pg_phrase')) {
      isPhrase = true;
      continue;
    }
    if (element.classes.contains('pg_sentence')) {
      isPhrase = false;
      continue;
    }

    final text = _speakableText(element);
    if (text.isEmpty) continue;
    final key = text.toLowerCase();
    if (!seen.add(key)) continue;

    final index = utterances.length;
    utterances.add(EntryUtterance(text: text, isPhrase: isPhrase));

    // Appended, not wrapped: the line keeps its own styling, and the reader
    // gets one consistent affordance at its end.
    element.append(Element.tag('a')
      ..attributes['href'] = 'speech://$index'
      ..attributes['class'] = 'speech'
      ..text = '🔊');
    if (index == speaking) {
      element.classes.add('speaking');
    }
  }

  return (
    html: document.body?.innerHtml ?? html,
    utterances: utterances,
  );
}

/// The English wording of [element], without the Chinese, the source book and
/// the 〔keyword〕 label.
String _speakableText(Element element) {
  final buffer = StringBuffer();

  void collect(Node node) {
    if (node is Text) {
      buffer.write(node.text);
      return;
    }
    if (node is! Element) return;
    if (_silentTags.contains(node.localName)) {
      buffer.write(' ');
      return;
    }
    if (node.classes.any(_silentClasses.contains)) return;
    for (final child in node.nodes) {
      collect(child);
    }
  }

  collect(element);

  var text = buffer
      .toString()
      .replaceAll('\u00a0', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  // Brackets left over once the label was dropped ("〔…〕…" keeps the text that
  // followed the label, so only the leading punctuation has to go).
  text = text
      .replaceAll(RegExp(r'^[\s〔\[\(【〈《]+'), '')
      .replaceAll(RegExp(r'[\s〕\]\)】〉》]+$'), '')
      .trim();

  if (text.length < 4) return '';
  if (!RegExp('[A-Za-z]{2}').hasMatch(text)) return '';
  // A single word is neither a phrase nor a sentence; those are the headword
  // itself, which the pronunciation bar already speaks.
  if (text.split(' ').length < 2) return '';
  return text;
}
