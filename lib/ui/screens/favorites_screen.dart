import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/audio/audio_manager.dart';
import '../../core/frequency/frequency_service.dart';
import '../../core/models/favorite_group.dart';
import '../../core/models/favorite_item.dart';
import '../../providers/dictionary_provider.dart';
import '../../providers/favorites_provider.dart';
import '../widgets/frequency_badge.dart';
import '../widgets/group_selector_dialog.dart';
import 'word_detail_screen.dart';

class FavoritesScreen extends StatefulWidget {
  final bool isPaneView;
  final void Function(String word)? onSelectWord;

  const FavoritesScreen({
    super.key,
    this.isPaneView = false,
    this.onSelectWord,
  });

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  final TextEditingController _searchController = TextEditingController();
  final AudioManager _audio = AudioManager();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onWordTapped(String word) {
    final dictProvider = context.read<DictionaryProvider>();
    dictProvider.lookupWord(word);

    if (widget.onSelectWord != null) {
      widget.onSelectWord!(word);
    } else if (!widget.isPaneView) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => WordDetailScreen(word: word),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final favProvider = context.watch<FavoritesProvider>();
    final groups = favProvider.groups;
    final favorites = favProvider.favorites;

    return Scaffold(
      appBar: widget.isPaneView
          ? null
          : AppBar(
              title: const Text('我的生词本', style: TextStyle(fontWeight: FontWeight.bold)),
              actions: [
                IconButton(
                  icon: const Icon(Icons.add_rounded),
                  tooltip: '新建分组',
                  onPressed: () => _showCreateGroupDialog(context, favProvider),
                ),
              ],
            ),
      body: Column(
        children: [
          // Group Filter Chips & Search Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E2430) : Colors.white,
              border: Border(
                bottom: BorderSide(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Search inside favorites
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: '在生词本中搜索单词或笔记...',
                    isDense: true,
                    prefixIcon: const Icon(Icons.filter_list_rounded, size: 20),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              favProvider.setFilterQuery('');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (val) => favProvider.setFilterQuery(val),
                ),
                const SizedBox(height: 10),

                // Group Chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      // "All" chip
                      FilterChip(
                        selected: favProvider.selectedGroupId == null,
                        label: Text('全部 (${groups.fold<int>(0, (sum, g) => sum + g.wordCount)})'),
                        onSelected: (_) => favProvider.selectGroup(null),
                      ),
                      const SizedBox(width: 8),

                      // Group chips
                      for (final g in groups) ...[
                        FilterChip(
                          selected: favProvider.selectedGroupId == g.id,
                          avatar: Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: Color(g.color),
                              shape: BoxShape.circle,
                            ),
                          ),
                          label: Text('${g.name} (${g.wordCount})'),
                          onSelected: (_) => favProvider.selectGroup(g.id),
                        ),
                        const SizedBox(width: 8),
                      ],

                      IconButton(
                        icon: const Icon(Icons.add_circle_outline_rounded, size: 22),
                        tooltip: '新建分组',
                        onPressed: () => _showCreateGroupDialog(context, favProvider),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Favorites Card List
          Expanded(
            child: favorites.isEmpty
                ? _buildEmptyState(theme, favProvider)
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: favorites.length,
                    itemBuilder: (context, index) {
                      final item = favorites[index];
                      final group = groups.firstWhere(
                        (g) => g.id == item.groupId,
                        orElse: () => groups.first,
                      );
                      return _buildFavoriteCard(context, item, group, theme, isDark, favProvider);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme, FavoritesProvider favProvider) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bookmark_border_rounded, size: 64, color: theme.hintColor),
            const SizedBox(height: 16),
            Text(
              favProvider.selectedGroupId != null ? '当前分组暂无收藏词汇' : '生词本还是空的',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '在查词页面点击星星按钮，即可将单词及笔记收藏到对应分组',
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.hintColor),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFavoriteCard(
    BuildContext context,
    FavoriteItem item,
    FavoriteGroup group,
    ThemeData theme,
    bool isDark,
    FavoritesProvider favProvider,
  ) {
    final freq = FrequencyService().getFrequency(item.word);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: isDark ? const Color(0xFF1E2430) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _onWordTapped(item.word),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Text(
                          item.word,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (item.phonetic != null && item.phonetic!.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Text(
                            item.phonetic!,
                            style: TextStyle(
                              color: theme.colorScheme.primary,
                              fontSize: 13.5,
                              fontFamily: 'Gentium Plus DC',
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Speaker Play Button
                  IconButton(
                    icon: const Icon(Icons.volume_up_rounded, size: 20),
                    tooltip: '播放读音',
                    onPressed: () => _audio.playWord(word: item.word),
                  ),

                  // Edit / Move Group Button
                  IconButton(
                    icon: const Icon(Icons.star_rounded, color: Colors.amber),
                    tooltip: '编辑分组/笔记',
                    onPressed: () => _openEditDialog(context, item, favProvider),
                  ),
                ],
              ),

              // Frequency & Exam Badges
              if (freq != null) ...[
                const SizedBox(height: 6),
                FrequencyBadge(info: freq),
              ],

              // Definition Snippet
              if (item.definitionSnippet != null && item.definitionSnippet!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  item.definitionSnippet!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
              ],

              // User Study Note
              if (item.note != null && item.note!.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isDark ? Colors.white10 : Colors.black12,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.edit_note_rounded, size: 16, color: Colors.amber),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          item.note!,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontStyle: FontStyle.italic,
                            color: isDark ? Colors.amber[200] : Colors.brown[700],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 8),
              // Group Tag
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Color(group.color).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  group.name,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(group.color),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openEditDialog(BuildContext context, FavoriteItem item, FavoritesProvider favProvider) {
    showDialog(
      context: context,
      builder: (_) => GroupSelectorDialog(
        word: item.word,
        phonetic: item.phonetic,
        definition: item.definitionSnippet,
        groups: favProvider.groups,
        existingFavorite: item,
        onSave: (groupId, note) async {
          await favProvider.addOrUpdateFavorite(
            word: item.word,
            groupId: groupId,
            phonetic: item.phonetic,
            definitionSnippet: item.definitionSnippet,
            examplesSnippet: item.examplesSnippet,
            note: note,
          );
        },
        onRemove: () async {
          await favProvider.removeFavorite(item.word);
        },
        onCreateGroup: (name, color) async {
          return await favProvider.createGroup(name, color);
        },
      ),
    );
  }

  void _showCreateGroupDialog(BuildContext context, FavoritesProvider favProvider) {
    final nameCtrl = TextEditingController();
    int color = 0xFF2E7D32;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          title: const Text('新建生词本分组'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '分组名称',
                  hintText: '如: 托福真词 / 错题本',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              const Text('选择分组标签颜色', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  0xFF3F51B5, 0xFF2E7D32, 0xFFEF6C00, 0xFFC2185B,
                  0xFF673AB7, 0xFF0097A7, 0xFF5D4037, 0xFF455A64,
                ].map((c) => InkWell(
                  onTap: () => setDlgState(() => color = c),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Color(c),
                      shape: BoxShape.circle,
                      border: color == c ? Border.all(color: Colors.white, width: 2.5) : null,
                      boxShadow: color == c ? [const BoxShadow(color: Colors.black26, blurRadius: 4)] : null,
                    ),
                  ),
                )).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              child: const Text('取消'),
              onPressed: () => Navigator.pop(ctx),
            ),
            FilledButton(
              child: const Text('创建'),
              onPressed: () async {
                final text = nameCtrl.text.trim();
                if (text.isNotEmpty) {
                  await favProvider.createGroup(text, color);
                  if (ctx.mounted) Navigator.pop(ctx);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
