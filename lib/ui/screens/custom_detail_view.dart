import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/custom/custom_text.dart';
import '../../core/mdx/entry_speech.dart';
import '../../providers/custom_text_provider.dart';
import '../../providers/entry_speech_provider.dart';
import '../../providers/settings_provider.dart';
import '../widgets/speakable_selection.dart';
import '../widgets/annotated_text.dart';
import '../widgets/speech_controls.dart';

/// Write or edit one 短文, and play it.
///
/// On the desktop layout this is the right pane and follows the selection; on a
/// phone it is pushed as its own page (a new entry when [itemId] is null).
class CustomDetailView extends StatefulWidget {
  final String? itemId;
  final bool isPaneView;

  const CustomDetailView({super.key, this.itemId, this.isPaneView = false});

  @override
  State<CustomDetailView> createState() => _CustomDetailViewState();
}

class _CustomDetailViewState extends State<CustomDetailView> {
  late TextEditingController _title;
  late TextEditingController _body;

  /// Owns the body field's internal scrollbar: the passage scrolls, the
  /// controls below it do not move.
  final ScrollController _bodyScroll = ScrollController();
  String? _groupId;

  @override
  void initState() {
    super.initState();
    final item = _storedItem;
    final provider = context.read<CustomTextProvider>();
    _title = TextEditingController(text: item?.title ?? '');
    _body = TextEditingController(text: item?.body ?? '');
    // A new entry lands in the group that is open, so writing several passages
    // for one group does not need the dropdown every time.
    _groupId =
        item?.groupId ??
        (provider.selectedGroupId == CustomTextProvider.ungroupedId
            ? null
            : provider.selectedGroupId);
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _bodyScroll.dispose();
    super.dispose();
  }

