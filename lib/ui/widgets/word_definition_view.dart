import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import '../../core/audio/audio_manager.dart';
import '../../core/mdx/mdx_entry.dart';

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
      return SelectionArea(
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
      activeContent = panels[curTab.tag] ?? panels['default'] ?? widget.entry.rawHtml;
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
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
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
          child: SelectionArea(
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
                  : (isDark ? const Color(0xFF3B4861) : const Color(0xFFCBD5E1)),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected
                  ? Colors.white
                  : (isDark ? const Color(0xFFE2E8F0) : const Color(0xFF334155)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHtmlContent(String html, bool isDark) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final primaryHex = '#${primaryColor.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
    final textColor = isDark ? '#E2E8F0' : '#1E293B';
    final secondaryTextColor = isDark ? '#94A3B8' : '#64748B';
    final exBgColor = isDark ? 'rgba(59, 130, 246, 0.10)' : 'rgba(59, 130, 246, 0.06)';
    final borderColor = isDark ? 'rgba(255, 255, 255, 0.12)' : 'rgba(0, 0, 0, 0.1)';

    final styledHtml = '''
      <style>
        body {
          color: $textColor;
          font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
          line-height: 1.65;
          margin: 0;
          padding: 0;
        }
        .hw { display: none; }
        .pron {
          color: $primaryHex;
          font-weight: 500;
          margin-bottom: 8px;
        }
        .pos {
          color: $primaryHex;
          font-weight: 700;
          font-size: 1.05em;
          margin-top: 14px;
          margin-bottom: 6px;
        }
        .section-title h3 {
          margin-top: 20px;
          margin-bottom: 10px;
          color: $primaryHex;
          font-size: 1.1em;
          border-bottom: 2px solid $primaryHex;
          padding-bottom: 4px;
          display: inline-block;
        }
        .section-divider {
          border: none;
          border-top: 1px dashed $borderColor;
          margin: 24px 0;
        }
        .defs {
          padding-left: 20px;
          margin-top: 8px;
          margin-bottom: 16px;
        }
        li {
          margin-bottom: 12px;
          line-height: 1.6;
        }
        .ex, blockquote.exq {
          display: block;
          margin-top: 8px;
          margin-bottom: 8px;
          padding: 8px 12px;
          background-color: $exBgColor;
          border-left: 3px solid $primaryHex;
          border-radius: 4px;
          font-style: italic;
          color: $secondaryTextColor;
        }
        .sec, .csec {
          margin-bottom: 20px;
        }
        a {
          color: $primaryHex;
          text-decoration: none;
          font-weight: 500;
        }
        .syn, .ant {
          color: $secondaryTextColor;
          margin-top: 4px;
        }
        hr {
          border: none;
          border-top: 1px solid $borderColor;
          margin: 16px 0;
        }
      </style>
      <div>$html</div>
    ''';

    return HtmlWidget(
      styledHtml,
      textStyle: TextStyle(
        fontSize: 15.0 * widget.fontSizeScale,
        height: 1.6,
      ),
      onTapUrl: (url) {
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
    );
  }
}
