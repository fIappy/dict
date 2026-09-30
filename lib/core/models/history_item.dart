class HistoryItem {
  final String id;
  final String word;
  final String? dictSource;
  final String? phonetic;
  final DateTime createdAt;

  const HistoryItem({
    required this.id,
    required this.word,
    this.dictSource,
    this.phonetic,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'word': word,
      'dict_source': dictSource,
      'phonetic': phonetic,
      'created_at': createdAt.millisecondsSinceEpoch,
    };
  }

  factory HistoryItem.fromMap(Map<String, dynamic> map) {
    return HistoryItem(
      id: map['id'] as String,
      word: map['word'] as String,
      dictSource: map['dict_source'] as String?,
      phonetic: map['phonetic'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    );
  }
}
