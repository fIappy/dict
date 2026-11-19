import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/custom/custom_text.dart';
import '../../core/mdx/entry_speech.dart';
import '../../providers/custom_text_provider.dart';
import '../../providers/entry_speech_provider.dart';
import '../../core/custom/playback_order.dart';
import '../../core/ui/ui_memory.dart';
import '../../providers/settings_provider.dart';
import 'custom_detail_view.dart';
import '../widgets/speech_controls.dart';

/// The 自定义短文 section, classified by **group**: the top of the pane lists
/// the groups (未分组 included, because every entry belongs somewhere), and the
/// passages of the selected group sit below.
class CustomScreen extends StatefulWidget {
  final bool isPaneView;

  const CustomScreen({super.key, this.isPaneView = false});

  @override
  State<CustomScreen> createState() => _CustomScreenState();
}

class _CustomScreenState extends State<CustomScreen> {
  /// The group panel starts at the height it always had, and the splitter is how
  /// the reader gives it more or less room.
  static const double _defaultGroupHeight = 190;
  static const double _minGroupHeight = 116;

  /// Below this the passage list would have nowhere to go.
  static const double _minListHeight = 160;

  /// The height lives in a notifier so a drag only re-lays out the two panes.
  /// A `setState` per pointer move rebuilt both lists — and every row of the
  /// passage list re-splits its body — which is what made dragging feel sticky.
  final ValueNotifier<double> _groupHeight =
      ValueNotifier<double>(_defaultGroupHeight);

  /// Sentences per entry, keyed by id and body so an edit misses the cache.
  final Map<String, List<String>> _sentenceCache = {};

  /// The splitter's own state lives in [_SplitterHandle]: rebuilding this page
  /// for a hover would rebuild both lists, which is what made dragging stutter.

  @override
  void initState() {
    super.initState();
    _restoreHeight();
  }

  @override
  void dispose() {
    _groupHeight.dispose();
    super.dispose();
  }

  Future<void> _restoreHeight() async {
    final saved = await UiMemory.readDouble(UiMemory.customGroupHeight);
    if (!mounted || saved == null) return;
    _groupHeight.value = saved;
  }

  void _rememberHeight() => UiMemory.writeDouble(
        UiMemory.customGroupHeight,
        _groupHeight.value,
      );


  List<String> _sentencesOf(CustomText item) {
    final key = '${item.id}|${item.body.hashCode}';
    final cached = _sentenceCache[key];
    if (cached != null) return cached;
    if (_sentenceCache.length > 600) _sentenceCache.clear();
    return _sentenceCache[key] = item.utterances;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CustomTextProvider>();

    return Scaffold(
      appBar: widget.isPaneView
          ? null
          : AppBar(
              title: const Text('自定义短文',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final maxGroupHeight = (constraints.maxHeight -
                  _minListHeight -
                  _minGroupHeight)
              .clamp(_minGroupHeight, 720.0);
          // Built once per page build and handed to the resizable pane as a
          // child: the drag changes a height, it does not rebuild the lists.
          final built = Column(
            children: [
              _ResizablePane(
                height: _groupHeight,
                min: _minGroupHeight,
                max: maxGroupHeight,
                child: _buildGroupSection(context, provider),
              ),
              _buildSplitter(context, maxGroupHeight),
              _buildGroupHeader(context, provider),
              Expanded(child: _buildList(context, provider)),
              _buildBottomBar(context, provider),
            ],
          );
          return built;
        },
      ),
    );
  }

  /// The drag handle between the group list and the passages.
  ///
  /// Dragging up gives the passages more room, dragging down gives the groups
  /// more; a double click puts the default back. The height survives restarts.
  Widget _buildSplitter(BuildContext context, double maxGroupHeight) {
    return _SplitterHandle(
      height: _groupHeight,
      min: _minGroupHeight,
      max: maxGroupHeight,
      onDone: _rememberHeight,
      onReset: () {
        _groupHeight.value = _defaultGroupHeight;
        _rememberHeight();
      },
    );
  }

  /// The top level: one row per group, with how many entries it holds.
  Widget _buildGroupSection(BuildContext context, CustomTextProvider provider) {
    final theme = Theme.of(context);
    final groups = provider.groups;

    return Container(
      key: const ValueKey('custom-group-section'),
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
      child: Column(
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
          Expanded(
            child: ListView(
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
            '还没有短文',
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).hintColor),
          ),
        ),
      );
    }

    final speech = context.watch<EntrySpeechProvider>();
    final settings = context.watch<SettingsProvider>();
    final currentItemId = speech.currentUtterance?.itemId;

    if (widget.isPaneView &&
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
      key: const ValueKey('custom-passage-list'),
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: items.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 56),
      itemBuilder: (context, index) {
        final item = items[index];
        final sentences = _sentencesOf(item);
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
                  if (!widget.isPaneView) _openDetail(context, provider, item.id);
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
            if (!widget.isPaneView) _openDetail(context, provider, item.id);
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
    if (widget.isPaneView) return; // The desktop detail pane follows the selection.
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

/// A fixed-height box whose height follows [height] without rebuilding [child].
class _ResizablePane extends StatelessWidget {
  const _ResizablePane({
    required this.height,
    required this.min,
    required this.max,
    required this.child,
  });

  final ValueListenable<double> height;
  final double min;
  final double max;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: height,
      child: child,
      builder: (context, value, child) => SizedBox(
        height: value.clamp(min, max),
        child: child,
      ),
    );
  }
}

/// The drag handle between the group list and the passages.
///
/// Dragging up gives the passages more room, dragging down gives the groups
/// more; a double click puts the default back. It owns its hover/drag state so
/// a hover never rebuilds the page, and while a drag is in flight a hover exit
/// is ignored: the pointer drifting a pixel off a handle that is moving with it
/// must not be read as "left the handle".
class _SplitterHandle extends StatefulWidget {
  const _SplitterHandle({
    required this.height,
    required this.min,
    required this.max,
    required this.onDone,
    required this.onReset,
  });

  final ValueNotifier<double> height;
  final double min;
  final double max;
  final VoidCallback onDone;
  final VoidCallback onReset;

  @override
  State<_SplitterHandle> createState() => _SplitterHandleState();
}

class _SplitterHandleState extends State<_SplitterHandle> {
  bool _hovering = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = _hovering || _dragging;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeRow,
      onEnter: (_) {
        if (_hovering) return;
        setState(() => _hovering = true);
      },
      onExit: (_) {
        if (_dragging || !_hovering) return;
        setState(() => _hovering = false);
      },
      child: GestureDetector(
        key: const ValueKey('custom-group-splitter'),
        behavior: HitTestBehavior.opaque,
        onVerticalDragStart: (_) {
          if (!_dragging) setState(() => _dragging = true);
        },
        onVerticalDragUpdate: (details) {
          widget.height.value = (widget.height.value + details.delta.dy)
              .clamp(widget.min, widget.max);
        },
        onVerticalDragEnd: (_) {
          if (_dragging) setState(() => _dragging = false);
          widget.onDone();
        },
        onVerticalDragCancel: () {
          if (_dragging) setState(() => _dragging = false);
          widget.onDone();
        },
        onDoubleTap: widget.onReset,
        child: SizedBox(
          height: 10,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              height: active ? 4 : 2,
              width: 52,
              decoration: BoxDecoration(
                color: active
                    ? theme.colorScheme.primary
                    : theme.dividerColor.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
