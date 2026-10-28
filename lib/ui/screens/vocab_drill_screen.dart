import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/audio/audio_manager.dart';
import '../../core/audio/prefetch_queue.dart';
import '../../core/audio/prepared_pronunciation.dart';
import '../../core/themes/theme_service.dart';
import '../../providers/dictionary_provider.dart';
import '../../providers/vocabulary_provider.dart';
import '../widgets/pronunciation_bar.dart';
import '../widgets/word_definition_view.dart';

/// 背词: the theme's words on the left, their Chinese meanings on the right.
///
/// The meanings start hidden — the point is to recall one before checking — and
/// each one flips on a click, with a switch for all of them. Stars narrow the
/// list to what the reader still needs, and every word can open its dictionary
/// entry in the side panel instead of sending the reader to another window.
class VocabDrillScreen extends StatefulWidget {
  const VocabDrillScreen({super.key, required this.scene});

  final ThemeScene scene;

  @override
  State<VocabDrillScreen> createState() => _VocabDrillScreenState();
}

class _VocabDrillScreenState extends State<VocabDrillScreen> {
  /// The word whose entry is in the side panel, or null when it is closed.
  String? _lookup;

  final AudioManager _audio = AudioManager();

  /// 循环朗读 is running, and the word sounding right now (highlighted in the
  /// list). The token lets a stop cut a run that is waiting on audio.
  bool _looping = false;

  /// Words whose audio is resolved ahead of their turn.
  static const int prefetchWindow = 10;
  int _loopToken = 0;
  String? _speaking;

  @override
  void dispose() {
    _loopToken++;
    _looping = false;
    _audio.stopPronunciation();
    super.dispose();
  }

  ThemeScene get scene => widget.scene;

  List<String> get _words => [for (final group in scene.groups) ...group.words];

  Map<String, String> get _glosses => {
        for (final group in scene.groups) ...group.glosses,
      };

  /// Plays one word, cutting the loop first so the two never overlap.
  Future<void> _playWord(String word) async {
    final accent = context.read<VocabularyProvider>().accent;
    await _stopLoop();
    setState(() => _speaking = word);
    await _audio.playWordAndWait(word: word, accent: accent);
    if (mounted && !_looping && _speaking == word) {
      setState(() => _speaking = null);
    }
  }

  Future<void> _stopLoop() async {
    if (!_looping) return;
    _loopToken++;
    setState(() {
      _looping = false;
      _speaking = null;
    });
    await _audio.stopPronunciation();
  }

  /// Reads [words] one after another, forever, until stopped.
  ///
  /// The queue prepares ten words of audio while the current one sounds, so a
  /// word whose clip has to be read from the archive (or fetched) is ready the
  /// moment the gap is over — the pause is the configured one, not that plus a
  /// download.
  Future<void> _startLoop(List<String> words) async {
    if (words.isEmpty || _looping) return;
    final accent = context.read<VocabularyProvider>().accent;
    final token = ++_loopToken;
    setState(() => _looping = true);
    final prepared = <int, PreparedPronunciation>{};
    try {
      while (mounted && token == _loopToken) {
        await PrefetchQueue(window: prefetchWindow).run(
          words.length,
          isCancelled: () => !mounted || token != _loopToken,
          onStart: (index) => setState(() => _speaking = words[index]),
          prepare: (index) async {
            prepared[index] =
                await _audio.prepareWord(word: words[index], accent: accent);
          },
          play: (index) async {
            final clip = prepared.remove(index) ??
                await _audio.prepareWord(word: words[index], accent: accent);
            await _audio.playPrepared(clip);
          },
          gap: const Duration(milliseconds: 350),
        );
        // Round the list off with the same pause it had between words.
        if (mounted && token == _loopToken) {
          await Future<void>.delayed(const Duration(milliseconds: 350));
        }
      }
    } finally {
      if (mounted && token == _loopToken) {
        setState(() {
          _looping = false;
          _speaking = null;
        });
      }
    }
  }

  Future<void> _lookUp(String word) async {
    setState(() => _lookup = word);
    await context.read<DictionaryProvider>().lookupWord(
          word,
          addToHistory: false,
          remember: false,
        );
  }

