import 'package:flutter/material.dart';
import '../../core/models/favorite_group.dart';
import '../../core/models/favorite_item.dart';

class GroupSelectorDialog extends StatefulWidget {
  final String word;
  final String? phonetic;
  final String? definition;
  final List<FavoriteGroup> groups;
  final FavoriteItem? existingFavorite;
  final Future<void> Function(String groupId, String note) onSave;
  final Future<void> Function()? onRemove;
  final Future<FavoriteGroup> Function(String name, int color) onCreateGroup;

  const GroupSelectorDialog({
    super.key,
    required this.word,
    this.phonetic,
    this.definition,
    required this.groups,
    this.existingFavorite,
    required this.onSave,
    this.onRemove,
    required this.onCreateGroup,
  });

  @override
  State<GroupSelectorDialog> createState() => _GroupSelectorDialogState();
}

class _GroupSelectorDialogState extends State<GroupSelectorDialog> {
  late String _selectedGroupId;
  late TextEditingController _noteController;
  bool _isCreatingNew = false;
  final TextEditingController _newGroupNameController = TextEditingController();
  int _selectedColor = 0xFF3F51B5;

  final List<int> _palette = const [
    0xFF3F51B5, // Indigo
    0xFF2E7D32, // Green
    0xFFEF6C00, // Orange
    0xFFC2185B, // Pink
    0xFF673AB7, // Deep Purple
    0xFF0097A7, // Cyan
    0xFF5D4037, // Brown
    0xFF455A64, // Blue Grey
  ];

  @override
  void initState() {
    super.initState();
    _selectedGroupId = widget.existingFavorite?.groupId ??
        (widget.groups.isNotEmpty ? widget.groups.first.id : 'default');
    _noteController = TextEditingController(text: widget.existingFavorite?.note ?? '');
  }

  @override
  void dispose() {
    _noteController.dispose();
    _newGroupNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isFavorited = widget.existingFavorite != null;

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            isFavorited ? Icons.star_rounded : Icons.star_border_rounded,
            color: Colors.amber[700],
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isFavorited ? '编辑收藏: ${widget.word}' : '收藏词汇: ${widget.word}',
              style: const TextStyle(fontSize: 18),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.phonetic != null && widget.phonetic!.isNotEmpty)
                Text(
                  widget.phonetic!,
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              const SizedBox(height: 16),

              const Text(
                '选择生词本分组',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 8),

              // Group Radio list or Dropdown
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: theme.dividerColor),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: RadioGroup<String>(
                  groupValue: _selectedGroupId,
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedGroupId = val);
                  },
                  child: Column(
                    children: [
                      for (final g in widget.groups)
                        RadioListTile<String>(
                          dense: true,
                          value: g.id,
                          title: Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: Color(g.color),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(g.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                            ],
                          ),
                          secondary: Text(
                            '${g.wordCount} 词',
                            style: TextStyle(color: theme.hintColor, fontSize: 12),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // Create new group toggle button
              if (!_isCreatingNew)
                TextButton.icon(
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('新建生词本分组'),
                  onPressed: () => setState(() => _isCreatingNew = true),
                )
              else ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _newGroupNameController,
                        autofocus: true,
                        decoration: const InputDecoration(
                          hintText: '输入新分组名称 (如: 考研生词)',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      child: const Text('创建'),
                      onPressed: () async {
                        final name = _newGroupNameController.text.trim();
                        if (name.isNotEmpty) {
                          final newGroup = await widget.onCreateGroup(name, _selectedColor);
                          setState(() {
                            _selectedGroupId = newGroup.id;
                            _isCreatingNew = false;
                            _newGroupNameController.clear();
                          });
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: _palette.map((colorVal) {
                    final isSel = _selectedColor == colorVal;
                    return InkWell(
                      onTap: () => setState(() => _selectedColor = colorVal),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: Color(colorVal),
                          shape: BoxShape.circle,
                          border: isSel
                              ? Border.all(color: Colors.white, width: 2)
                              : null,
                          boxShadow: isSel
                              ? [const BoxShadow(color: Colors.black26, blurRadius: 4)]
                              : null,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],

              const SizedBox(height: 16),
              const Text(
                '学习笔记 / 助记',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _noteController,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: '输入记忆法、搭配或个人复习备忘...',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (isFavorited && widget.onRemove != null)
          TextButton.icon(
            icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
            label: const Text('取消收藏', style: TextStyle(color: Colors.red)),
            onPressed: () async {
              final nav = Navigator.of(context);
              await widget.onRemove?.call();
              if (mounted) nav.pop();
            },
          ),
        TextButton(
          child: const Text('取消'),
          onPressed: () => Navigator.pop(context),
        ),
        FilledButton(
          child: const Text('保存'),
          onPressed: () async {
            final nav = Navigator.of(context);
            await widget.onSave(_selectedGroupId, _noteController.text.trim());
            if (mounted) nav.pop();
          },
        ),
      ],
    );
  }
}
