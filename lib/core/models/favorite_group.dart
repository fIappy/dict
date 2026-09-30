class FavoriteGroup {
  final String id;
  final String name;
  final String? description;
  final int color;
  final String? icon;
  final int sortOrder;
  final DateTime createdAt;
  final int wordCount;

  const FavoriteGroup({
    required this.id,
    required this.name,
    this.description,
    this.color = 0xFF3F51B5, // Default Indigo
    this.icon,
    this.sortOrder = 0,
    required this.createdAt,
    this.wordCount = 0,
  });

  FavoriteGroup copyWith({
    String? id,
    String? name,
    String? description,
    int? color,
    String? icon,
    int? sortOrder,
    DateTime? createdAt,
    int? wordCount,
  }) {
    return FavoriteGroup(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      color: color ?? this.color,
      icon: icon ?? this.icon,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
      wordCount: wordCount ?? this.wordCount,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'color': color,
      'icon': icon,
      'sort_order': sortOrder,
      'created_at': createdAt.millisecondsSinceEpoch,
    };
  }

  factory FavoriteGroup.fromMap(Map<String, dynamic> map, {int wordCount = 0}) {
    return FavoriteGroup(
      id: map['id'] as String,
      name: map['name'] as String,
      description: map['description'] as String?,
      color: map['color'] as int? ?? 0xFF3F51B5,
      icon: map['icon'] as String?,
      sortOrder: map['sort_order'] as int? ?? 0,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      wordCount: (map['word_count'] as int?) ?? wordCount,
    );
  }
}
