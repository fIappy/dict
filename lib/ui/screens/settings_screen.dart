import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/dictionary_provider.dart';
import '../../core/ai/ai_config.dart';
import '../../core/ai/openai_client.dart';
import '../../core/audio/speech_engine.dart';
import '../../core/audio/audio_manager.dart';
import '../../core/audio/kokoro_model_store.dart';
import '../../core/audio/word_audio_cache.dart';
import '../../providers/settings_provider.dart';

/// Everything that shapes the app rather than the current word: theme, the
/// dictionary registry, and how the entry's phrases and examples are read.
///
/// It replaces the theme toggle that used to sit at the bottom of the
/// navigation rail — the same corner now opens this panel, and the toggle moved
/// in here, next to 本地词典管理, which used to have its own destination.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, this.isPaneView = false});

  /// True when embedded (rail dialog / mobile destination): no Scaffold, so the
  /// container supplies the surface.
  final bool isPaneView;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    // The AI child window hosts this page without a DictionaryProvider: the
    // dictionary card is simply absent there instead of taking the window down.
    final dictionaries = Provider.of<DictionaryProvider?>(context);

    final content = ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        const _SectionTitle('外观'),
        SegmentedButton<ThemeMode>(
          segments: const [
            ButtonSegment(
              value: ThemeMode.system,
              icon: Icon(Icons.brightness_auto_rounded, size: 18),
              label: Text('跟随系统'),
            ),
            ButtonSegment(
              value: ThemeMode.light,
              icon: Icon(Icons.light_mode_rounded, size: 18),
              label: Text('浅色'),
            ),
            ButtonSegment(
              value: ThemeMode.dark,
              icon: Icon(Icons.dark_mode_rounded, size: 18),
              label: Text('深色'),
            ),
          ],
          selected: {settings.themeMode},
          onSelectionChanged: (selection) =>
              settings.setThemeMode(selection.first),
        ),
        const SizedBox(height: 24),
        const _SectionTitle('学习库与词音缓存'),
        _LexiconAndWordCacheCard(dictionaries: dictionaries),
        const SizedBox(height: 24),
        const _SectionTitle('发音引擎'),
        // Five engines no longer fit one row of segments; a chip per engine
        // wraps, and the line below says whether the choice leaves the machine.
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final engine in SpeechEngine.values)
              ChoiceChip(
                label: Text(engine.label, style: const TextStyle(fontSize: 13)),
                selected: settings.speechEngine == engine,
                onSelected: (_) => settings.setSpeechEngine(engine),
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            settings.speechEngine.isOnline ? '联网朗读：这一句会发送到服务商' : '本机朗读：不联网',
            style: TextStyle(
              fontSize: 11.5,
              color: settings.speechEngine.isOnline
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).hintColor,
            ),
          ),
        ),
        _EngineStatus(engine: settings.speechEngine),
        _SliderTile(
          icon: Icons.volume_up_rounded,
          title: '音量',
          valueLabel: '${(settings.speechVolume * 100).round()}%',
          value: settings.speechVolume,
          min: 0,
          max: 1,
          divisions: 20,
          onChanged: settings.setSpeechVolume,
        ),
        const SizedBox(height: 24),
        const _SectionTitle('朗读短语与例句'),
        _SliderTile(
          icon: Icons.speed_rounded,
          title: '播放语速',
          valueLabel: '×${settings.speechRate.toStringAsFixed(2)}',
          value: settings.speechRate,
          min: 0.5,
          max: 1.5,
          divisions: 20,
          onChanged: settings.setSpeechRate,
        ),
        _SliderTile(
          icon: Icons.timer_outlined,
          title: '短语/例句之间的间隔',
          valueLabel: '${settings.sentenceGap.inMilliseconds / 1000.0} 秒',
          value: settings.sentenceGap.inMilliseconds / 1000.0,
          min: 0,
          max: 3,
          divisions: 30,
          onChanged: settings.setSentenceGapSeconds,
        ),
        const SizedBox(height: 24),
        const _SectionTitle('AI 练习'),
        _AiSettingsCard(settings: settings),
      ],
    );

    // Embedded in the mobile tab stack: the page has no AppBar of its own, so
    // the status bar would sit on top of the first section title.
    if (isPaneView) return SafeArea(bottom: false, child: content);
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: content,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _SliderTile extends StatelessWidget {
  const _SliderTile({
    required this.icon,
    required this.title,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                valueLabel,
                style: TextStyle(
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            label: valueLabel,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// Endpoint, key and model for the 主题 AI page. One card instead of three
/// separate settings, because none of them is useful on its own.
class _AiSettingsCard extends StatefulWidget {
  const _AiSettingsCard({required this.settings});

  final SettingsProvider settings;

  @override
  State<_AiSettingsCard> createState() => _AiSettingsCardState();
}

class _AiSettingsCardState extends State<_AiSettingsCard> {
  bool _loadingModels = false;
  bool _obscureKey = true;
  String? _modelsError;
  final Map<TextEditingController, Timer> _saveTimers = {};
  final Map<TextEditingController, Future<void> Function(String)> _saveHandlers = {};

  late final TextEditingController _base = TextEditingController(
    text: widget.settings.aiBaseUrl,
  );
  late final TextEditingController _key = TextEditingController(
    text: widget.settings.aiApiKey,
  );
  late final TextEditingController _model = TextEditingController(
    text: widget.settings.aiModel,
  );

  void _flushPendingSaves() {
    for (final timer in _saveTimers.values) {
      timer.cancel();
    }
    _saveTimers.clear();
    for (final entry in _saveHandlers.entries) {
      unawaited(entry.value(entry.key.text));
    }
    _saveHandlers.clear();
  }

  @override
  void dispose() {
    _flushPendingSaves();
    _base.dispose();
    _key.dispose();
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effort = widget.settings.aiReasoningEffort;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _field(
              _base,
              'Base URL',
              'https://api.openai.com/v1',
              widget.settings.setAiBaseUrl,
            ),
            const SizedBox(height: 10),
            _field(
              _key,
              'API Key',
              'sk-...',
              widget.settings.setAiApiKey,
              obscure: _obscureKey,
              suffix: IconButton(
                icon: Icon(
                  _obscureKey ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  size: 18,
                ),
                tooltip: _obscureKey ? '显示密钥' : '隐藏密钥',
                onPressed: () => setState(() => _obscureKey = !_obscureKey),
              ),
            ),
            const SizedBox(height: 10),
            _field(
              _model,
              '模型',
              'gpt-4o-mini',
              widget.settings.setAiModel,
              suffix: IconButton(
                icon: _loadingModels
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded, size: 18),
                tooltip: '读取接口支持的模型',
                onPressed: _loadingModels ? null : _fetchModels,
              ),
            ),
            if (_modelsError != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _modelsError!,
                  style: TextStyle(fontSize: 11.5, color: theme.colorScheme.error),
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text('思考强度',
                    style: TextStyle(fontSize: 12, color: theme.hintColor)),
                const SizedBox(width: 10),
                SegmentedButton<AiReasoningEffort>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  segments: [
                    for (final value in AiReasoningEffort.values)
                      ButtonSegment(value: value, label: Text(value.label)),
                  ],
                  selected: {effort},
                  onSelectionChanged: (selection) =>
                      widget.settings.setAiReasoningEffort(selection.first),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// The model list as the endpoint reports it; picking one writes the field.
  Future<void> _fetchModels() async {
    _flushPendingSaves();
    setState(() {
      _loadingModels = true;
      _modelsError = null;
    });
    final client = OpenAiClient(
      config: AiConfig(
        baseUrl: _base.text,
        apiKey: _key.text,
        model: _model.text,
      ),
    );
    try {
      final models = await client.listModels();
      if (!mounted) return;
      final picked = await _pickModel(models);
      if (picked != null) {
        _model.text = picked;
        await widget.settings.setAiModel(picked);
      }
    } on AiException catch (e) {
      if (mounted) setState(() => _modelsError = e.message);
    } finally {
      client.close();
      if (mounted) setState(() => _loadingModels = false);
    }
  }

  Future<String?> _pickModel(List<String> models) => showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('接口支持的模型（${models.length}）',
              style: const TextStyle(fontSize: 15)),
          content: SizedBox(
            width: 420,
            height: 380,
            child: ListView.builder(
              itemCount: models.length,
              itemBuilder: (_, index) => ListTile(
                dense: true,
                selected: models[index] == _model.text.trim(),
                title: Text(models[index], style: const TextStyle(fontSize: 13)),
                onTap: () => Navigator.pop(dialogContext, models[index]),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
          ],
        ),
      );

  Widget _field(
    TextEditingController controller,
    String label,
    String hint,
    Future<void> Function(String) save, {
    bool obscure = false,
    Widget? suffix,
  }) {
    void commitNow(String value) {
      _saveTimers.remove(controller)?.cancel();
      _saveHandlers.remove(controller);
      unawaited(save(value));
    }

    return TextField(
      controller: controller,
      obscureText: obscure,
      autocorrect: false,
      enableSuggestions: false,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        hintText: hint,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        suffixIcon: suffix,
      ),
      onChanged: (value) {
        _saveHandlers[controller] = save;
        _saveTimers.remove(controller)?.cancel();
        _saveTimers[controller] = Timer(
          const Duration(milliseconds: 300),
          () => commitNow(controller.text),
        );
      },
      onSubmitted: commitNow,
      onEditingComplete: () => commitNow(controller.text),
    );
  }
}

/// What the chosen engine found on this machine: the voice it will use, or the
/// path the model belongs at.
class _EngineStatus extends StatefulWidget {
  const _EngineStatus({required this.engine});

  final SpeechEngine engine;

  @override
  State<_EngineStatus> createState() => _EngineStatusState();
}

class _EngineStatusState extends State<_EngineStatus> {
  String? _status;
  SpeechEngine? _asked;

  @override
  void initState() {
    super.initState();
    _ask();
  }

  @override
  void didUpdateWidget(_EngineStatus oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.engine != widget.engine) _ask();
  }

  Future<void> _ask() async {
    final engine = widget.engine;
    _asked = engine;
    final status = switch (engine) {
      SpeechEngine.system => await AudioManager()
          .sentenceVoiceLabel('us')
          .then((label) => label ?? '本机没有英语系统语音'),
      SpeechEngine.kokoro => await findKokoroModel() == null
          ? await kokoroModelHint()
          : '已找到 Kokoro 模型',
      SpeechEngine.edge => '微软在线音色：Aria（美）/ Sonia（英）',
      SpeechEngine.google => 'Google 在线发音',
      SpeechEngine.baidu => '百度在线朗读',
    };
    if (!mounted || _asked != engine) return;
    setState(() => _status = status);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.graphic_eq_rounded, size: 14, color: theme.hintColor),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _status ?? '正在检测…',
              style: TextStyle(fontSize: 11.5, height: 1.4, color: theme.hintColor),
            ),
          ),
        ],
      ),
    );
  }
}

