import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/dictionary_provider.dart';
import '../../core/ai/ai_config.dart';
import '../../core/ai/openai_client.dart';
import '../../core/audio/speech_engine.dart';
import '../../core/audio/audio_manager.dart';
import '../../core/audio/kokoro_model_store.dart';
import '../../providers/settings_provider.dart';
import 'dictionary_manager_screen.dart';

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
    final dictionaries = context.watch<DictionaryProvider>();

    final content = ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        _SectionTitle('外观'),
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
        _SectionTitle('词典'),
        Card(
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: ListTile(
            leading: const Icon(Icons.folder_copy_outlined),
            title: const Text('本地词典管理'),
            subtitle: Text(
              dictionaries.hasDictionaries
                  ? '已加载 ${dictionaries.allDictionaries.length} 本'
                  : '尚未添加词典',
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const DictionaryManagerScreen(),
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        _SectionTitle('发音引擎'),
        SegmentedButton<SpeechEngine>(
          segments: [
            for (final engine in SpeechEngine.values)
              ButtonSegment(
                value: engine,
                label: Text(engine.label, style: const TextStyle(fontSize: 13)),
              ),
          ],
          selected: {settings.speechEngine},
          showSelectedIcon: false,
          onSelectionChanged: (selection) =>
              settings.setSpeechEngine(selection.first),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            settings.speechEngine.hint,
            style: TextStyle(fontSize: 12, height: 1.4, color: Theme.of(context).hintColor),
          ),
        ),
        _EngineStatus(engine: settings.speechEngine),
        _SliderTile(
          icon: Icons.volume_up_rounded,
          title: '音量',
          valueLabel: '${(settings.speechVolume * 100).round()}%',
          hint: '所有朗读（词典、AI、自定义短文、数字训练）的音量',
          value: settings.speechVolume,
          min: 0,
          max: 1,
          divisions: 20,
          onChanged: settings.setSpeechVolume,
        ),
        const SizedBox(height: 24),
        _SectionTitle('朗读短语与例句'),
        _SliderTile(
          icon: Icons.speed_rounded,
          title: '播放语速',
          valueLabel: '×${settings.speechRate.toStringAsFixed(2)}',
          hint: '×1.0 是语音的自然语速；0.5 更慢，1.5 更快',
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
          hint: '顺序播放时，一句读完后等多久再读下一句',
          value: settings.sentenceGap.inMilliseconds / 1000.0,
          min: 0,
          max: 3,
          divisions: 30,
          onChanged: settings.setSentenceGapSeconds,
        ),
        const SizedBox(height: 24),
        _SectionTitle('AI 练习'),
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
    required this.hint,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String valueLabel;
  final String hint;
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
          Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Text(
              hint,
              style: TextStyle(fontSize: 12, color: theme.hintColor),
            ),
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
  String? _modelsError;

  late final TextEditingController _base = TextEditingController(
    text: widget.settings.aiBaseUrl,
  );
  late final TextEditingController _key = TextEditingController(
    text: widget.settings.aiApiKey,
  );
  late final TextEditingController _model = TextEditingController(
    text: widget.settings.aiModel,
  );

  @override
  void dispose() {
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
            Text(
              '兼容 OpenAI 格式的接口，用于生成造句与主题短文。留空 Key 也能连本地服务。',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.4,
                color: theme.hintColor,
              ),
            ),
            const SizedBox(height: 12),
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
              obscure: true,
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
      // Written through on every keystroke: a field this short costs nothing to
      // persist, and leaving the page must not lose it.
      onChanged: (value) {
        save(value);
      },
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
