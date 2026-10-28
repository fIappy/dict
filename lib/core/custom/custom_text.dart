/// A user-written passage the app reads back sentence by sentence.
///
/// Everything in this section is a 短文 now: a single line without punctuation
/// simply yields one sentence. Entries stored by the earlier build carried a
/// `kind` field (`phrase` / `passage`); it is ignored on read, which is exactly
/// the requested migration — the old phrases are passages with one sentence.
library;

/// A user-defined group the passages are filed under.
class CustomTextGroup {
  const CustomTextGroup({required this.id, required this.name});

  final String id;
  final String name;

  Map<String, Object?> toJson() => {'id': id, 'name': name};

  factory CustomTextGroup.fromJson(Map<String, Object?> json) => CustomTextGroup(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
      );
}

/// One entry of the 自定义短文 list.
class CustomText {
  const CustomText({
    required this.id,
    required this.body,
    this.title = '',
    this.groupId,
    required this.createdAt,
  });

  final String id;

  /// What gets read out, verbatim.
  final String body;

  /// Optional name; empty means the body supplies the list label.
  final String title;

  /// Null when the entry is not in a group.
  final String? groupId;
  final DateTime createdAt;

  CustomText copyWith({
    String? body,
    String? title,
    String? groupId,
    bool clearGroup = false,
  }) =>
      CustomText(
        id: id,
        body: body ?? this.body,
        title: title ?? this.title,
        groupId: clearGroup ? null : (groupId ?? this.groupId),
        createdAt: createdAt,
      );

  /// What the list shows: the title, or the first line of the body.
  String get label {
    final trimmed = title.trim();
    if (trimmed.isNotEmpty) return trimmed;
    final firstLine = body
        .split('\n')
        .map((line) => line.trim())
        .firstWhere((line) => line.isNotEmpty, orElse: () => body.trim());
    if (firstLine.length <= 48) return firstLine;
    return '${firstLine.substring(0, 48)}…';
  }

  /// What playback reads, in order: the passage's sentences.
  List<String> get utterances => splitSentences(body);

  Map<String, Object?> toJson() => {
        'id': id,
        'body': body,
        'title': title,
        'groupId': groupId,
        'createdAt': createdAt.toIso8601String(),
      };

  /// Reads an entry; the legacy `kind` field is deliberately not read.
  factory CustomText.fromJson(Map<String, Object?> json) => CustomText(
        id: json['id'] as String? ?? '',
        body: json['body'] as String? ?? '',
        title: json['title'] as String? ?? '',
        groupId: json['groupId'] as String?,
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      );
}

/// Where a sentence ends: terminal punctuation plus the space after it, or a
/// line break. Offsets are in the original text, so a click position can be
/// mapped back to a sentence.
final RegExp _sentenceBreak =
    RegExp(r'[.!?。！？;；:]+[ \t\r\n]+|\r?\n+');

/// The sentences of [body] as ranges over the original string.
List<({int start, int end})> sentenceRanges(String body) {
  final ranges = <({int start, int end})>[];
  var start = 0;
  for (final match in _sentenceBreak.allMatches(body)) {
    if (match.end > start) ranges.add((start: start, end: match.end));
    start = match.end;
  }
  if (start < body.length) ranges.add((start: start, end: body.length));

  // Trim the edges without losing the ability to place a click: a range still
  // covers its sentence, the whitespace just belongs to nobody.
  final trimmed = <({int start, int end})>[];
  for (final range in ranges) {
    var a = range.start;
    var b = range.end;
    while (a < b && _isSpace(body.codeUnitAt(a))) {
      a++;
    }
    while (b > a && _isSpace(body.codeUnitAt(b - 1))) {
      b--;
    }
    if (b > a) trimmed.add((start: a, end: b));
  }
  return trimmed;
}

/// One piece of a passage as it was written: the text between two sentence
/// breaks, the separator that followed it, and — when the piece is not just
/// whitespace — the index [splitSentences] gives it.
///
/// Rendering a passage sentence by sentence for the red mark must not reflow
/// it: a one-sentence-per-line article has to keep its line breaks, so the
/// separators travel with the pieces instead of being collapsed to spaces.
class PassageSegment {
  const PassageSegment({
    required this.text,
    required this.separator,
    required this.sentenceIndex,
  });

  final String text;
  final String separator;

  /// Null for whitespace-only pieces (blank lines between paragraphs).
  final int? sentenceIndex;

  bool get isSentence => sentenceIndex != null;
}

/// [body] split into [PassageSegment]s, using the same rule as
/// [splitSentences] so the indices line up with what playback reads.
List<PassageSegment> passageSegments(String body) {
  final normalised = body.replaceAll('\r\n', '\n');
  final separator = RegExp(r'(?<=[.!?。！？;；:])\s+|\n+');
  final segments = <PassageSegment>[];
  var start = 0;
  var sentence = 0;
  void add(String text, String separator) {
    final isSentence = text.trim().isNotEmpty;
    segments.add(PassageSegment(
      text: text,
      separator: separator,
      sentenceIndex: isSentence ? sentence++ : null,
    ));
  }

  for (final match in separator.allMatches(normalised)) {
    add(normalised.substring(start, match.start), match.group(0)!);
    start = match.end;
  }
  if (start < normalised.length) add(normalised.substring(start), '');
  return segments;
}

/// Splits a passage into the sentences playback walks one by one.
///
/// A sentence ends at `.` `!` `?` (Latin or full-width), `;` `:` or a line
/// break; the punctuation stays with the sentence, because the voice uses it
/// for prosody.
List<String> splitSentences(String body) => [
      for (final range in sentenceRanges(body))
        body.substring(range.start, range.end),
    ];

/// The sentence that contains [offset] and every sentence after it, along
/// with the 0-based index of the first sentence in [splitSentences] order.
({int startIndex, List<String> sentences}) sentencesFromWithIndex(
    String body, int offset) {
  final ranges = sentenceRanges(body);
  if (ranges.isEmpty) return (startIndex: 0, sentences: const <String>[]);
  final at = offset.clamp(0, body.length);
  var index = ranges.indexWhere((range) => at < range.end);
  if (index < 0) index = ranges.length - 1;
  return (
    startIndex: index,
    sentences: [
      for (var i = index; i < ranges.length; i++)
        body.substring(ranges[i].start, ranges[i].end),
    ],
  );
}

/// The sentence that contains [offset] and every sentence after it.
///
/// This is what "read from here" needs: a click anywhere inside a sentence
/// starts that sentence, not the next one.
List<String> sentencesFrom(String body, int offset) =>
    sentencesFromWithIndex(body, offset).sentences;

bool _isSpace(int code) =>
    code == 0x20 || code == 0x09 || code == 0x0A || code == 0x0D;
