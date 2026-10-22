import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/custom/custom_text.dart';
import '../../core/mdx/entry_speech.dart';
import '../../providers/custom_text_provider.dart';
import '../../providers/entry_speech_provider.dart';
import '../../providers/settings_provider.dart';

/// Write or edit one 短语 / 短文, and play it.
///
/// On the desktop layout this is the right pane and follows the selection; on a
/// phone it is pushed as its own page (new entry when [itemId] is null).
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
  late CustomTextKind _kind;
  String? _groupId;

  @override
  void initState() {
    super.initState();
    final item = _storedItem;
    _title = TextEditingController(text: item?.title ?? '');
    _body = TextEditingController(text: item?.body ?? '');
    _kind = item?.kind ?? context.read<CustomTextProvider>().kind;
    _groupId = item?.groupId;
  }

  @override
  void didUpdateWidget(CustomDetailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The desktop pane is rebuilt with a new key per selection, so this only
    // fires when the same page is reused (it isn't); kept for safety.
    if (oldWidget.itemId != widget.itemId) {
      final item = _storedItem;
      _title.text = item?.title ?? '';
      _body.text = item?.body ?? '';
      _kind = item?.kind ?? _kind;
      _groupId = item?.groupId;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
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
    final speech = context.watch<EntrySpeechProvider>();
    final theme = Theme.of(context);
    final item = _storedItem;
    final isNew = item == null;

    final content = SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                isNew ? Icons.add_circle_outline_rounded : Icons.edit_note_rounded,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                isNew ? '新增${_kind.label}' : '编辑${_kind.label}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const Spacer(),
              SegmentedButton<CustomTextKind>(
                segments: [
                  for (final kind in CustomTextKind.values)
                    ButtonSegment(
                      value: kind,
                      label: Text(kind.label,
                          style: const TextStyle(fontSize: 11.5)),
                    ),
                ],
                selected: {_kind},
                showSelectedIcon: false,
                onSelectionChanged: (selection) =>
                    setState(() => _kind = selection.first),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _title,
            decoration: InputDecoration(
              labelText: '标题（可选）',
              hintText: _kind == CustomTextKind.phrase ? '例如：on the house' : '例如：My morning routine',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _body,
            minLines: _kind == CustomTextKind.passage ? 8 : 3,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            decoration: InputDecoration(
              labelText: _kind == CustomTextKind.phrase ? '短语内容' : '短文内容',
              hintText: _kind == CustomTextKind.phrase
                  ? '要朗读的文字'
                  : '一段文字；句号/问号/叹号或换行处会分成句子，逐句朗读',
              alignLabelWithHint: true,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          _buildGroupRow(context, provider),
          const SizedBox(height: 16),
          Row(
            children: [
              FilledButton.icon(
                icon: const Icon(Icons.save_rounded, size: 18),
                label: const Text('保存'),
                onPressed: () => _save(context, provider, item),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: Icon(
                    speech.isPlaying ? Icons.stop_rounded : Icons.volume_up_rounded,
                    size: 18,
                  ),
                  label: Text(speech.isPlaying ? '停止' : '播放'),
                  onPressed: () => _togglePlay(context, item),
                ),
              ),
              if (!isNew) ...[
                const SizedBox(width: 8),
                IconButton(
                  tooltip: '删除',
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: () => _delete(context, provider, item),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _kind == CustomTextKind.phrase
                ? '短语整句朗读；短文在句号、问号、叹号或换行处断句，逐句朗读。'
                : '短文在句号、问号、叹号或换行处断句，逐句朗读，句间停顿取设置里的间隔。',
            style: TextStyle(fontSize: 12, color: theme.hintColor),
          ),
        ],
      ),
    );

    if (widget.isPaneView || !isNew) return content;
    return content;
  }

  Widget _buildGroupRow(BuildContext context, CustomTextProvider provider) {
    return Row(
      children: [
        const Icon(Icons.folder_outlined, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButtonFormField<String?>(
            initialValue: _groupId,
            decoration: const InputDecoration(
              labelText: '分组',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('未分组')),
              for (final group in provider.groups)
                DropdownMenuItem<String?>(value: group.id, child: Text(group.name)),
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
            if (group != null && mounted) setState(() => _groupId = group.id);
          },
        ),
      ],
    );
  }

  Future<void> _save(
    BuildContext context,
    CustomTextProvider provider,
    CustomText? item,
  ) async {
    final body = _body.text.trim();
    if (body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('先写点内容再保存'), duration: Duration(seconds: 1)),
      );
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    if (item == null) {
      final added = await provider.add(
        kind: _kind,
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
          kind: _kind,
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

  Future<void> _delete(
    BuildContext context,
    CustomTextProvider provider,
    CustomText item,
  ) async {
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
    if (context.mounted && !widget.isPaneView) Navigator.of(context).maybePop();
  }

  void _togglePlay(BuildContext context, CustomText? item) {
    final speech = context.read<EntrySpeechProvider>();
    if (speech.isPlaying) {
      speech.stop();
      return;
    }
    final body = _body.text.trim();
    final lines = _kind == CustomTextKind.phrase
        ? (body.isEmpty ? const <String>[] : [body])
        : splitSentences(body);
    if (lines.isEmpty) return;
    final settings = context.read<SettingsProvider>();
    speech.playAll(
      [
        for (final line in lines)
          EntryUtterance(text: line, isPhrase: _kind == CustomTextKind.phrase),
      ],
      rate: settings.speechRate,
      gap: settings.sentenceGap,
      accent: accentForLanguage(settings.ttsLanguage),
    );
  }
}
