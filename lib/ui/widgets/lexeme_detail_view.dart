import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/custom/custom_text.dart';
import '../../core/mdx/entry_speech.dart';
import '../../core/models/lexeme_entry.dart';
import '../../providers/entry_speech_provider.dart';
import '../../providers/settings_provider.dart';
import 'annotated_text.dart';
import 'speakable_selection.dart';

/// Native Flutter structured AI learning card for a [LexemeEntry].
class LexemeDetailView extends StatefulWidget {
  const LexemeDetailView({
    super.key,
    required this.lexeme,
    this.fontSizeScale = 1.0,
    this.compact = false,
    this.onWordTap,
  });

  final LexemeEntry lexeme;
  final double fontSizeScale;
  final bool compact;
  final void Function(String word)? onWordTap;

  @override
  State<LexemeDetailView> createState() => _LexemeDetailViewState();
}

class _LexemeDetailViewState extends State<LexemeDetailView> {
  bool _showTranslations = true;

  void _speakText(BuildContext context, String rawText) {
    final cleaned = rawText
        .replaceAll('...', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) return;
    final speech = context.read<EntrySpeechProvider>();
    final settings = context.read<SettingsProvider>();
    speech.speakText(
      cleaned,
      rate: settings.speechRate,
      accent: accentForLanguage(settings.ttsLanguage),
      engine: settings.speechEngine,
      volume: settings.speechVolume,
    );
  }

  void _playSentence(BuildContext context, int index, String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final speech = context.read<EntrySpeechProvider>();
    final settings = context.read<SettingsProvider>();
    speech.playOne(
      EntryUtterance(
        text: trimmed,
        isPhrase: false,
        itemId: 'lexeme_sent_$index',
        sentenceIndex: 0,
      ),
      rate: settings.speechRate,
      accent: accentForLanguage(settings.ttsLanguage),
      engine: settings.speechEngine,
      volume: settings.speechVolume,
    );
  }

  void _togglePassageSpeech(BuildContext context, String passageText) {
    final speech = context.read<EntrySpeechProvider>();
    final sentences = splitSentences(passageText);
    if (sentences.isEmpty) return;
    final utterances = [
      for (var i = 0; i < sentences.length; i++)
        EntryUtterance(
          text: sentences[i],
          isPhrase: false,
          itemId: 'lexeme_passage',
          sentenceIndex: i,
        ),
    ];
    if (speech.isReadingUtterances(utterances)) {
      speech.stop();
      return;
    }
    final settings = context.read<SettingsProvider>();
    speech.playAll(
      utterances,
      rate: settings.speechRate,
      gap: settings.sentenceGap,
      accent: accentForLanguage(settings.ttsLanguage),
      loop: settings.speechLoop,
      engine: settings.speechEngine,
      volume: settings.speechVolume,
    );
  }

