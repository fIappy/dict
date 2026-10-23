import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/dom.dart' as dom;
import 'package:provider/provider.dart';
import '../../core/audio/audio_manager.dart';
import '../../core/mdx/entry_speech.dart';
import '../../core/mdx/mdx_entry.dart';
import '../../providers/entry_speech_provider.dart';
import '../../providers/settings_provider.dart';
import 'speakable_selection.dart';

class WordDefinitionView extends StatefulWidget {
  final MdxEntry entry;
  final void Function(String word)? onWordTap;
  final double fontSizeScale;

  const WordDefinitionView({
    super.key,
    required this.entry,
    this.onWordTap,
    this.fontSizeScale = 1.0,
  });

  @override
  State<WordDefinitionView> createState() => _WordDefinitionViewState();
}

class _WordDefinitionViewState extends State<WordDefinitionView> {
  int _selectedTabIndex = 0;
  String _selectedText = '';
  final AudioManager _audioManager = AudioManager();

  @override
  void didUpdateWidget(WordDefinitionView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.word != widget.entry.word) {
      setState(() {
        _selectedTabIndex = 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final tabs = widget.entry.tabs;
    final panels = widget.entry.panels;

    if (tabs.isEmpty || panels.isEmpty) {
      return SpeakableSelectionArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: _buildHtmlContent(widget.entry.rawHtml, isDark),
        ),
      );
    }

    // Determine current panel content
    String activeContent;
    final isAllTab = _selectedTabIndex >= tabs.length;

    if (isAllTab) {
      // Concatenate all panels sequentially for "All / 全部" view
      final sb = StringBuffer();
      for (final tab in tabs) {
        final p = panels[tab.tag];
        if (p != null && p.trim().isNotEmpty) {
          sb.write('<div class="section-title"><h3>${tab.label}</h3></div>');
          sb.write(p);
          sb.write('<hr class="section-divider"/>');
        }
      }
      activeContent = sb.toString();
      if (activeContent.isEmpty) activeContent = widget.entry.rawHtml;
    } else {
      final curTab = tabs[_selectedTabIndex];
      activeContent =
          panels[curTab.tag] ?? panels['default'] ?? widget.entry.rawHtml;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Top Interactive Tabs Bar
        if (tabs.length > 1)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E2430) : const Color(0xFFF1F5F9),
              border: Border(
                bottom: BorderSide(
                  color: isDark
                      ? const Color(0xFF334155)
                      : const Color(0xFFE2E8F0),
                ),
              ),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (int i = 0; i < tabs.length; i++) ...[
                    _buildTabPill(
                      label: tabs[i].label,
                      isSelected: _selectedTabIndex == i,
                      theme: theme,
                      isDark: isDark,
                      onTap: () {
                        setState(() {
                          _selectedTabIndex = i;
                        });
                      },
                    ),
                    const SizedBox(width: 8),
                  ],
                  // "All / 全部" view option
                  _buildTabPill(
                    label: '全部展开',
                    isSelected: isAllTab,
                    theme: theme,
                    isDark: isDark,
                    onTap: () {
                      setState(() {
                        _selectedTabIndex = tabs.length;
                      });
                    },
                  ),
                ],
              ),
            ),
          ),

        // Active Panel HTML Content
        Expanded(
          child: SpeakableSelectionArea(
            child: SingleChildScrollView(
              key: ValueKey('${widget.entry.word}_$_selectedTabIndex'),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: _buildHtmlContent(activeContent, isDark),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTabPill({
    required String label,
    required bool isSelected,
    required ThemeData theme,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    final activeColor = theme.colorScheme.primary;

    return Material(
      color: isSelected
          ? activeColor
          : (isDark ? const Color(0xFF262D3D) : Colors.white),
      borderRadius: BorderRadius.circular(8),
      elevation: isSelected ? 1 : 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected
                  ? activeColor
                  : (isDark
                        ? const Color(0xFF3B4861)
                        : const Color(0xFFCBD5E1)),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected
                  ? Colors.white
                  : (isDark
                        ? const Color(0xFFE2E8F0)
                        : const Color(0xFF334155)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHtmlContent(String html, bool isDark) {
    // The reader adds a speaker link to every 词语搭配 / 权威例句 line; the
    // indices it hands back address the same list the links carry. The line
    // being read is marked so it can be coloured.
    final speech = context.watch<EntrySpeechProvider>();
    final speaking = speech.isPlaying &&
            speech.isReading([for (final line in extractEntryUtterances(html)) line.text])
        ? speech.currentIndex
        : null;
    final prepared = prepareEntrySpeech(html, speaking: speaking);
    final primaryColor = Theme.of(context).colorScheme.primary;
    final primaryHex =
        '#${primaryColor.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
    final secondaryTextColor = isDark ? '#94A3B8' : '#64748B';
    final exBgColor = isDark
        ? 'rgba(59, 130, 246, 0.10)'
        : 'rgba(59, 130, 246, 0.06)';
    final borderColor = isDark
        ? 'rgba(255, 255, 255, 0.12)'
        : 'rgba(0, 0, 0, 0.1)';

    final entryStyles = _entryStyles(
      primary: primaryHex,
      secondary: secondaryTextColor,
      exampleBackground: exBgColor,
      border: borderColor,
    );

    return SelectionArea(
      onSelectionChanged: (content) => _selectedText = content?.plainText ?? '',
      contextMenuBuilder: (menuContext, state) => _selectionMenu(state),
      child: HtmlWidget(
        prepared.html,
        textStyle: TextStyle(
          fontSize: 15.0 * widget.fontSizeScale,
          height: 1.6,
        ),
        customStylesBuilder: entryStyles,
        onTapUrl: (url) {
          if (url.startsWith('speech://')) {
            final index = int.tryParse(url.substring('speech://'.length));
            if (index != null && index < prepared.utterances.length) {
              final settings = context.read<SettingsProvider>();
              context.read<EntrySpeechProvider>().playOne(
                prepared.utterances[index],
                rate: settings.speechRate,
                accent: accentForLanguage(settings.ttsLanguage),
              );
            }
            return true;
          }
          if (url.startsWith('sound://')) {
            final soundKey = url.substring('sound://'.length);
            _audioManager.playWord(word: widget.entry.word, soundKey: soundKey);
            return true;
          } else if (url.startsWith('entry://')) {
            final target = url.substring('entry://'.length);
            widget.onWordTap?.call(target);
            return true;
          } else {
            final cleaned = url.replaceAll(RegExp(r'[^a-zA-Z\-]'), '');
            if (cleaned.isNotEmpty) {
              widget.onWordTap?.call(cleaned);
              return true;
            }
          }
          return false;
        },
      ),
    );
  }

  /// The text-selection menu, with reading appended: tagged example lines have
  /// their own speaker icons, but a definition or a note only gets a voice once
  /// it can be selected.
  Widget _selectionMenu(SelectableRegionState state) {
    final items = [...state.contextMenuButtonItems];
    final selected = _selectedText.trim();
    if (selected.isNotEmpty) {
      items.add(
        ContextMenuButtonItem(
          label: '朗读',
          onPressed: () {
            ContextMenuController.removeAny();
            _speakSelected(selected);
          },
        ),
      );
    }
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: state.contextMenuAnchors,
      buttonItems: items,
    );
  }

  void _speakSelected(String text) {
    final settings = context.read<SettingsProvider>();
    context.read<EntrySpeechProvider>().speakText(
      text,
      rate: settings.speechRate,
      accent: accentForLanguage(settings.ttsLanguage),
    );
  }

  /// Styles for the markup this reader renders.
  ///
  /// `HtmlWidget` never interprets `<style>` blocks — it builds them as
  /// `display: none` — so the only way CSS reaches it is this callback, which
  /// is why every rule lives here instead of in a stylesheet string. Rules are
  /// keyed by tag name and CSS class, the way the archives write them.
  ///
  /// Covered: Dictionary.com (`hw` / `pron` / `pos` / `defs` / `ex` / `sec`)
  /// and SIO 双向双解词典, whose records split a headword into an audio bar, a
  /// concise entry, 词语搭配 and 权威例句 sections that would otherwise run
  /// together into a single paragraph.
  StylesMap? Function(dom.Element) _entryStyles({
    required String primary,
    required String secondary,
    required String exampleBackground,
    required String border,
  }) {
    return (element) {
      final styles = <String, String>{};
      final classes = element.classes;

      switch (element.localName) {
        case 'li':
          styles['margin-bottom'] = '12px';
          styles['line-height'] = '1.6';
        case 'hr':
          styles['border'] = 'none';
          styles['border-top'] = '1px solid $border';
          styles['margin'] = '16px 0';
        case 'a':
          styles['color'] = primary;
          styles['text-decoration'] = 'none';
          styles['font-weight'] = '500';
        case 'h3' when _hasAncestorClass(element, 'section-title'):
          styles['margin-top'] = '20px';
          styles['margin-bottom'] = '10px';
          styles['color'] = primary;
          styles['font-size'] = '1.1em';
          styles['border-bottom'] = '2px solid $primary';
          styles['padding-bottom'] = '4px';
          styles['display'] = 'inline-block';
        // Chinese side of a bilingual example: rendered as plain text, since
        // the 中文显隐 toggle needs the archive's JavaScript.
        case 'zh_cn':
          styles['display'] = 'block';
          styles['margin-top'] = '2px';
          styles['color'] = secondary;
          styles['font-size'] = '0.94em';
      }

      if (classes.contains('hw')) {
        styles['display'] = 'none';
      }
      // The speaker link the reader appends to each speakable line.
      if (classes.contains('speaking')) {
        styles['color'] = '#E53935';
        styles['font-weight'] = '600';
      }
      if (classes.contains('speech')) {
        styles['display'] = 'inline';
        styles['margin-left'] = '6px';
        styles['font-size'] = '0.85em';
        styles['text-decoration'] = 'none';
        styles['opacity'] = '0.75';
      }
      if (classes.contains('pron')) {
        styles['color'] = primary;
        styles['font-weight'] = '500';
        styles['margin-bottom'] = '8px';
      }
      if (classes.contains('pos')) {
        styles['color'] = primary;
        styles['font-weight'] = '700';
        styles['font-size'] = '1.05em';
        styles['margin-top'] = '14px';
        styles['margin-bottom'] = '6px';
      }
      if (classes.contains('section-divider')) {
        styles['border'] = 'none';
        styles['border-top'] = '1px dashed $border';
        styles['margin'] = '24px 0';
      }
      if (classes.contains('defs')) {
        styles['padding-left'] = '20px';
        styles['margin-top'] = '8px';
        styles['margin-bottom'] = '16px';
      }
      if (classes.contains('ex') ||
          (element.localName == 'blockquote' && classes.contains('exq'))) {
        styles['display'] = 'block';
        styles['margin'] = '8px 0';
        styles['padding'] = '8px 12px';
        styles['background-color'] = exampleBackground;
        styles['border-left'] = '3px solid $primary';
        styles['border-radius'] = '4px';
        styles['font-style'] = 'italic';
        styles['color'] = secondary;
      }
      if (classes.contains('sec') || classes.contains('csec')) {
        styles['margin-bottom'] = '20px';
      }
      if (classes.contains('syn') || classes.contains('ant')) {
        styles['color'] = secondary;
        styles['margin-top'] = '4px';
      }
      if (classes.contains('tio_forvo')) {
        styles['display'] = 'block';
        styles['margin-bottom'] = '12px';
      }
      if (element.localName == 'a' && _hasAncestorClass(element, 'tio_forvo')) {
        styles['display'] = 'inline-block';
        styles['margin'] = '0 6px 4px 0';
        styles['padding'] = '1px 8px';
        styles['border'] = '1px solid $border';
        styles['border-radius'] = '10px';
        styles['font-size'] = '11.5px';
        styles['font-weight'] = '500';
        styles['text-decoration'] = 'none';
      }
      if (classes.contains('pg_simple')) {
        styles['display'] = 'block';
        styles['margin-bottom'] = '6px';
      }
      if (classes.contains('pg_hw')) {
        styles['font-weight'] = '700';
        styles['font-size'] = '1.1em';
      }
      if (classes.contains('pg_phrase') || classes.contains('pg_sentence')) {
        styles['display'] = 'block';
        styles['margin'] = '18px 0 8px';
        styles['padding-bottom'] = '4px';
        styles['border-bottom'] = '2px solid $primary';
        styles['color'] = primary;
        styles['font-size'] = '1.05em';
        styles['font-weight'] = '700';
      }
      if (classes.contains('pg_exam')) {
        styles['display'] = 'block';
        styles['margin'] = '6px 0 6px 10px';
      }
      if (classes.contains('pg_key')) {
        styles['color'] = primary;
        styles['font-weight'] = '700';
      }
      if (classes.contains('pg_ht')) {
        styles['text-decoration'] = 'underline';
      }
      if (classes.contains('pg_book')) {
        styles['margin-left'] = '6px';
        styles['font-size'] = '0.82em';
        styles['color'] = secondary;
      }
      if (classes.contains('comment')) {
        styles['display'] = 'none';
      }

      return styles.isEmpty ? null : styles;
    };
  }

  static bool _hasAncestorClass(dom.Element element, String name) {
    for (var node = element.parent; node is dom.Element; node = node.parent) {
      if (node.classes.contains(name)) return true;
    }
    return false;
  }
}
