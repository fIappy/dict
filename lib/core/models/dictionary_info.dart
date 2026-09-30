class DictionaryInfo {
  final String id;
  final String name;
  final String mdxPath;
  final String? mddPath;
  final String? cssPath;
  final bool isEnabled;
  final int priority;
  final int entryCount;
  final DateTime createdAt;

  const DictionaryInfo({
    required this.id,
    required this.name,
    required this.mdxPath,
    this.mddPath,
    this.cssPath,
    this.isEnabled = true,
    this.priority = 0,
    this.entryCount = 0,
    required this.createdAt,
  });

  DictionaryInfo copyWith({
    String? id,
    String? name,
    String? mdxPath,
    String? mddPath,
    String? cssPath,
    bool? isEnabled,
    int? priority,
    int? entryCount,
    DateTime? createdAt,
  }) {
    return DictionaryInfo(
      id: id ?? this.id,
      name: name ?? this.name,
      mdxPath: mdxPath ?? this.mdxPath,
      mddPath: mddPath ?? this.mddPath,
      cssPath: cssPath ?? this.cssPath,
      isEnabled: isEnabled ?? this.isEnabled,
      priority: priority ?? this.priority,
      entryCount: entryCount ?? this.entryCount,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'mdx_path': mdxPath,
      'mdd_path': mddPath,
      'css_path': cssPath,
      'is_enabled': isEnabled ? 1 : 0,
      'priority': priority,
      'entry_count': entryCount,
      'created_at': createdAt.millisecondsSinceEpoch,
    };
  }

  factory DictionaryInfo.fromMap(Map<String, dynamic> map) {
    return DictionaryInfo(
      id: map['id'] as String,
      name: map['name'] as String,
      mdxPath: map['mdx_path'] as String,
      mddPath: map['mdd_path'] as String?,
      cssPath: map['css_path'] as String?,
      isEnabled: (map['is_enabled'] as int) == 1,
      priority: map['priority'] as int? ?? 0,
      entryCount: map['entry_count'] as int? ?? 0,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    );
  }
}