class _LexiconAndWordCacheCard extends StatefulWidget {
  const _LexiconAndWordCacheCard({required this.dictionaries});

  final DictionaryProvider? dictionaries;

  @override
  State<_LexiconAndWordCacheCard> createState() =>
      _LexiconAndWordCacheCardState();
}

class _LexiconAndWordCacheCardState extends State<_LexiconAndWordCacheCard> {
  WordAudioCacheStats? _stats;
  bool _clearing = false;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final stats = await AudioManager().wordCache.stats();
      if (!mounted) return;
      setState(() => _stats = stats);
    } catch (_) {}
  }

  Future<void> _clearCache() async {
    if (_clearing) return;
    setState(() => _clearing = true);
    try {
      await AudioManager().wordCache.clear();
      await _loadStats();
    } finally {
      if (mounted) {
        setState(() => _clearing = false);
      }
    }
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ready = widget.dictionaries?.hasDictionaries ?? false;
    final entryCount = widget.dictionaries?.totalEntries ?? 0;
    final stats = _stats;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Icon(
              Icons.auto_stories_outlined,
              color: ready ? theme.colorScheme.primary : theme.hintColor,
            ),
            title: const Text('COCA 5.4万 AI 学习库'),
            subtitle: Text(
              ready
                  ? '已就绪 · $entryCount 词 · 原生释义/搭配/例句/短文'
                  : '未检测到 coca_learn.db（部分查询将不可用）',
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.cached_rounded),
            title: const Text('在线单词发音缓存（独立 LRU）'),
            subtitle: Text(
              stats == null
                  ? '正在读取缓存统计…（与句子朗读缓存独立）'
                  : '已缓存 ${stats.wordCount} / ${stats.maxWords} 词'
                      ' · ${stats.clipCount} 条音频'
                      ' · ${_formatBytes(stats.totalBytes)}（独立于句子朗读缓存）',
            ),
            trailing: TextButton(
              onPressed:
                  (_clearing || (stats?.wordCount ?? 0) == 0) ? null : _clearCache,
              child: const Text('清空缓存'),
            ),
          ),
        ],
      ),
    );
  }
}