  @override
  Widget build(BuildContext context) {
    final vocabulary = context.watch<VocabularyProvider>();
    final words = vocabulary.arrange(vocabulary.filtered(_words));

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 940;
        final panel = _lookup == null ? null : _buildLookup(context);
        if (panel != null && !wide) {
          // A phone has no room for three columns: the entry takes the page.
          return panel;
        }
        return Column(
          children: [
            _buildToolbar(context, vocabulary, words.length),
            Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
            Expanded(
              child: Row(
                children: [
                  Expanded(child: _buildTable(context, vocabulary, words)),
                  if (panel != null) ...[
                    const VerticalDivider(width: 1),
                    SizedBox(width: 400, child: panel),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildToolbar(
    BuildContext context,
    VocabularyProvider vocabulary,
    int shown,
  ) {
    final theme = Theme.of(context);
    final total = _words.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildToolbarTop(context, vocabulary, shown, total, theme),
          const SizedBox(height: 4),
          _buildDrillRow(context, vocabulary, shown),
        ],
      ),
    );
  }

  /// 循环朗读 / 美英音 / 打乱顺序 — the controls that act on the whole list.
  Widget _buildDrillRow(
    BuildContext context,
    VocabularyProvider vocabulary,
    int shown,
  ) {
    final theme = Theme.of(context);
    return Row(
      children: [
        FilledButton.tonalIcon(
          icon: Icon(_looping ? Icons.stop_rounded : Icons.play_arrow_rounded,
              size: 18),
          label: Text(
            _looping ? '停止朗读' : '循环朗读 $shown 词',
            style: const TextStyle(fontSize: 12.5),
          ),
          onPressed: shown == 0
              ? null
              : () => _looping
                  ? _stopLoop()
                  : _startLoop(vocabulary.arrange(
                      vocabulary.filtered(_words))),
        ),
        const SizedBox(width: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'us', label: Text('美音', style: TextStyle(fontSize: 12))),
            ButtonSegment(value: 'uk', label: Text('英音', style: TextStyle(fontSize: 12))),
          ],
          selected: {vocabulary.accent},
          onSelectionChanged: (selection) =>
              vocabulary.setAccent(selection.first),
          showSelectedIcon: false,
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: WidgetStatePropertyAll(const TextStyle(fontSize: 12)),
          ),
        ),
        const SizedBox(width: 8),
        TextButton.icon(
          icon: Icon(
            vocabulary.isShuffled ? Icons.sort_rounded : Icons.shuffle_rounded,
            size: 16,
          ),
          label: Text(
            vocabulary.isShuffled ? '恢复原序' : '打乱顺序',
            style: const TextStyle(fontSize: 12),
          ),
          onPressed: () => vocabulary.isShuffled
              ? vocabulary.restoreOrder()
              : vocabulary.shuffle(_words),
        ),
        const Spacer(),
        if (_speaking != null)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.graphic_eq_rounded, size: 15, color: theme.colorScheme.error),
              const SizedBox(width: 4),
              Text(
                _speaking!,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildToolbarTop(
    BuildContext context,
    VocabularyProvider vocabulary,
    int shown,
    int total,
    ThemeData theme,
  ) {
    return Padding(
      padding: EdgeInsets.zero,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${scene.label} · $total 词',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                Text(
                  '显示 $shown 词 · 带星 ${vocabulary.starredCount} 词',
                  style: TextStyle(fontSize: 11.5, color: theme.hintColor),
                ),
              ],
            ),
          ),
          _buildStarFilter(context, vocabulary),
          const SizedBox(width: 4),
          TextButton.icon(
            icon: Icon(
              vocabulary.revealAll
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              size: 16,
            ),
            label: Text(
              vocabulary.revealAll ? '全部隐藏' : '全部显示',
              style: const TextStyle(fontSize: 12),
            ),
            onPressed: vocabulary.toggleRevealAll,
          ),
        ],
      ),
    );
  }

  Widget _buildStarFilter(BuildContext context, VocabularyProvider vocabulary) {
    final current = vocabulary.filter;
    final label = switch (current) {
      StarFilter.all => '星数：不限',
      StarFilter.starred => '只看带星',
      StarFilter.exact => '恰好 ${vocabulary.filterStars} 星',
      StarFilter.atLeast => '≥ ${vocabulary.filterStars} 星',
    };
    final options = <({StarFilter filter, int stars})>[
      (filter: StarFilter.all, stars: vocabulary.filterStars),
      (filter: StarFilter.starred, stars: vocabulary.filterStars),
      for (var n = 1; n <= VocabularyProvider.maxStars; n++)
        (filter: StarFilter.exact, stars: n),
      for (var n = 1; n <= VocabularyProvider.maxStars; n++)
        (filter: StarFilter.atLeast, stars: n),
    ];
    String labelOf(({StarFilter filter, int stars}) option) =>
        switch (option.filter) {
          StarFilter.all => '不限',
          StarFilter.starred => '只看带星',
          StarFilter.exact => '恰好 ${option.stars} 星',
          StarFilter.atLeast => '≥ ${option.stars} 星',
        };

    return PopupMenuButton<({StarFilter filter, int stars})>(
      tooltip: '按星数筛选',
      initialValue: (filter: current, stars: vocabulary.filterStars),
      onSelected: (option) =>
          vocabulary.setFilter(option.filter, stars: option.stars),
      itemBuilder: (_) => [
        for (final option in options)
          PopupMenuItem(
            value: option,
            child: Text(labelOf(option), style: const TextStyle(fontSize: 13)),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.filter_alt_outlined, size: 16),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontSize: 12)),
            const Icon(Icons.arrow_drop_down_rounded, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildTable(
    BuildContext context,
    VocabularyProvider vocabulary,
    List<String> words,
  ) {
    final theme = Theme.of(context);
    if (words.isEmpty) {
      return Center(
        child: Text(
          vocabulary.filter == StarFilter.all
              ? '这个主题还没有词'
              : '没有符合星数筛选的词，换个筛选或先给词加星',
          style: TextStyle(fontSize: 13, color: theme.hintColor),
        ),
      );
    }
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
          child: Row(
            children: [
              const SizedBox(width: 100),
              Text('词汇', style: TextStyle(fontSize: 11.5, color: theme.hintColor)),
              const Spacer(),
              Text('释义', style: TextStyle(fontSize: 11.5, color: theme.hintColor)),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: words.length,
            itemBuilder: (context, index) {
              final word = words[index];
              return _buildRow(context, vocabulary, word);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildRow(
    BuildContext context,
    VocabularyProvider vocabulary,
    String word,
  ) {
    final theme = Theme.of(context);
    final stars = vocabulary.starsOf(word);
    final revealed = vocabulary.isRevealed(word);
    final gloss = _glosses[word] ?? '';
    final border = BorderSide(color: theme.dividerColor.withValues(alpha: 0.35));

    return InkWell(
      onTap: () => vocabulary.toggleGloss(word),
      child: Container(
        decoration: BoxDecoration(border: Border(bottom: border)),
        padding: const EdgeInsets.fromLTRB(8, 2, 12, 2),
        child: Row(
          children: [
            SizedBox(
              width: 100,
              child: Row(
                children: [
                  _starButton(
                    icon: Icons.remove_circle_outline,
                    tooltip: '减一颗星',
                    onPressed: stars > 0 ? () => vocabulary.removeStar(word) : null,
                  ),
                  SizedBox(
                    width: 58,
                    child: Text(
                      '${'★' * stars}${'☆' * (VocabularyProvider.maxStars - stars)}',
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.1,
                        letterSpacing: 0,
                        color: stars > 0
                            ? theme.colorScheme.primary
                            : theme.hintColor,
                      ),
                    ),
                  ),
                  _starButton(
                    icon: Icons.add_circle_outline,
                    tooltip: '加一颗星',
                    onPressed: stars < VocabularyProvider.maxStars
                        ? () => vocabulary.addStar(word)
                        : null,
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      word,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: stars > 0 ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: Icon(
                      _speaking == word
                          ? Icons.volume_up_rounded
                          : Icons.volume_up_outlined,
                      size: 16,
                    ),
                    tooltip: '${vocabulary.accentLabel}发音',
                    visualDensity: VisualDensity.compact,
                    color: _speaking == word ? theme.colorScheme.error : null,
                    onPressed: () => _playWord(word),
                  ),
                  IconButton(
                    icon: const Icon(Icons.search_rounded, size: 16),
                    tooltip: '查词典',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _lookUp(word),
                  ),
                ],
              ),
            ),
            const VerticalDivider(width: 12),
            Expanded(
              flex: 4,
              child: revealed
                  ? Text(
                      gloss.isEmpty ? '—' : gloss,
                      style: const TextStyle(fontSize: 12.5, height: 1.35),
                    )
                  : Text(
                      '点击显示释义',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.hintColor,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _starButton({
    required IconData icon,
    required String tooltip,
    VoidCallback? onPressed,
  }) {
    return IconButton(
      icon: Icon(icon, size: 15),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
      onPressed: onPressed,
    );
  }

  Widget _buildLookup(BuildContext context) {
    final word = _lookup!;
    final dictionary = context.watch<DictionaryProvider>();
    final theme = Theme.of(context);
    final entry = dictionary.currentWord == word ? dictionary.currentEntry : null;
    final loading = dictionary.isLoadingEntry || dictionary.currentWord != word;

    return Container(
      color: theme.colorScheme.surface,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    word,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  tooltip: '关闭词典释义',
                  onPressed: () => setState(() => _lookup = null),
                ),
              ],
            ),
          ),
          // The entry's own speaker links rely on a font the packaged stylesheet
          // does not ship, so the window gives the word a pronunciation bar of
          // its own — the same one the dictionary module uses.
          if (entry != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 2),
              child: Align(
                alignment: Alignment.centerLeft,
                child: PronunciationBar(
                  word: entry.word,
                  phonetic: entry.phonetic,
                  phonetics: entry.phonetics,
                  soundKey: entry.soundKey,
                  soundKeys: entry.soundKeys,
                ),
              ),
            ),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : entry == null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            dictionary.hasDictionaries
                                ? '没有找到「$word」的词条'
                                : '还没有加载词典，请在主窗口的词典管理里添加',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: theme.hintColor,
                            ),
                          ),
                        ),
                      )
                    : WordDefinitionView(entry: entry),
          ),
        ],
      ),
    );
  }
}
