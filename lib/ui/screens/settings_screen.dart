import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/dictionary_provider.dart';
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
              Text(valueLabel,
                  style: TextStyle(
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  )),
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
