import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/frequency/frequency_service.dart';
import '../../core/mdx/entry_speech.dart';
import '../../core/mdx/mdx_entry.dart';
import '../../core/models/lexeme_entry.dart';
import '../../providers/dictionary_provider.dart';
import '../../providers/entry_speech_provider.dart';
import '../../providers/favorites_provider.dart';
import '../../providers/settings_provider.dart';
import '../widgets/examples_card.dart';
import '../widgets/frequency_badge.dart';
import '../widgets/group_selector_dialog.dart';
import '../widgets/lexeme_detail_view.dart';
import '../widgets/pronunciation_bar.dart';
import '../widgets/word_definition_view.dart';
import '../widgets/speakable_selection.dart';
import '../widgets/speech_controls.dart';

class WordDetailScreen extends StatelessWidget {
  final LexemeEntry? lexeme;
  final MdxEntry? entry;
  final String word;
  final bool isPaneView;

  const WordDetailScreen({
    super.key,
    this.lexeme,
    this.entry,
    required this.word,
    this.isPaneView = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final dictProvider = context.watch<DictionaryProvider>();
    final favProvider = context.watch<FavoritesProvider>();
    final settings = context.watch<SettingsProvider>();
    final freqService = FrequencyService();
    if (!freqService.isInitialized) {
      unawaited(freqService.init());
    }

    final activeLexeme = lexeme ?? (entry == null ? dictProvider.currentLexeme : null);
    final mdxEntry = activeLexeme == null ? (entry ?? dictProvider.currentEntry) : null;
    final isLoading = lexeme == null && entry == null && dictProvider.isLoadingEntry;

    return ValueListenableBuilder<int>(
      valueListenable: freqService.versionListenable,
      builder: (context, _, _) {
        final freq = freqService.getFrequency(word);

        final Widget content;
        if (isLoading) {
          content = const Center(child: CircularProgressIndicator());
        } else if (activeLexeme != null) {
          content = _buildLexemeBody(
            context,
            activeLexeme,
            freq,
            favProvider,
            dictProvider,
            settings,
            isDark,
          );
        } else if (mdxEntry != null) {
          content = _buildEntryBody(
            context,
            mdxEntry,
            freq,
            favProvider,
            dictProvider,
            settings,
            isDark,
          );
        } else {
          content = _buildNotFoundView(context, word, dictProvider);
        }

        if (isPaneView) {
          return content;
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(word),
            actions: [
              _buildFavoriteAction(
                context,
                word,
                lexeme: activeLexeme,
                entry: mdxEntry,
                freq: freq,
                favProvider: favProvider,
                dictProvider: dictProvider,
              ),
            ],
          ),
          body: content,
        );
      },
    );
  }

