import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/custom/custom_text.dart';
import '../../core/mdx/entry_speech.dart';
import '../../providers/custom_text_provider.dart';
import '../../providers/entry_speech_provider.dart';
import '../../core/custom/playback_order.dart';
import '../../providers/settings_provider.dart';
import 'custom_detail_view.dart';
import '../widgets/speech_controls.dart';

/// The 自定义短文 section, classified by **group**: the top of the pane lists
/// the groups (未分组 included, because every entry belongs somewhere), and the
/// passages of the selected group sit below.
class CustomScreen extends StatelessWidget {
  final bool isPaneView;

  const CustomScreen({super.key, this.isPaneView = false});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CustomTextProvider>();

    return Scaffold(
      appBar: isPaneView
          ? null
          : AppBar(
              title: const Text('自定义短文',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
      body: Column(
        children: [
          _buildGroupSection(context, provider),
          Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
          _buildGroupHeader(context, provider),
          Expanded(child: _buildList(context, provider)),
          _buildBottomBar(context, provider),
        ],
      ),
    );
  }

  /// The top level: one row per group, with how many entries it holds.
  Widget _buildGroupSection(BuildContext context, CustomTextProvider provider) {
    final theme = Theme.of(context);
    final groups = provider.groups;

    return Container(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
      constraints: const BoxConstraints(maxHeight: 190),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 2),
            child: Row(
              children: [
                Icon(Icons.folder_copy_outlined,
                    size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                const Text('分组',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 12.5)),
                const Spacer(),
                TextButton.icon(
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('新建分组', style: TextStyle(fontSize: 12)),
                  onPressed: () => _promptNewGroup(context, provider),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 4),
              children: [
                _groupTile(context, provider, CustomTextProvider.ungroupedId,
                    '未分组', null),
                for (final group in groups)
                  _groupTile(context, provider, group.id, group.name, group.id),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _groupTile(
    BuildContext context,
    CustomTextProvider provider,
    String groupId,
    String name,
    String? editableGroupId,
  ) {
    final theme = Theme.of(context);
    final selected = provider.selectedGroupId == groupId;
    final count = provider.countIn(groupId);

    return InkWell(
      onTap: () => provider.selectGroup(groupId),
      child: Container(
        color: selected ? theme.colorScheme.primary.withValues(alpha: 0.10) : null,
        padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
        child: Row(
          children: [
            Icon(
              selected ? Icons.folder_rounded : Icons.folder_outlined,
              size: 16,
              color: selected ? theme.colorScheme.primary : theme.hintColor,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? theme.colorScheme.primary : null,
                ),
              ),
            ),
            Text('$count', style: TextStyle(fontSize: 11.5, color: theme.hintColor)),
            if (editableGroupId != null)
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded, size: 16),
                padding: EdgeInsets.zero,
                onSelected: (action) => action == 'rename'
                    ? _promptRenameGroup(context, provider, editableGroupId, name)
                    : provider.removeGroup(editableGroupId),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'rename', child: Text('重命名')),
                  PopupMenuItem(value: 'delete', child: Text('删除分组')),
                ],
              )
            else
              const SizedBox(width: 40),
          ],
        ),
      ),
    );
  }

  /// The open group's name, above its passages.
  Widget _buildGroupHeader(BuildContext context, CustomTextProvider provider) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              provider.selectedGroupName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
            ),
          ),
          Text('${provider.visibleTexts.length} 条',
              style: TextStyle(
                  fontSize: 11.5, color: Theme.of(context).hintColor)),
          if (provider.visibleTexts.isNotEmpty) ...[
            const SizedBox(width: 4),
            SpeechControls(
              idleLabel: '播放本组',
              onStart: () => _playFrom(context, provider, 0),
            ),
          ],
        ],
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
            '「${provider.selectedGroupName}」里还没有短文，点右下角「添加」写一段',
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).hintColor),
          ),
        ),
      );
    }

    final speech = context.watch<EntrySpeechProvider>();
    final settings = context.watch<SettingsProvider>();
    final currentItemId = speech.currentUtterance?.itemId;

    if (isPaneView &&
        currentItemId != null &&
        speech.isPlaying &&
        provider.selectedId != currentItemId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (speech.isPlaying &&
            speech.currentUtterance?.itemId == currentItemId) {
          provider.select(currentItemId);
        }
      });
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: items.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 56),
      itemBuilder: (context, index) {
        final item = items[index];
        final sentences = item.utterances;
        final speakingSentence = speech.sentenceIndexFor(item.id);
        final speaking = speakingSentence != null;
        final theme = Theme.of(context);
        return ListTile(
          dense: true,
          leading: IconButton(
            icon: Icon(
                speaking ? Icons.volume_up_rounded : Icons.play_circle_outline_rounded),
            color: speaking ? theme.colorScheme.error : null,
            tooltip: speaking
                ? '停止播放'
                : '${settings.speechOrder.label}播放（从这篇开始）',
            onPressed: () {
              if (speaking) {
                speech.stop();
              } else {
                _playFrom(context, provider, index);
              }
            },
          ),
          title: Text(
            item.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: speaking ? theme.colorScheme.error : null,
            ),
          ),
          subtitle: Text(
            speaking
                ? '正在朗读 ${speakingSentence + 1}/${sentences.length}：'
                    '${speech.currentUtterance?.text ?? (speakingSentence < sentences.length ? sentences[speakingSentence] : '')}'
                : '${sentences.length} 句',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              color: speaking ? theme.colorScheme.error : null,
              fontWeight: speaking ? FontWeight.w600 : null,
            ),
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
              PopupMenuItem(value: 'group', child: Text('移到其他分组…')),
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
  Widget _buildBottomBar(BuildContext context, CustomTextProvider provider) {
    final speech = context.watch<EntrySpeechProvider>();
    final settings = context.watch<SettingsProvider>();
    final theme = Theme.of(context);
    final totalSentences =
        provider.visibleTexts.fold<int>(0, (sum, it) => sum + it.utterances.length);
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
                    : '${settings.speechOrder.label}播放 $totalSentences 句',
              ),
              onPressed: totalSentences == 0
                  ? null
                  : () {
                      if (playing) {
                        speech.stop();
                        return;
                      }
                      _playFrom(context, provider, 0);
                    },
            ),
          ),
          IconButton(
            tooltip: settings.speechOrder == PlaybackOrder.shuffle
                ? '播放顺序：随机（点按改为顺序）'
                : '播放顺序：顺序（点按改为随机）',
            icon: Icon(
              settings.speechOrder == PlaybackOrder.shuffle
                  ? Icons.shuffle_rounded
                  : Icons.format_list_numbered_rounded,
              size: 18,
            ),
            onPressed: () => settings.setSpeechOrder(
              settings.speechOrder == PlaybackOrder.shuffle
                  ? PlaybackOrder.sequential
                  : PlaybackOrder.shuffle,
            ),
          ),
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
      MaterialPageRoute<void>(builder: (_) => CustomDetailView(itemId: id)),
    );
  }

  void _playFrom(
    BuildContext context,
    CustomTextProvider provider,
    int startIndex,
  ) {
    final items = provider.visibleTexts;
    if (startIndex < 0 || startIndex >= items.length) return;
    provider.select(items[startIndex].id);

    final settings = context.read<SettingsProvider>();
    final queue = provider.queueFrom(startIndex, settings.speechOrder);
    _playQueue(context, queue);
  }

  void _playQueue(BuildContext context, List<EntryUtterance> queue) {
    final settings = context.read<SettingsProvider>();
    context.read<EntrySpeechProvider>().playAll(
          queue,
          rate: settings.speechRate,
          gap: settings.sentenceGap,
          accent: accentForLanguage(settings.ttsLanguage),
          loop: settings.speechLoop,
          engine: settings.speechEngine,
          volume: settings.speechVolume,
        );
  }

  Future<String?> _askName(BuildContext context, String title, String initial) async {
    final controller = TextEditingController(text: initial);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
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
            child: const Text('确定'),
          ),
        ],
      ),
    );
    controller.dispose();
    return name;
  }

  Future<void> _promptNewGroup(
    BuildContext context,
    CustomTextProvider provider,
  ) async {
    final name = await _askName(context, '新建分组', '');
    if (name == null) return;
    final group = await provider.addGroup(name);
    if (group != null) provider.selectGroup(group.id);
  }

  Future<void> _promptRenameGroup(
    BuildContext context,
    CustomTextProvider provider,
    String id,
    String current,
  ) async {
    final name = await _askName(context, '重命名分组', current);
    if (name == null) return;
    await provider.renameGroup(id, name);
  }

  Future<void> _promptGroup(
    BuildContext context,
    CustomTextProvider provider,
    CustomText item,
  ) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text('「${item.label}」移到'),
        children: [
          _groupChoice(dialogContext, '未分组', CustomTextProvider.ungroupedId,
              item.groupId == null),
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
    if (choice == CustomTextProvider.ungroupedId) {
      await provider.update(item.copyWith(clearGroup: true));
    } else {
      await provider.update(item.copyWith(groupId: choice));
    }
  }

  /// One row of the「移到」dialog; the current group carries a check mark.
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
}
