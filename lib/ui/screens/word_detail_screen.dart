import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/frequency/frequency_service.dart';
import '../../core/mdx/entry_speech.dart';
import '../../core/mdx/mdx_entry.dart';
import '../../providers/dictionary_provider.dart';
import '../../providers/entry_speech_provider.dart';
import '../../providers/favorites_provider.dart';
import '../../providers/settings_provider.dart';
import '../widgets/examples_card.dart';
import '../widgets/frequency_badge.dart';
import '../widgets/group_selector_dialog.dart';
import '../widgets/pronunciation_bar.dart';
import '../widgets/word_definition_view.dart';
import '../widgets/speakable_selection.dart';

class WordDetailScreen extends StatelessWidget {
  final MdxEntry? entry;
  final String word;
  final bool isPaneView;

  const WordDetailScreen({
    super.key,
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
    final freq = FrequencyService().getFrequency(word);

    final mdxEntry = entry ?? dictProvider.currentEntry;
    final isLoading = dictProvider.isLoadingEntry;

    final content = isLoading
        ? const Center(child: CircularProgressIndicator())
        : (mdxEntry == null
            ? _buildNotFoundView(context, word, dictProvider)
            : _buildEntryBody(context, mdxEntry, freq, favProvider, dictProvider, settings, isDark));

    if (isPaneView) {
      return content;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(word),
        actions: [
          _buildFavoriteAction(context, word, mdxEntry, freq, favProvider),
        ],
      ),
      body: content,
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
                  ? '请检查拼写，或在左侧列表选择推荐的相近词汇'
                  : '当前未加载任何词典，请前往词典管理添加词典文件',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).hintColor),
            ),
          ],
        ),
      ),
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
    return SpeakableSelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
        // Word Header Banner
        Container(
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
                  _buildFavoriteButton(context, mdxEntry.word, mdxEntry, freq, favProvider),
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: ExamplesCard(
              examples: mdxEntry.exampleSentences.take(3).toList(),
              targetWord: mdxEntry.word,
            ),
          ),
        ],
      ),
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
    final speech = context.watch<EntrySpeechProvider>();
    final playing = speech.isPlaying;
    final index = speech.currentIndex;
    final progress = index == null ? '' : ' ${index + 1}/${speech.items.length}';
    return FilledButton.tonalIcon(
      icon: Icon(
        playing ? Icons.stop_rounded : Icons.playlist_play_rounded,
        size: 18,
      ),
      label: Text(playing ? '停止$progress' : '顺序播放 ${utterances.length} 句'),
      onPressed: () {
        if (playing) {
          speech.stop();
          return;
        }
        speech.playAll(
          utterances,
          rate: settings.speechRate,
          gap: settings.sentenceGap,
          accent: accentForLanguage(settings.ttsLanguage),
        );
      },
    );
  }

  Widget _buildFavoriteButton(
    BuildContext context,
    String targetWord,
    MdxEntry entry,
    WordFrequencyInfo? freq,
    FavoritesProvider favProvider,
  ) {
    return FutureBuilder(
      future: favProvider.getFavoriteForWord(targetWord),
      builder: (context, snapshot) {
        final favItem = snapshot.data;
        final isFav = favItem != null;

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isFav) ...[
              FutureBuilder(
                future: favProvider.groups.isNotEmpty
                    ? Future.value(favProvider.groups.firstWhere((g) => g.id == favItem.groupId, orElse: () => favProvider.groups.first))
                    : null,
                builder: (context, gSnap) {
                  final group = gSnap.data;
                  if (group == null) return const SizedBox.shrink();
                  return Container(
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
                  );
                },
              ),
            ],
            IconButton.filledTonal(
              icon: Icon(
                isFav ? Icons.star_rounded : Icons.star_border_rounded,
                color: isFav ? Colors.amber[700] : null,
              ),
              tooltip: isFav ? '编辑收藏' : '收藏此词',
              onPressed: () => _openFavoriteDialog(context, targetWord, entry, freq, favProvider, favItem),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFavoriteAction(
    BuildContext context,
    String targetWord,
    MdxEntry? entry,
    WordFrequencyInfo? freq,
    FavoritesProvider favProvider,
  ) {
    if (entry == null) return const SizedBox.shrink();
    return IconButton(
      icon: const Icon(Icons.star_border_rounded),
      onPressed: () => _openFavoriteDialog(context, targetWord, entry, freq, favProvider, null),
    );
  }

  void _openFavoriteDialog(
    BuildContext context,
    String targetWord,
    MdxEntry entry,
    WordFrequencyInfo? freq,
    FavoritesProvider favProvider,
    dynamic existingFavorite,
  ) {
    showDialog(
      context: context,
      builder: (_) => GroupSelectorDialog(
        word: targetWord,
        phonetic: entry.phonetic,
        definition: freq?.briefZh ?? (entry.definitions.isNotEmpty ? entry.definitions.first : null),
        groups: favProvider.groups,
        existingFavorite: existingFavorite,
        onSave: (groupId, note) async {
          await favProvider.addOrUpdateFavorite(
            word: targetWord,
            groupId: groupId,
            phonetic: entry.phonetic,
            definitionSnippet: freq?.briefZh ?? (entry.definitions.isNotEmpty ? entry.definitions.first : null),
            examplesSnippet: entry.exampleSentences.isNotEmpty ? entry.exampleSentences.first : null,
            note: note,
            dictSource: 'Dictionary.com',
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