  Widget _buildNotFoundView(BuildContext context, String word, DictionaryProvider dictProvider) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off_rounded, size: 64, color: Theme.of(context).hintColor),
            const SizedBox(height: 16),
            Text(
              '未找到 "$word" 的词条',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              dictProvider.hasDictionaries
                  ? '请检查拼写，或在左侧搜索相近词汇或搭配'
                  : '当前未加载 5.4 万词 AI 学习库 (coca_learn.db)，请确认学习库文件位于应用目录',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).hintColor),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLexemeBody(
    BuildContext context,
    LexemeEntry lexeme,
    WordFrequencyInfo? freq,
    FavoritesProvider favProvider,
    DictionaryProvider dictProvider,
    SettingsProvider settings,
    bool isDark,
  ) {
    final utterances = lexeme.toUtterances();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SpeakableSelectionArea(
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E2430) : Colors.white,
              border: Border(
                bottom: BorderSide(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: SpeakableText(
                        lexeme.word,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                    _buildFavoriteButton(
                      context,
                      lexeme.word,
                      lexeme: lexeme,
                      freq: freq,
                      favProvider: favProvider,
                      dictProvider: dictProvider,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    PronunciationBar(
                      word: lexeme.word,
                      phonetic: '',
                    ),
                    FrequencyBadge(info: freq),
                    if (utterances.isNotEmpty)
                      _buildUtterancesControl(context, utterances, settings),
                  ],
                ),
                if (lexeme.briefZh.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SpeakableText(
                    lexeme.briefZh,
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        Expanded(
          child: LexemeDetailView(
            lexeme: lexeme,
            fontSizeScale: settings.fontSizeScale,
            onWordTap: (tappedWord) {
              dictProvider.lookupWord(tappedWord);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEntryBody(
    BuildContext context,
    MdxEntry mdxEntry,
    WordFrequencyInfo? freq,
    FavoritesProvider favProvider,
    DictionaryProvider dictProvider,
    SettingsProvider settings,
    bool isDark,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Word Header Banner (own SpeakableSelectionArea so WordDefinitionView is not nested)
        SpeakableSelectionArea(
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E2430) : Colors.white,
              border: Border(
                bottom: BorderSide(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: SpeakableText(
                        mdxEntry.word,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                    _buildFavoriteButton(
                      context,
                      mdxEntry.word,
                      entry: mdxEntry,
                      freq: freq,
                      favProvider: favProvider,
                      dictProvider: dictProvider,
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Pronunciation bar & Frequency badges
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    PronunciationBar(
                      word: mdxEntry.word,
                      phonetic: mdxEntry.phonetic,
                      phonetics: mdxEntry.phonetics,
                      soundKey: mdxEntry.soundKey,
                      soundKeys: mdxEntry.soundKeys,
                    ),
                    FrequencyBadge(info: freq),
                    _buildSpeechControl(context, mdxEntry, settings),
                  ],
                ),

                // Chinese brief gloss if available
                if (freq?.briefZh != null) ...[
                  const SizedBox(height: 8),
                  SpeakableText(
                    freq!.briefZh!,
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        // Main Definition & Panels Canvas
        Expanded(
          child: WordDefinitionView(
            entry: mdxEntry,
            fontSizeScale: settings.fontSizeScale,
            onWordTap: (tappedWord) {
              dictProvider.lookupWord(tappedWord);
            },
          ),
        ),

        // Bottom Examples Card if examples exist and not in examples tab
        if (mdxEntry.exampleSentences.isNotEmpty &&
            !mdxEntry.tabs.any((t) => t.tag.toLowerCase().contains('ex')))
          SpeakableSelectionArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: ExamplesCard(
                examples: mdxEntry.exampleSentences.take(3).toList(),
                targetWord: mdxEntry.word,
              ),
            ),
          ),
      ],
    );
  }

  /// One click reads every 词语搭配 / 权威例句 line in page order, waiting the
  /// configured gap between lines. While it runs the same button stops it and
  /// shows which line is sounding.
  Widget _buildSpeechControl(
    BuildContext context,
    MdxEntry mdxEntry,
    SettingsProvider settings,
  ) {
    final utterances = extractEntryUtterances(mdxEntry.rawHtml);
    if (utterances.isEmpty) return const SizedBox.shrink();
    return _buildUtterancesControl(context, utterances, settings);
  }

  Widget _buildUtterancesControl(
    BuildContext context,
    List<EntryUtterance> utterances,
    SettingsProvider settings,
  ) {
    return Builder(
      builder: (context) {
        final progress = context.select<EntrySpeechProvider, String>((speech) {
          final index = speech.currentIndex;
          return index == null ? '' : ' ${index + 1}/${speech.items.length}';
        });
        return SpeechControls(
          labels: true,
          idleLabel: '顺序播放 ${utterances.length} 句$progress',
          onStart: () => context.read<EntrySpeechProvider>().playAll(
            utterances,
            rate: settings.speechRate,
            gap: settings.sentenceGap,
            accent: accentForLanguage(settings.ttsLanguage),
            loop: settings.speechLoop,
            engine: settings.speechEngine,
            volume: settings.speechVolume,
          ),
        );
      },
    );
  }

  Widget _buildFavoriteButton(
    BuildContext context,
    String targetWord, {
    LexemeEntry? lexeme,
    MdxEntry? entry,
    WordFrequencyInfo? freq,
    required FavoritesProvider favProvider,
    required DictionaryProvider dictProvider,
  }) {
    final favItem = favProvider.findFavorite(targetWord);
    final isFav = favItem != null;
    final group = favItem == null
        ? null
        : (favProvider.findGroup(favItem.groupId) ??
            (favProvider.groups.isNotEmpty ? favProvider.groups.first : null));

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (group != null)
          Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Color(group.color).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Color(group.color)),
            ),
            child: Text(
              group.name,
              style: TextStyle(
                fontSize: 11,
                color: Color(group.color),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        IconButton.filledTonal(
          icon: Icon(
            isFav ? Icons.star_rounded : Icons.star_border_rounded,
            color: isFav ? Colors.amber[700] : null,
          ),
          tooltip: isFav ? '编辑收藏' : '收藏此词',
          onPressed: () => _openFavoriteDialog(
            context,
            targetWord,
            lexeme: lexeme,
            entry: entry,
            freq: freq,
            favProvider: favProvider,
            existingFavorite: favItem,
            dictSource: dictProvider.currentDictionaryName,
          ),
        ),
      ],
    );
  }

  Widget _buildFavoriteAction(
    BuildContext context,
    String targetWord, {
    LexemeEntry? lexeme,
    MdxEntry? entry,
    WordFrequencyInfo? freq,
    required FavoritesProvider favProvider,
    required DictionaryProvider dictProvider,
  }) {
    if (lexeme == null && entry == null) return const SizedBox.shrink();
    final favItem = favProvider.findFavorite(targetWord);
    final isFav = favItem != null;
    return IconButton(
      icon: Icon(
        isFav ? Icons.star_rounded : Icons.star_border_rounded,
        color: isFav ? Colors.amber[700] : null,
      ),
      tooltip: isFav ? '编辑收藏' : '收藏此词',
      onPressed: () => _openFavoriteDialog(
        context,
        targetWord,
        lexeme: lexeme,
        entry: entry,
        freq: freq,
        favProvider: favProvider,
        existingFavorite: favItem,
        dictSource: dictProvider.currentDictionaryName,
      ),
    );
  }

  void _openFavoriteDialog(
    BuildContext context,
    String targetWord, {
    LexemeEntry? lexeme,
    MdxEntry? entry,
    WordFrequencyInfo? freq,
    required FavoritesProvider favProvider,
    dynamic existingFavorite,
    String? dictSource,
  }) {
    final phonetic = entry?.phonetic ?? '';
    final defSnippet = freq?.briefZh ??
        ((lexeme != null && lexeme.briefZh.isNotEmpty)
            ? lexeme.briefZh
            : (entry != null && entry.definitions.isNotEmpty
                ? entry.definitions.first
                : null));
    final exampleSnippet = (lexeme != null && lexeme.sentences.isNotEmpty)
        ? lexeme.sentences.first.text
        : (entry != null && entry.exampleSentences.isNotEmpty
            ? entry.exampleSentences.first
            : null);

    showDialog(
      context: context,
      builder: (_) => GroupSelectorDialog(
        word: targetWord,
        phonetic: phonetic,
        definition: defSnippet,
        groups: favProvider.groups,
        existingFavorite: existingFavorite,
        onSave: (groupId, note) async {
          await favProvider.addOrUpdateFavorite(
            word: targetWord,
            groupId: groupId,
            phonetic: phonetic,
            definitionSnippet: defSnippet,
            examplesSnippet: exampleSnippet,
            note: note,
            dictSource: dictSource ?? 'COCA 5.4万 AI 学习库',
          );
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('已保存到生词本: $targetWord'),
                duration: const Duration(seconds: 1),
              ),
            );
          }
        },
        onRemove: existingFavorite != null
            ? () async {
                await favProvider.removeFavorite(targetWord);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('已从生词本移除: $targetWord'),
                      duration: const Duration(seconds: 1),
                    ),
                  );
                }
              }
            : null,
        onCreateGroup: (name, color) async {
          return await favProvider.createGroup(name, color);
        },
      ),
    );
  }
}
