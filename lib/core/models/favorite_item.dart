class FavoriteItem {
  final String id;
  final String word;
  final String groupId;
  final String? phonetic;
  final String? definitionSnippet;
  final String? examplesSnippet;
  final String? note;
  final String? dictSource;
  final List<String> tags;
  final DateTime createdAt;
  final DateTime updatedAt;

  const FavoriteItem({
    required this.id,
    required this.word,
    required this.groupId,
    this.phonetic,
    this.definitionSnippet,
    this.examplesSnippet,
    this.note,
    this.dictSource,
    this.tags = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  FavoriteItem copyWith({
    String? id,
    String? word,
    String? groupId,
    String? phonetic,
    String? definitionSnippet,
    String? examplesSnippet,
    String? note,
    String? dictSource,
    List<String>? tags,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return FavoriteItem(
      id: id ?? this.id,
      word: word ?? this.word,
      groupId: groupId ?? this.groupId,
      phonetic: phonetic ?? this.phonetic,
      definitionSnippet: definitionSnippet ?? this.definitionSnippet,
      examplesSnippet: examplesSnippet ?? this.examplesSnippet,
      note: note ?? this.note,
      dictSource: dictSource ?? this.dictSource,
      tags: tags ?? this.tags,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'word': word,
      'group_id': groupId,
      'phonetic': phonetic,
      'definition_snippet': definitionSnippet,
      'examples_snippet': examplesSnippet,
      'note': note,
      'dict_source': dictSource,
      'tags': tags.join(','),
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory FavoriteItem.fromMap(Map<String, dynamic> map) {
    final tagsStr = map['tags'] as String? ?? '';
    final tags = tagsStr.split(',').where((s) => s.trim().isNotEmpty).toList();
    return FavoriteItem(
      id: map['id'] as String,
      word: map['word'] as String,
      groupId: map['group_id'] as String,
      phonetic: map['phonetic'] as String?,
      definitionSnippet: map['definition_snippet'] as String?,
      examplesSnippet: map['examples_snippet'] as String?,
      note: map['note'] as String?,
      dictSource: map['dict_source'] as String?,
      tags: tags,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
    );
  }
}