  @override
  Widget build(BuildContext context) {
    final lexeme = widget.lexeme;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final speech = context.watch<EntrySpeechProvider>();
    final pad = widget.compact ? 14.0 : 24.0;
    final scale = widget.fontSizeScale;

    return SpeakableSelectionArea(
      child: ListView(
        padding: EdgeInsets.fromLTRB(pad, widget.compact ? 12 : 18, pad, 28),
        children: [
          if (lexeme.matchedFrom != null ||
              lexeme.pos.isNotEmpty ||
              lexeme.register != 'standard' ||
              lexeme.themeGloss != null) ...[
            _buildMetaTags(theme, isDark, lexeme),
            const SizedBox(height: 14),
          ],

          if (lexeme.meaningZh.trim().isNotEmpty) ...[
            _SectionHeader(
              icon: Icons.menu_book_rounded,
              title: '核心释义',
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 8),
            _SectionCard(
              isDark: isDark,
              child: Text(
                lexeme.meaningZh,
                style: TextStyle(
                  fontSize: 15 * scale,
                  height: 1.65,
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          if (lexeme.usageZh.trim().isNotEmpty) ...[
            _SectionHeader(
              icon: Icons.lightbulb_outline_rounded,
              title: '用法与避坑',
              color: isDark ? Colors.amber[300]! : Colors.orange[800]!,
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.amber.withValues(alpha: 0.08)
                    : const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark
                      ? Colors.amber.withValues(alpha: 0.25)
                      : const Color(0xFFFDE68A),
                ),
              ),
              child: Text(
                lexeme.usageZh,
                style: TextStyle(
                  fontSize: 14 * scale,
                  height: 1.65,
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          if (lexeme.collocations.isNotEmpty) ...[
            _SectionHeader(
              icon: Icons.link_rounded,
              title: '高频搭配词组',
              color: theme.colorScheme.secondary,
              trailing: Text(
                '点击可朗读',
                style: TextStyle(fontSize: 11.5, color: theme.hintColor),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final phrase in lexeme.collocations)
                  ActionChip(
                    avatar: Icon(
                      Icons.volume_up_rounded,
                      size: 15,
                      color: theme.colorScheme.primary,
                    ),
                    label: Text(
                      phrase,
                      style: TextStyle(
                        fontSize: 13.5 * scale,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    onPressed: () => _speakText(context, phrase),
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],

          if (lexeme.patterns.isNotEmpty) ...[
            const _SectionHeader(
              icon: Icons.account_tree_outlined,
              title: '实用句型',
              color: Colors.teal,
            ),
            const SizedBox(height: 8),
            _SectionCard(
              isDark: isDark,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < lexeme.patterns.length; i++) ...[
                    if (i > 0)
                      Divider(
                        height: 14,
                        color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                      ),
                    InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => _speakText(context, lexeme.patterns[i]),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                lexeme.patterns[i],
                                style: TextStyle(
                                  fontSize: 14 * scale,
                                  fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ),
                            Icon(
                              Icons.volume_up_outlined,
                              size: 16,
                              color: theme.hintColor,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          if (lexeme.expressions.isNotEmpty) ...[
            const _SectionHeader(
              icon: Icons.auto_awesome_rounded,
              title: '地道表达',
              color: Colors.deepPurpleAccent,
            ),
            const SizedBox(height: 8),
            _SectionCard(
              isDark: isDark,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < lexeme.expressions.length; i++) ...[
                    if (i > 0)
                      Divider(
                        height: 14,
                        color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                      ),
                    InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => _speakText(context, lexeme.expressions[i]),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                lexeme.expressions[i],
                                style: TextStyle(
                                  fontSize: 14 * scale,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            Icon(
                              Icons.volume_up_outlined,
                              size: 16,
                              color: theme.hintColor,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          if (lexeme.sentences.isNotEmpty) ...[
            _SectionHeader(
              icon: Icons.format_quote_rounded,
              title: '情景例句',
              color: theme.colorScheme.primary,
              trailing: TextButton.icon(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: Icon(
                  _showTranslations
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 15,
                ),
                label: Text(
                  _showTranslations ? '隐藏译文' : '显示译文',
                  style: const TextStyle(fontSize: 12),
                ),
                onPressed: () =>
                    setState(() => _showTranslations = !_showTranslations),
              ),
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < lexeme.sentences.length; i++) ...[
              _buildSentenceItem(
                context,
                theme: theme,
                isDark: isDark,
                index: i,
                sentence: lexeme.sentences[i],
                isSpeaking: speech.sentenceIndexFor('lexeme_sent_$i') != null,
                scale: scale,
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 8),
          ],

          if (lexeme.passage != null &&
              lexeme.passage!.text.trim().isNotEmpty) ...[
            _buildPassageSection(
              context,
              theme: theme,
              isDark: isDark,
              passage: lexeme.passage!,
              speech: speech,
              scale: scale,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetaTags(ThemeData theme, bool isDark, LexemeEntry lexeme) {
    final chips = <Widget>[];

    if (lexeme.matchedFrom != null) {
      chips.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '由「${lexeme.matchedFrom}」匹配至词元「${lexeme.word}」',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSecondaryContainer,
            ),
          ),
        ),
      );
    }

    for (final p in lexeme.pos) {
      chips.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            p,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ),
      );
    }

    if (lexeme.register != 'standard') {
      final (label, bg, fg, icon) = switch (lexeme.register) {
        'informal' => (
            '口语 / 非正式',
            isDark ? Colors.blueGrey.shade800 : Colors.blueGrey.shade100,
            isDark ? Colors.blueGrey.shade100 : Colors.blueGrey.shade800,
            Icons.chat_bubble_outline_rounded,
          ),
        'formal' => (
            '正式 / 书面 / 术语',
            isDark ? Colors.indigo.shade900 : Colors.indigo.shade50,
            isDark ? Colors.indigo.shade200 : Colors.indigo.shade800,
            Icons.school_outlined,
          ),
        'vulgar' => (
            '粗俗用语·慎用',
            isDark ? Colors.orange.withValues(alpha: 0.25) : const Color(0xFFFFEDD5),
            isDark ? Colors.orange.shade200 : Colors.orange.shade900,
            Icons.warning_amber_rounded,
          ),
        'offensive' => (
            '冒犯性词汇·警示',
            isDark ? Colors.red.withValues(alpha: 0.28) : const Color(0xFFFEE2E2),
            isDark ? Colors.red.shade200 : Colors.red.shade900,
            Icons.report_problem_outlined,
          ),
        _ => (
            lexeme.register,
            theme.colorScheme.surfaceContainerHighest,
            theme.colorScheme.onSurfaceVariant,
            Icons.label_outline,
          ),
      };
      chips.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: fg),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final gloss = lexeme.themeGloss?.trim();
    if (gloss != null && gloss.isNotEmpty) {
      chips.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isDark ? Colors.white10 : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '主题义：$gloss',
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return Wrap(spacing: 8, runSpacing: 8, children: chips);
  }

  Widget _buildSentenceItem(
    BuildContext context, {
    required ThemeData theme,
    required bool isDark,
    required int index,
    required LexemeSentence sentence,
    required bool isSpeaking,
    required double scale,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: isSpeaking
            ? theme.colorScheme.error.withValues(alpha: 0.08)
            : (isDark ? const Color(0xFF1E2430) : Colors.white),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSpeaking
              ? theme.colorScheme.error.withValues(alpha: 0.45)
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 3, right: 10),
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '${index + 1}',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnnotatedText(
                  sentence.text,
                  themeWords: {widget.lexeme.word},
                  phrases: sentence.phrases,
                  speakingIndex: isSpeaking ? 0 : null,
                  style: TextStyle(
                    fontSize: 14.5 * scale,
                    height: 1.55,
                  ),
                ),
                if (_showTranslations &&
                    sentence.translation.trim().isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    sentence.translation,
                    style: TextStyle(
                      fontSize: 13 * scale,
                      height: 1.45,
                      color: theme.hintColor,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: '朗读此句',
            icon: Icon(
              isSpeaking ? Icons.graphic_eq_rounded : Icons.volume_up_rounded,
              size: 19,
              color: isSpeaking
                  ? theme.colorScheme.error
                  : theme.colorScheme.primary,
            ),
            onPressed: () => _playSentence(context, index, sentence.text),
          ),
        ],
      ),
    );
  }

  Widget _buildPassageSection(
    BuildContext context, {
    required ThemeData theme,
    required bool isDark,
    required LexemePassage passage,
    required EntrySpeechProvider speech,
    required double scale,
  }) {
    final sentences = splitSentences(passage.text);
    final passageUtterances = [
      for (var i = 0; i < sentences.length; i++)
        EntryUtterance(
          text: sentences[i],
          isPhrase: false,
          itemId: 'lexeme_passage',
          sentenceIndex: i,
        ),
    ];
    final isReadingPassage = speech.isReadingUtterances(passageUtterances);
    final speakingIdx = speech.sentenceIndexFor('lexeme_passage');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          icon: Icons.article_outlined,
          title: '情景短文',
          color: theme.colorScheme.primary,
          trailing: TextButton.icon(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: Icon(
              isReadingPassage ? Icons.stop_rounded : Icons.play_arrow_rounded,
              size: 17,
            ),
            label: Text(
              isReadingPassage ? '停止短文' : '朗读短文',
              style: const TextStyle(fontSize: 12.5),
            ),
            onPressed: () => _togglePassageSpeech(context, passage.text),
          ),
        ),
        const SizedBox(height: 8),
        _SectionCard(
          isDark: isDark,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (passage.title.trim().isNotEmpty) ...[
                Text(
                  passage.title,
                  style: TextStyle(
                    fontSize: 15.5 * scale,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              AnnotatedText(
                passage.text,
                themeWords: {widget.lexeme.word},
                phrases: passage.phrases,
                speakingIndex: speakingIdx,
                style: TextStyle(
                  fontSize: 14.5 * scale,
                  height: 1.7,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.color,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final Color color;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 6),
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        const Spacer(),
        ?trailing,
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.isDark,
    required this.child,
  });

  final bool isDark;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2430) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      child: child,
    );
  }
}