  CustomText? get _storedItem {
    final id = widget.itemId;
    if (id == null) return null;
    for (final item in context.read<CustomTextProvider>().allTexts) {
      if (item.id == id) return item;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CustomTextProvider>();
    final theme = Theme.of(context);
    final item = _storedItem;
    final isNew = item == null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                isNew
                    ? Icons.add_circle_outline_rounded
                    : Icons.edit_note_rounded,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                isNew ? '新增短文' : '编辑短文',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _title,
            contextMenuBuilder: speakableEditableMenu,
            decoration: const InputDecoration(
              labelText: '标题（可选）',
              hintText: '例如：My morning routine',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(child: _buildBody(context)),
          const SizedBox(height: 12),
          _buildGroupRow(context, provider),
          const SizedBox(height: 16),
          Row(
            children: [
              FilledButton.icon(
                icon: const Icon(Icons.save_rounded, size: 18),
                label: const Text('保存'),
                onPressed: () => _save(provider, item),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SpeechControls(
                    labels: true,
                    idleLabel: '播放全文',
                    onStart: _startPlay,
                  ),
                ),
              ),
              if (!isNew)
                IconButton(
                  tooltip: '删除',
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: () => _delete(provider, item),
                ),
            ],
          ),
          const SizedBox(height: 8),
          _buildSpeakingLine(context),
          const SizedBox(height: 6),
          Text(
            '在句号、问号、叹号或换行处断句，逐句朗读，句间停顿取设置里的间隔。',
            style: TextStyle(fontSize: 12, color: theme.hintColor),
          ),
        ],
      ),
    );
  }

  /// The body box.
  ///
  /// A TextField cannot colour part of its text, so while this passage is
  /// sounding the box becomes a reader that marks the sentence being read in
  /// red; the moment playback stops the editable field is back.
  ///
  /// One scrollbar either way. A multiline [TextField] always gets the
  /// framework's bar — [EditableText] calls `copyWith(scrollbars: true)` on
  /// whatever behavior is in scope, so turning it off from outside does nothing
  /// — which is why the passage is wrapped in [_NoFieldScrollbar] and draws its
  /// own always-visible bar instead.
  Widget _buildBody(BuildContext context) {
    final speech = context.watch<EntrySpeechProvider>();
    final lines = splitSentences(_body.text);
    final speaking = speech.isReading(lines) ? speech.currentIndex : null;

    if (speaking != null) {
      final theme = Theme.of(context);
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outline),
          borderRadius: BorderRadius.circular(4),
        ),
        child: ScrollConfiguration(
          behavior: const ScrollBehavior(),
          child: SingleChildScrollView(
            child: AnnotatedText(
              _body.text,
              themeWords: const {},
              speakingIndex: speaking,
              style: const TextStyle(fontSize: 15, height: 1.6),
            ),
          ),
        ),
      );
    }

    return ScrollConfiguration(
      behavior: const _NoFieldScrollbar(),
      child: Scrollbar(
        controller: _bodyScroll,
        thumbVisibility: true,
        child: Listener(
          onPointerDown: (event) {
            if (event.buttons & kSecondaryMouseButton != 0) {
              rememberSecondaryTap(event.position);
            }
          },
          child: TextField(
            controller: _body,
            contextMenuBuilder: speakableEditableMenu,
            scrollController: _bodyScroll,
            expands: true,
            minLines: null,
            maxLines: null,
            textAlignVertical: TextAlignVertical.top,
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(
              labelText: '短文内容',
              hintText: '一段文字；句号/问号/叹号或换行处会分成句子，逐句朗读',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
        ),
      ),
    );
  }

  /// The sentence sounding right now, in red — the same mark the lists use.
  Widget _buildSpeakingLine(BuildContext context) {
    final speech = context.watch<EntrySpeechProvider>();
    final lines = splitSentences(_body.text);
    final index = speech.isReading(lines) ? speech.currentIndex : null;
    if (index == null || index >= lines.length) return const SizedBox.shrink();
    return Text(
      '正在朗读 ${index + 1}/${lines.length}：${lines[index]}',
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.error,
      ),
    );
  }

  Widget _buildGroupRow(BuildContext context, CustomTextProvider provider) {
    return Row(
      children: [
        const Icon(Icons.folder_outlined, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButtonFormField<String?>(
            initialValue: _groupId,
            // A long group name must not widen the field or overlap the plus
            // button next to it.
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: '分组',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text(
                  '未分组',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              for (final group in provider.groups)
                DropdownMenuItem<String?>(
                  value: group.id,
                  child: Text(
                    group.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (value) => setState(() => _groupId = value),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: '新建分组',
          icon: const Icon(Icons.create_new_folder_outlined),
          onPressed: () async {
            final controller = TextEditingController();
            final name = await showDialog<String>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: const Text('新建分组'),
                content: TextField(
                  controller: controller,
                  autofocus: true,
                  onSubmitted: (value) =>
                      Navigator.of(dialogContext).pop(value),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    onPressed: () =>
                        Navigator.of(dialogContext).pop(controller.text),
                    child: const Text('创建'),
                  ),
                ],
              ),
            );
            controller.dispose();
            if (name == null) return;
            final group = await provider.addGroup(name);
            if (group != null && mounted) setState(() => _groupId = group.id);
          },
        ),
      ],
    );
  }

  Future<void> _save(CustomTextProvider provider, CustomText? item) async {
    final body = _body.text.trim();
    if (body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('先写点内容再保存'),
          duration: Duration(seconds: 1),
        ),
      );
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    if (item == null) {
      final added = await provider.add(
        body: body,
        title: _title.text.trim(),
        groupId: _groupId,
      );
      provider.select(added.id);
      messenger.showSnackBar(
        const SnackBar(content: Text('已添加'), duration: Duration(seconds: 1)),
      );
      if (!mounted) return;
      if (!widget.isPaneView) navigator.maybePop();
    } else {
      await provider.update(
        item.copyWith(
          body: body,
          title: _title.text.trim(),
          groupId: _groupId,
          clearGroup: _groupId == null,
        ),
      );
      messenger.showSnackBar(
        const SnackBar(content: Text('已保存'), duration: Duration(seconds: 1)),
      );
    }
  }

  Future<void> _delete(CustomTextProvider provider, CustomText item) async {
    final navigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除这一条？'),
        content: Text(item.label),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await provider.remove(item.id);
    if (mounted && !widget.isPaneView) navigator.maybePop();
  }

  void _startPlay() {
    final speech = context.read<EntrySpeechProvider>();
    final lines = splitSentences(_body.text);
    if (lines.isEmpty) return;
    final settings = context.read<SettingsProvider>();
    speech.playAll(
      [for (final line in lines) EntryUtterance(text: line, isPhrase: false)],
      rate: settings.speechRate,
      gap: settings.sentenceGap,
      accent: accentForLanguage(settings.ttsLanguage),
      loop: settings.speechLoop,
      engine: settings.speechEngine,
      volume: settings.speechVolume,
    );
  }
}

/// Declines the framework scrollbar for its subtree.
///
/// [EditableText] forces `scrollbars: true` on the behavior it hands to its own
/// scrollable, so `ScrollConfiguration.of(context).copyWith(scrollbars: false)`
/// cannot suppress it. Overriding [buildScrollbar] can: the forced copy only
/// adds the flag and delegates the drawing back here.
class _NoFieldScrollbar extends MaterialScrollBehavior {
  const _NoFieldScrollbar();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) =>
      child;
}
