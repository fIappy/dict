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

/// Splits a passage into the sentences playback walks one by one.
///
/// A sentence ends at `.` `!` `?` (Latin or full-width) or a line break; the
/// punctuation stays with the sentence, because the voice uses it for prosody.
List<String> splitSentences(String body) {
  final normalised = body.replaceAll('\r\n', '\n');
  final parts = normalised.split(RegExp(r'(?<=[.!?。！？;；:])\s+|\n+'));
  return [
    for (final part in parts)
      if (part.trim().isNotEmpty) part.trim(),
  ];
}
