import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ai/ai_archive.dart';
import '../../core/ai/ai_config.dart';
import '../../core/ai/theme_agent.dart';
import '../../core/mdx/entry_speech.dart';
import '../../core/themes/theme_service.dart';
import '../../providers/ai_practice_provider.dart';
import '../../providers/entry_speech_provider.dart';
import '../../providers/settings_provider.dart';
import 'settings_screen.dart';

/// AI practice for one theme: example sentences for a word, a passage built
/// from the theme's own vocabulary, and everything generated so far.
///
/// The audio buttons are the same engine the dictionary uses (Piper model, or
/// the platform voice when it is missing), so a generated passage can be used
/// as listening practice.
class AiPracticeScreen extends StatefulWidget {
  const AiPracticeScreen({super.key, required this.scene});

  final ThemeScene scene;

  @override
  State<AiPracticeScreen> createState() => _AiPracticeScreenState();
}

class _AiPracticeScreenState extends State<AiPracticeScreen> {
  final TextEditingController _wordController = TextEditingController();
  int _sentenceCount = 5;
  PracticeLevel _sentenceLevel = PracticeLevel.easy;
  PracticeLevel _passageLevel = PracticeLevel.easy;

  @override
  void initState() {
    super.initState();
    context.read<AiPracticeProvider>().openScene(widget.scene.id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AiPracticeProvider>().loadArchive();
    });
  }

  @override
  void dispose() {
    _wordController.dispose();
    super.dispose();
  }

  AiConfig _config(SettingsProvider settings) => AiConfig(
    baseUrl: settings.aiBaseUrl,
    apiKey: settings.aiApiKey,
    model: settings.aiModel,
  );

  void _speak(String text) {
    final settings = context.read<SettingsProvider>();
    context.read<EntrySpeechProvider>().speakText(
      text,
      rate: settings.speechRate,
      accent: accentForLanguage(settings.ttsLanguage),
    );
  }

  void _speakAll(List<GeneratedSentence> sentences) {
    final settings = context.read<SettingsProvider>();
    context.read<EntrySpeechProvider>().playAll(
      [
        for (final sentence in sentences)
          EntryUtterance(text: sentence.text, isPhrase: false),
      ],
      rate: settings.speechRate,
      gap: settings.sentenceGap,
      accent: accentForLanguage(settings.ttsLanguage),
    );
  }

  Future<void> _generateSentences(AiConfig config) async {
    final word = _wordController.text.trim();
    if (word.isEmpty) return;
    await context.read<AiPracticeProvider>().generateSentences(
      config: config,
      sceneId: widget.scene.id,
      sceneLabel: widget.scene.label,
      word: word,
      count: _sentenceCount,
      level: _sentenceLevel,
    );
  }

  Future<void> _generatePassage(AiConfig config) async {
    await context.read<AiPracticeProvider>().generatePassage(
      config: config,
      sceneId: widget.scene.id,
      sceneLabel: widget.scene.label,
      sceneHint: widget.scene.hint,
      sceneWords: widget.scene.words,
      level: _passageLevel,
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AiPracticeProvider>();
    final settings = context.watch<SettingsProvider>();
    final config = _config(settings);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'AI 练习 · ${widget.scene.label}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
        children: [
          if (!config.isConfigured) _buildConfigHint(context),
          if (provider.error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                provider.error!,
                style: TextStyle(
                  fontSize: 12.5,
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          if (provider.isGenerating)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          _buildSentenceCard(context, provider, config),
          const SizedBox(height: 14),
          _buildPassageCard(context, provider, config),
          const SizedBox(height: 14),
          _buildArchive(context, provider),
        ],
      ),
    );
  }

  Widget _buildConfigHint(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          children: [
            Icon(Icons.key_rounded, size: 20, color: theme.hintColor),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                '还没有配置 AI 接口。生成句子和短文需要一个兼容 OpenAI 的接口。',
                style: TextStyle(fontSize: 12.5, height: 1.4),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
              ),
              child: const Text('去设置'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSentenceCard(
    BuildContext context,
    AiPracticeProvider provider,
    AiConfig config,
  ) {
    final theme = Theme.of(context);
    final speech = context.watch<EntrySpeechProvider>();
    final quickPicks = widget.scene.words.take(6).toList();

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.short_text_rounded, size: 18),
                const SizedBox(width: 6),
                Text(
                  '造句',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _wordController,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                hintText:
                    '输入要造句的单词，如 ${quickPicks.isEmpty ? 'apple' : quickPicks.first}',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            if (quickPicks.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final word in quickPicks)
                    ActionChip(
                      label: Text(word, style: const TextStyle(fontSize: 12)),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setState(() {
                        _wordController.text = word;
                      }),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                _levelSelector(
                  _sentenceLevel,
                  (level) => setState(() => _sentenceLevel = level),
                ),
                const Spacer(),
                SegmentedButton<int>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  segments: const [
                    ButtonSegment(value: 3, label: Text('3 句')),
                    ButtonSegment(value: 5, label: Text('5 句')),
                    ButtonSegment(value: 8, label: Text('8 句')),
                  ],
                  selected: {_sentenceCount},
                  onSelectionChanged: (selection) =>
                      setState(() => _sentenceCount = selection.first),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: provider.isGenerating
                    ? null
                    : () => _generateSentences(config),
                icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                label: const Text('生成句子'),
              ),
            ),
            if (provider.sentences.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    '${provider.sentencesWord}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => speech.isPlaying
                        ? speech.stop()
                        : _speakAll(provider.sentences),
                    icon: Icon(
                      speech.isPlaying
                          ? Icons.stop_rounded
                          : Icons.playlist_play_rounded,
                      size: 18,
                    ),
                    label: Text(speech.isPlaying ? '停止' : '全部朗读'),
                  ),
                ],
              ),
              for (var i = 0; i < provider.sentences.length; i++)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${i + 1}.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: theme.hintColor,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              provider.sentences[i].text,
                              style: const TextStyle(
                                fontSize: 13.5,
                                height: 1.45,
                              ),
                            ),
                            if (provider.sentences[i].translation != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  provider.sentences[i].translation!,
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 1.4,
                                    color: theme.hintColor,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.volume_up_rounded, size: 18),
                        tooltip: '朗读这一句',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _speak(provider.sentences[i].text),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPassageCard(
    BuildContext context,
    AiPracticeProvider provider,
    AiConfig config,
  ) {
    final theme = Theme.of(context);
    final speech = context.watch<EntrySpeechProvider>();
    final passage = provider.passage;

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.menu_book_rounded, size: 18),
                const SizedBox(width: 6),
                Text(
                  '主题短文',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const Spacer(),
                _levelSelector(
                  _passageLevel,
                  (level) => setState(() => _passageLevel = level),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '易 = 主题里最高频的词，句子短；难 = 最低频的词，句子结构更复杂。',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.4,
                color: theme.hintColor,
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: provider.isGenerating
                    ? null
                    : () => _generatePassage(config),
                icon: const Icon(Icons.auto_stories_rounded, size: 18),
                label: const Text('生成短文'),
              ),
            ),
            if (passage != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      passage.title,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      speech.isPlaying
                          ? Icons.stop_rounded
                          : Icons.volume_up_rounded,
                      size: 20,
                    ),
                    tooltip: speech.isPlaying ? '停止' : '整篇朗读',
                    onPressed: () =>
                        speech.isPlaying ? speech.stop() : _speak(passage.text),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              SelectableText(
                passage.text,
                style: const TextStyle(fontSize: 13.5, height: 1.6),
              ),
              if (provider.passageWords.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  '本篇要求的主题词',
                  style: TextStyle(fontSize: 11.5, color: theme.hintColor),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final word in provider.passageWords)
                      Chip(
                        label: Text(
                          word,
                          style: const TextStyle(fontSize: 11.5),
                        ),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildArchive(BuildContext context, AiPracticeProvider provider) {
    final theme = Theme.of(context);
    final items = provider.archiveFor(widget.scene.id);

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.inventory_2_outlined, size: 18),
                const SizedBox(width: 6),
                Text(
                  '归档',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${items.length}',
                  style: TextStyle(fontSize: 11.5, color: theme.hintColor),
                ),
              ],
            ),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  '这个主题还没有生成记录。',
                  style: TextStyle(fontSize: 12.5, color: theme.hintColor),
                ),
              ),
            for (final item in items)
              _buildArchiveTile(context, provider, item),
          ],
        ),
      ),
    );
  }

  Widget _buildArchiveTile(
    BuildContext context,
    AiPracticeProvider provider,
    AiArchiveItem item,
  ) {
    final theme = Theme.of(context);
    final title = item.kind == AiItemKind.passage
        ? item.title
        : '${item.word ?? ''} · ${item.lines.length} 句';
    final subtitle =
        '${item.kind == AiItemKind.passage ? '短文' : '造句'} · ${item.level.label} · '
        '${_formatDate(item.created)}';

    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      shape: const Border(),
      collapsedShape: const Border(),
      title: Text(title, style: const TextStyle(fontSize: 13)),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 11.5, color: theme.hintColor),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.volume_up_rounded, size: 18),
            tooltip: '朗读',
            visualDensity: VisualDensity.compact,
            onPressed: () => _speak(
              item.kind == AiItemKind.passage
                  ? item.text
                  : [for (final line in item.lines) line.text].join(' '),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            tooltip: '删除',
            visualDensity: VisualDensity.compact,
            onPressed: () => provider.delete(item.id),
          ),
        ],
      ),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: item.kind == AiItemKind.passage
              ? SelectableText(
                  item.text,
                  style: const TextStyle(fontSize: 13, height: 1.55),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final line in item.lines)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: SelectableText(
                          line.text,
                          style: const TextStyle(fontSize: 13, height: 1.45),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _levelSelector(
    PracticeLevel value,
    ValueChanged<PracticeLevel> onChanged,
  ) {
    return SegmentedButton<PracticeLevel>(
      showSelectedIcon: false,
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      segments: [
        for (final level in PracticeLevel.values)
          ButtonSegment(value: level, label: Text(level.label)),
      ],
      selected: {value},
      onSelectionChanged: (selection) => onChanged(selection.first),
    );
  }

  static String _formatDate(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}';
  }
}
