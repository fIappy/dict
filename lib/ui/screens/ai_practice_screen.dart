import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ai/ai_archive.dart';
import '../../core/ai/ai_config.dart';
import '../../core/ai/passage_style.dart';
import '../../core/ai/theme_agent.dart';
import '../../core/ai/vocabulary_band.dart';
import '../../core/mdx/entry_speech.dart';
import '../../core/themes/theme_service.dart';
import '../widgets/annotated_text.dart';
import '../../providers/ai_practice_provider.dart';
import '../../providers/entry_speech_provider.dart';
import '../../providers/settings_provider.dart';
import 'settings_screen.dart';
import '../widgets/speakable_selection.dart';
import '../../core/custom/custom_text.dart';
import '../widgets/speech_controls.dart';

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
  final TextEditingController _lengthController = TextEditingController();
  final TextEditingController _extraController = TextEditingController();
  int _sentenceCount = 5;
  final ScrollController _scroll = ScrollController();
  PracticeLevel _sentenceLevel = PracticeLevel.easy;
  PracticeLevel _passageLevel = PracticeLevel.easy;

  /// Passage knobs. Length and style live in settings; the frequency band is
  /// per theme, so it stays here and resets when another theme is opened.
  int _passageLength = 140;
  PassageStyle _passageStyle = PassageStyle.descriptive;
  int? _bandFrom;
  int? _bandTo;
  bool _seeded = false;

  @override
  void initState() {
    super.initState();
    // Both calls notify, and initState runs inside the build phase — they wait
    // for the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<AiPracticeProvider>();
      provider.openScene(widget.scene.id);
      provider.loadArchive();
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _wordController.dispose();
    _lengthController.dispose();
    _extraController.dispose();
    super.dispose();
  }

  AiConfig _config(SettingsProvider settings) => AiConfig(
    baseUrl: settings.aiBaseUrl,
    apiKey: settings.aiApiKey,
    model: settings.aiModel,
  );

  void _speak(String text) {
    final lines = splitSentences(text);
    if (lines.isEmpty) return;
    final settings = context.read<SettingsProvider>();
    context.read<EntrySpeechProvider>().playAll(
      [for (final line in lines) EntryUtterance(text: line, isPhrase: false)],
      rate: settings.speechRate,
      gap: settings.sentenceGap,
      accent: accentForLanguage(settings.ttsLanguage),
      loop: settings.speechLoop,
      engine: settings.speechEngine,
      volume: settings.speechVolume,
    );
  }

  /// Which sentence of [text] is sounding right now, if it is this passage.
  int? _speakingPassageSentence(AiPracticeProvider provider, String text) {
    final speech = context.watch<EntrySpeechProvider>();
    final lines = splitSentences(text);
    if (!speech.isReading(lines)) return null;
    return speech.currentIndex;
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
      loop: settings.speechLoop,
      engine: settings.speechEngine,
      volume: settings.speechVolume,
    );
  }

  Future<void> _generateSentences(AiConfig config) async {
    final word = _wordController.text.trim();
    if (word.isEmpty) {
      // Doing nothing at all reads as a broken button.
      final provider = context.read<AiPracticeProvider>();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('先输入一个要造句的单词（也可以点上面的候选词）'),
          duration: Duration(seconds: 2),
        ),
      );
      provider.clearError();
      return;
    }
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
    // The field is the truth: typing 1000 and going straight to the button
    // used to keep the old value, because a mouse click does not take focus.
    final typed = int.tryParse(_lengthController.text.trim());
    if (typed != null && typed != _passageLength) {
      _applyPassageLength(typed);
    }
    final provider = context.read<AiPracticeProvider>();
    final ranked = provider.rankedWordsFor(widget.scene.id, widget.scene.words);
    final total = ranked.length;
    if (total == 0) return;
    final from = (_bandFrom ?? 1).clamp(1, total);
    final to = (_bandTo ?? (total < _defaultBand ? total : _defaultBand))
        .clamp(from, total);
    final length = _passageLength;
    final words = wordsInBand(
      ranked,
      from: from,
      to: to,
      length: length,
    );
    await provider.generatePassage(
      config: config,
      sceneId: widget.scene.id,
      sceneLabel: widget.scene.label,
      sceneHint: widget.scene.hint,
      requiredWords: words,
      level: _passageLevel,
      length: length,
      style: _passageStyle,
      wordsNote:
          'These come from theme ranks $from-$to of $total by frequency; the '
          'rest of the theme is not required.',
      extra: _extraController.text,
    );
  }

  /// How many of a theme's most frequent words a passage asks for when the
  /// reader has not narrowed the band yet.
  static const int _defaultBand = 60;

  int get _sceneWordCount => widget.scene.words.length;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AiPracticeProvider>();
    final settings = context.watch<SettingsProvider>();
    final config = _config(settings);
    final theme = Theme.of(context);
    if (!_seeded) {
      // First frame only: later edits own these values, and the settings store
      // is written back on change.
      _seeded = true;
      _passageLength = settings.passageLength;
      _passageStyle = settings.passageStyle;
      _lengthController.text = '$_passageLength';
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'AI 练习 · ${widget.scene.label}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        controller: _scroll,
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
          if (provider.archiveSource != null) _buildArchiveSource(context, provider),
          _buildSentenceCard(context, provider, config),
          const SizedBox(height: 14),
          _buildPassageCard(context, provider, config),
          if (provider.reasoning != null) ...[
            const SizedBox(height: 14),
            _buildReasoningCard(context, provider),
          ],
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
    final quickPicks = widget.scene.words.take(6).toList();
    final sceneWords = widget.scene.words.toSet();
    final busySentences =
        provider.isGenerating && provider.running == AiRunKind.sentences;

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
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _levelSelector(
                  _sentenceLevel,
                  (level) => setState(() => _sentenceLevel = level),
                ),
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
                icon: busySentences
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome_rounded, size: 18),
                label: Text(busySentences ? '生成中…' : '生成句子'),
              ),
            ),
            if (provider.sentences.isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildMarkLegend(context),
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
                  SpeechControls(
                    labels: true,
                    idleLabel: '全部朗读',
                    onStart: () => _speakAll(provider.sentences),
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
                            AnnotatedText(
                              provider.sentences[i].text,
                              themeWords: sceneWords,
                              phrases: provider.sentences[i].phrases,
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
    final passage = provider.passage;
    final sceneWords = widget.scene.words.toSet();
    final busyPassage =
        provider.isGenerating && provider.running == AiRunKind.passage;

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
              '难度控制句型与内容深度（五档）；必须出现的词由下面的词频区间决定。',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.4,
                color: theme.hintColor,
              ),
            ),
            const SizedBox(height: 8),
            _buildLengthRow(context, provider),
            const SizedBox(height: 6),
            _buildStyleChips(context),
            const SizedBox(height: 2),
            _buildBandAndExtra(context, provider),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: provider.isGenerating
                    ? null
                    : () => _generatePassage(config),
                icon: busyPassage
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_stories_rounded, size: 18),
                label: Text(busyPassage ? '生成中…' : '生成短文'),
              ),
            ),
            if (passage != null) ...[
              const SizedBox(height: 12),
              _buildMarkLegend(context),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          passage.title,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          _wordCountLine(provider, passage),
                          style: TextStyle(
                            fontSize: 11,
                            color: provider.passageShort
                                ? theme.colorScheme.error
                                : theme.hintColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SpeechControls(
                    onStart: () => _speak(passage.text),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              AnnotatedText(
                passage.text,
                themeWords: sceneWords,
                phrases: passage.phrases,
                style: const TextStyle(fontSize: 13.5, height: 1.6),
                speakingIndex: _speakingPassageSentence(provider, passage.text),
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

  /// What the model thought before answering. Collapsed by default: it is
  /// reference material, not the thing the reader came for.
  Widget _buildReasoningCard(BuildContext context, AiPracticeProvider provider) {
    final theme = Theme.of(context);
    final text = provider.reasoning!;
    return Card(
      elevation: 0,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14),
        shape: const Border(),
        collapsedShape: const Border(),
        leading: Icon(Icons.psychology_alt_rounded, size: 18, color: theme.hintColor),
        title: const Text('思考过程',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        subtitle: Text('${text.length} 字',
            style: TextStyle(fontSize: 11.5, color: theme.hintColor)),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: SpeakableText(
              text,
              style: TextStyle(
                  fontSize: 12.5, height: 1.55, color: theme.hintColor),
            ),
          ),
        ],
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
    final isPassage = item.kind == AiItemKind.passage;
    final title = isPassage ? item.title : '${item.word ?? ''} · ${item.lines.length} 句';
    final subtitle = '${isPassage ? '短文' : '造句'} · ${item.level.label} · '
        '${_formatDate(item.created)}';
    final selected = provider.archiveSource?.id == item.id;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      selected: selected,
      leading: Icon(
        isPassage ? Icons.article_outlined : Icons.short_text_rounded,
        size: 18,
        color: selected ? theme.colorScheme.primary : theme.hintColor,
      ),
      title: Text(title, style: const TextStyle(fontSize: 13)),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 11.5, color: theme.hintColor),
      ),
      onTap: () {
        provider.showArchiveItem(item);
        setState(() {
          _sentenceLevel = item.level;
          _passageLevel = item.level;
        });
        if (_scroll.hasClients) {
          _scroll.animateTo(
            0,
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOut,
          );
        }
      },
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.volume_up_rounded, size: 18),
            tooltip: '朗读',
            visualDensity: VisualDensity.compact,
            onPressed: () => _speak(
              isPassage
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
    );
  }

  /// Says where the text on the page came from, so a restored generation is
  /// not mistaken for a fresh one.
  Widget _buildArchiveSource(BuildContext context, AiPracticeProvider provider) {
    final theme = Theme.of(context);
    final item = provider.archiveSource!;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
        child: Row(
          children: [
            Icon(Icons.history_rounded, size: 18, color: theme.hintColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '来自归档 · ${item.kind == AiItemKind.passage ? '短文' : '造句'} · '
                '${item.level.label} · ${_formatDate(item.created)}',
                style: TextStyle(fontSize: 12, color: theme.hintColor),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 18),
              tooltip: '收起提示',
              visualDensity: VisualDensity.compact,
              onPressed: provider.clearSource,
            ),
          ],
        ),
      ),
    );
  }

  void _applyPassageLength(int raw) {
    final value = raw.clamp(20, 10000);
    setState(() => _passageLength = value);
    _lengthController.text = '$value';
    _lengthController.selection =
        TextSelection.collapsed(offset: _lengthController.text.length);
    context.read<SettingsProvider>().setPassageLength(value);
  }

  Widget _buildLengthRow(BuildContext context, AiPracticeProvider provider) {
    final theme = Theme.of(context);
    final total = _sceneWordCount;
    final sliderValue = _passageLength.clamp(50, 2000).toDouble();
    return Row(
      children: [
        Text('长度', style: TextStyle(fontSize: 11.5, color: theme.hintColor)),
        Expanded(
          child: Slider(
            min: 50,
            max: 2000,
            divisions: 39,
            value: sliderValue,
            label: '约 $_passageLength 词',
            onChanged: provider.isGenerating
                ? null
                : (value) => setState(() => _passageLength = value.round()),
            onChangeEnd: (value) =>
                context.read<SettingsProvider>().setPassageLength(_passageLength),
          ),
        ),
        SizedBox(
          width: 68,
          child: TextField(
            controller: _lengthController,
            enabled: !provider.isGenerating,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12.5),
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 6),
              border: OutlineInputBorder(),
            ),
            onSubmitted: (text) => _applyPassageLength(
              int.tryParse(text.trim()) ?? _passageLength,
            ),
            onTapOutside: (_) => _applyPassageLength(
              int.tryParse(_lengthController.text.trim()) ?? _passageLength,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Text('词', style: TextStyle(fontSize: 11.5, color: theme.hintColor)),
        const SizedBox(width: 6),
        Text(
          '主题共 $total 词',
          style: TextStyle(fontSize: 11, color: theme.hintColor),
        ),
      ],
    );
  }

  Widget _buildStyleChips(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 2),
          child: Text('风格',
              style: TextStyle(fontSize: 11.5, color: theme.hintColor)),
        ),
        for (final style in PassageStyle.values)
          ChoiceChip(
            label: Text(style.label, style: const TextStyle(fontSize: 11.5)),
            selected: _passageStyle == style,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onSelected: (_) {
              setState(() => _passageStyle = style);
              context.read<SettingsProvider>().setPassageStyle(style);
            },
          ),
      ],
    );
  }

  Widget _buildBandAndExtra(BuildContext context, AiPracticeProvider provider) {
    final theme = Theme.of(context);
    final ranked = provider.rankedWordsFor(widget.scene.id, widget.scene.words);
    final total = ranked.length;
    if (total == 0) return const SizedBox.shrink();

    final from = (_bandFrom ?? 1).clamp(1, total);
    final to = (_bandTo ?? (total < _defaultBand ? total : _defaultBand))
        .clamp(from, total);
    final required =
        wordsInBand(ranked, from: from, to: to, length: _passageLength);
    final bandSize = to - from + 1;
    final sampled = required.length < bandSize;
    final hasExtra = _extraController.text.trim().isNotEmpty;

    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      shape: const Border(),
      collapsedShape: const Border(),
      leading: Icon(Icons.tune_rounded, size: 18, color: theme.hintColor),
      title: const Text('词汇区间与追加要求',
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
      subtitle: Text(
        '排名 $from–$to / 共 $total · 区间 $bandSize 词 · '
        '要 ${required.length} 词${hasExtra ? ' · 有追加要求' : ''}',
        style: TextStyle(fontSize: 11, color: theme.hintColor),
      ),
      children: [
        if (total > 1)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RangeSlider(
                min: 1,
                max: total.toDouble(),
                divisions: total > 1 ? total - 1 : null,
                values: RangeValues(from.toDouble(), to.toDouble()),
                labels: RangeLabels('$from', '$to'),
                onChanged: provider.isGenerating
                    ? null
                    : (values) => setState(() {
                          _bandFrom = values.start.round();
                          _bandTo = values.end.round();
                        }),
              ),
              Text(
                '按词频从高到低排；只把这段区间里的词交给模型。',
                style: TextStyle(fontSize: 11, color: theme.hintColor),
              ),
              const SizedBox(height: 2),
              Text(
                sampled
                    ? '区间 $bandSize 个词，但 $_passageLength 词的篇幅大约只能'
                        '容纳 ${required.length} 个必需词（每 10 词 1 个），'
                        '已从区间里等距抽取；想要更多就往长的方向调。'
                    : '区间内 ${required.length} 个词全部要求出现。',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.4,
                  color: theme.hintColor,
                ),
              ),
              const SizedBox(height: 6),
            ],
          ),
        if (provider.passageWords.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '上次要求的词：${provider.passageWords.join(', ')}',
                style: TextStyle(fontSize: 11, color: theme.hintColor),
              ),
            ),
          ),
        TextField(
          controller: _extraController,
          enabled: !provider.isGenerating,
          minLines: 2,
          maxLines: 4,
          style: const TextStyle(fontSize: 12.5),
          decoration: const InputDecoration(
            isDense: true,
            hintText: '追加要求，例如：多用被动语态 / 提到上海 / 结尾留一个悬念',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }

  /// "实际 151 词 · 要求约 1000 词", red when the model fell well short.
  String _wordCountLine(AiPracticeProvider provider, GeneratedPassage passage) {
    final asked = provider.archiveSource?.length ?? _passageLength;
    final actual = passage.wordCount;
    final tail = asked > 0 ? '要求约 $asked 词' : '未指定长度';
    final short = asked > 0 && actual < asked * 0.7;
    return '实际 $actual 词 · $tail${short ? ' · 比要求短很多' : ''}';
  }

  /// Explains the two marks on generated text, once per card.
  Widget _buildMarkLegend(BuildContext context) {
    final theme = Theme.of(context);
    final markStyle = TextStyle(fontSize: 11.5, color: theme.hintColor);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Wrap(
        spacing: 12,
        runSpacing: 2,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '主题词',
                style: markStyle.copyWith(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(' = 本主题词汇', style: markStyle),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '短语',
                style: markStyle.copyWith(
                  decoration: TextDecoration.underline,
                  decorationStyle: TextDecorationStyle.dotted,
                  decorationColor: theme.colorScheme.error.withValues(alpha: 0.7),
                ),
              ),
              Text(' = AI 标注的固定搭配', style: markStyle),
            ],
          ),
        ],
      ),
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
        padding: WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        ),
      ),
      segments: [
        for (final level in PracticeLevel.values)
          ButtonSegment(
            value: level,
            label: Text(level.label, style: const TextStyle(fontSize: 12)),
          ),
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
