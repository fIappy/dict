/// A user-written line the app can read back: a 短语 (one utterance) or a 短文
/// (split into sentences, so the drill can pace them).
library;

/// The two things this section holds.
enum CustomTextKind {
  phrase('短语'),
  passage('短文');

  const CustomTextKind(this.label);
  final String label;

  static CustomTextKind fromName(String? name) => CustomTextKind.values
      .firstWhere((kind) => kind.name == name, orElse: () => CustomTextKind.phrase);
}

/// A user-defined group both kinds can be filed under.
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

/// One entry of the 自定义短语 / 自定义短文 list.
class CustomText {
  const CustomText({
    required this.id,
    required this.kind,
    required this.body,
    this.title = '',
    this.groupId,
    required this.createdAt,
  });

  final String id;
  final CustomTextKind kind;

  /// What gets read out, verbatim.
  final String body;

  /// Optional name; empty means the body supplies the list label.
  final String title;

  /// Null when the entry is not in a group.
  final String? groupId;
  final DateTime createdAt;

  CustomText copyWith({
    CustomTextKind? kind,
    String? body,
    String? title,
    String? groupId,
    bool clearGroup = false,
  }) =>
      CustomText(
        id: id,
        kind: kind ?? this.kind,
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

  /// What playback reads, in order: the whole phrase, or the passage's
  /// sentences one after another (the gap between them comes from the settings).
  List<String> get utterances {
    if (kind == CustomTextKind.phrase) {
      final text = body.trim();
      return text.isEmpty ? const [] : [text];
    }
    return splitSentences(body);
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'kind': kind.name,
        'body': body,
        'title': title,
        'groupId': groupId,
        'createdAt': createdAt.toIso8601String(),
      };

  factory CustomText.fromJson(Map<String, Object?> json) => CustomText(
        id: json['id'] as String? ?? '',
        kind: CustomTextKind.fromName(json['kind'] as String?),
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
