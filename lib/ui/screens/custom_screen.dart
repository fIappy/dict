import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/custom/custom_text.dart';
import '../../core/mdx/entry_speech.dart';
import '../../providers/custom_text_provider.dart';
import '../../providers/entry_speech_provider.dart';
import '../../providers/settings_provider.dart';
import 'custom_detail_view.dart';

/// The 自定义短语 / 自定义短文 list: the user's own lines, filed in groups, each
/// with a play button, plus one 顺序播放 for the whole filtered list.
class CustomScreen extends StatelessWidget {
  final bool isPaneView;

  const CustomScreen({super.key, this.isPaneView = false});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CustomTextProvider>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: isPaneView
          ? null
          : AppBar(
              title: const Text('自定义短语与短文',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: SegmentedButton<CustomTextKind>(
              segments: [
                for (final kind in CustomTextKind.values)
                  ButtonSegment(
                    value: kind,
                    label: Text(kind.label,
                        style: const TextStyle(fontSize: 12.5)),
                  ),
              ],
              selected: {provider.kind},
              showSelectedIcon: false,
              onSelectionChanged: (selection) =>
                  provider.selectKind(selection.first),
            ),
          ),
          _buildGroupBar(context, provider),
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
          Expanded(child: _buildList(context, provider)),
          _buildBottomBar(context, provider),
        ],
      ),
    );
  }

  /// 全部 / 未分组 / each group / 新建分组.
  Widget _buildGroupBar(BuildContext context, CustomTextProvider provider) {
    final selected = provider.groupFilter;
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          _chip(context, '全部', null, selected),
          _chip(context, '未分组', CustomTextProvider.ungroupedFilter, selected),
          for (final group in provider.groups)
            _chip(context, group.name, group.id, selected),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
            child: ActionChip(
              avatar: const Icon(Icons.create_new_folder_outlined, size: 16),
              label: const Text('新建分组', style: TextStyle(fontSize: 12)),
              onPressed: () => _promptNewGroup(context, provider),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(
    BuildContext context,
    String label,
    String? value,
    String? selected,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 3),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: selected == value,
        visualDensity: VisualDensity.compact,
        onSelected: (_) => context.read<CustomTextProvider>().setGroupFilter(value),
      ),
    );
  }

  Widget _buildList(BuildContext context, CustomTextProvider provider) {
    final items = provider.visibleTexts;
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            provider.kind == CustomTextKind.phrase
                ? '还没有自定义短语，点右下角「添加」写一条'
                : '还没有自定义短文，点右下角「添加」写一段',
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).hintColor),
          ),
        ),
      );
    }

    final speech = context.watch<EntrySpeechProvider>();
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: items.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 56),
      itemBuilder: (context, index) {
        final item = items[index];
        final group = _groupOf(provider, item);
        final speaking = speech.isPlaying && speech.currentIndex != null;
        return ListTile(
          dense: true,
          leading: IconButton(
            icon: Icon(speaking ? Icons.volume_up_rounded : Icons.play_circle_outline_rounded),
            tooltip: '播放这一条',
            onPressed: () => _play(context, [item]),
          ),
          title: Text(
            item.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            [
              item.utterances.length > 1 ? '${item.utterances.length} 句' : null,
              group?.name ?? '未分组',
            ].whereType<String>().join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11.5),
          ),
          trailing: PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, size: 18),
            onSelected: (action) {
              switch (action) {
                case 'edit':
                  provider.select(item.id);
                  if (!isPaneView) _openDetail(context, provider, item.id);
                case 'group':
                  _promptGroup(context, provider, item);
                case 'delete':
                  provider.remove(item.id);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('编辑')),
              PopupMenuItem(value: 'group', child: Text('分组…')),
              PopupMenuItem(value: 'delete', child: Text('删除')),
            ],
          ),
          onTap: () {
            provider.select(item.id);
            if (!isPaneView) _openDetail(context, provider, item.id);
          },
        );
      },
    );
  }

  CustomTextGroup? _groupOf(CustomTextProvider provider, CustomText item) {
    for (final group in provider.groups) {
      if (group.id == item.groupId) return group;
    }
    return null;
  }

  Widget _buildBottomBar(BuildContext context, CustomTextProvider provider) {
    final speech = context.watch<EntrySpeechProvider>();
    final theme = Theme.of(context);
    final queue = provider.playbackQueue;
    final playing = speech.isPlaying;
    final index = speech.currentIndex;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.tonalIcon(
              icon: Icon(
                playing ? Icons.stop_rounded : Icons.playlist_play_rounded,
                size: 18,
              ),
              label: Text(
                playing
                    ? '停止 ${index == null ? '' : '${index + 1}/${speech.items.length}'}'.trimRight()
                    : '顺序播放 ${queue.length} 句',
              ),
              onPressed: queue.isEmpty
                  ? null
                  : () {
                      if (playing) {
                        speech.stop();
                        return;
                      }
                      _playQueue(context, queue);
                    },
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('添加'),
            onPressed: () {
              provider.select(null);
              _openDetail(context, provider, null);
            },
          ),
        ],
      ),
    );
  }

  void _openDetail(BuildContext context, CustomTextProvider provider, String? id) {
    if (isPaneView) return; // The desktop detail pane follows the selection.
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CustomDetailView(itemId: id),
      ),
    );
  }

  void _play(BuildContext context, List<CustomText> items) {
    final queue = [
      for (final item in items)
        for (final line in item.utterances)
          EntryUtterance(text: line, isPhrase: item.kind == CustomTextKind.phrase),
    ];
    _playQueue(context, queue);
  }

  void _playQueue(BuildContext context, List<EntryUtterance> queue) {
    final settings = context.read<SettingsProvider>();
    context.read<EntrySpeechProvider>().playAll(
          queue,
          rate: settings.speechRate,
          gap: settings.sentenceGap,
          accent: accentForLanguage(settings.ttsLanguage),
        );
  }

  Future<void> _promptNewGroup(
    BuildContext context,
    CustomTextProvider provider,
  ) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('新建分组'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '例如：商务英语'),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null) return;
    final group = await provider.addGroup(name);
    if (group != null) provider.setGroupFilter(group.id);
  }

  /// One row of the「归入」dialog; the current group carries a check mark.
  Widget _groupChoice(
    BuildContext context,
    String label,
    String value,
    bool selected,
  ) {
    return ListTile(
      dense: true,
      title: Text(label),
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        size: 18,
      ),
      onTap: () => Navigator.of(context).pop(value),
    );
  }

  Future<void> _promptGroup(
    BuildContext context,
    CustomTextProvider provider,
    CustomText item,
  ) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text('「${item.label}」归入'),
        children: [
          _groupChoice(dialogContext, '未分组', '__none__', item.groupId == null),
          for (final group in provider.groups)
            _groupChoice(
              dialogContext,
              group.name,
              group.id,
              item.groupId == group.id,
            ),
        ],
      ),
    );
    if (choice == null) return;
    await provider.update(
      item.copyWith(
        groupId: choice == '__none__' ? null : choice,
        clearGroup: choice == '__none__',
      ),
    );
  }
}
