import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/audio/audio_manager.dart';
import '../../core/ipa/ipa_model.dart';
import '../../providers/dictionary_provider.dart';
import 'word_detail_screen.dart';

class IpaDetailView extends StatelessWidget {
  final IpaPhoneme phoneme;
  final bool isPaneView;

  const IpaDetailView({
    super.key,
    required this.phoneme,
    this.isPaneView = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final content = SelectionArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Top Hero Card (Phoneme symbol & articulatory guide)
            _buildHeroCard(context, theme, isDark),
            const SizedBox(height: 20),

            // 2. Common Spelling Patterns
            if (phoneme.commonSpellings.isNotEmpty) ...[
              _buildSpellingPatternsCard(theme, isDark),
              const SizedBox(height: 20),
            ],

            // 3. Example Words with Audio
            _buildExampleWordsSection(context, theme, isDark),
            const SizedBox(height: 24),

            // 4. Phoneme Combinations (与其它音标的组合发音)
            if (phoneme.combinations.isNotEmpty) ...[
              _buildCombinationsSection(context, theme, isDark),
              const SizedBox(height: 24),
            ],
          ],
        ),
      ),
    );

    if (isPaneView) {
      return content;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('音标详解: ${phoneme.symbol}'),
      ),
      body: content,
    );
  }

  Widget _buildHeroCard(BuildContext context, ThemeData theme, bool isDark) {
    final audio = AudioManager();

    return Card(
      elevation: 0,
      color: isDark ? const Color(0xFF1E2430) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Big IPA Symbol Avatar
                // Big IPA Symbol Avatar (Tap to play pure phoneme sound)
                Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => audio.playIpaPhoneme(phoneme.audioAssetKey),
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            theme.colorScheme.primary,
                            theme.colorScheme.tertiary,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: theme.colorScheme.primary.withValues(alpha: 0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Text(
                            phoneme.rawSymbol,
                            style: const TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              fontFamily: 'Gentium Plus DC',
                            ),
                          ),
                          const Positioned(
                            bottom: 4,
                            right: 4,
                            child: Icon(Icons.volume_up_rounded, color: Colors.white70, size: 16),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),

                // Meta Info & Classification
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            phoneme.symbol,
                            style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              fontFamily: 'Gentium Plus DC',
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.tonalIcon(
                            icon: const Icon(Icons.volume_up_rounded, size: 18),
                            label: const Text('播放音标原声', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () => audio.playIpaPhoneme(phoneme.audioAssetKey),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy_rounded, size: 18),
                            tooltip: '复制音标',
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: phoneme.symbol));
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('已复制音标 ${phoneme.symbol}')),
                              );
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              phoneme.subCategory,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              phoneme.voiceType,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: isDark ? Colors.white70 : Colors.black87,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),

            // Articulatory Advice (发音技巧)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lightbulb_outline_rounded, size: 20, color: Colors.amber[700]),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '发音要领与技巧',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        phoneme.description,
                        style: const TextStyle(fontSize: 13.5, height: 1.6),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Mouth & Tongue Shape (唇形与舌位)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.record_voice_over_outlined, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '口型与舌位',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        phoneme.mouthShape,
                        style: TextStyle(
                          fontSize: 13.5,
                          height: 1.6,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpellingPatternsCard(ThemeData theme, bool isDark) {
    return Card(
      elevation: 0,
      color: isDark ? const Color(0xFF1E2430) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.spellcheck_rounded, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                const Text(
                  '常见字母及组合拼写规则',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: phoneme.commonSpellings.map((sp) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isDark ? Colors.white10 : Colors.black12,
                    ),
                  ),
                  child: Text(
                    sp,
                    style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExampleWordsSection(BuildContext context, ThemeData theme, bool isDark) {
    final audio = AudioManager();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.menu_book_rounded, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              '核心示例单词 (${phoneme.examples.length})',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(width: 8),
            Text(
              '点击喇叭收听读音，点击卡片直达词典释义',
              style: TextStyle(fontSize: 12, color: theme.hintColor),
            ),
          ],
        ),
        const SizedBox(height: 10),

        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: phoneme.examples.map((item) {
            return Material(
              color: isDark ? const Color(0xFF1E2430) : Colors.white,
              borderRadius: BorderRadius.circular(10),
              elevation: 0,
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () {
                  context.read<DictionaryProvider>().lookupWord(item.word);
                  if (!isPaneView) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => WordDetailScreen(word: item.word),
                      ),
                    );
                  }
                },
                child: Container(
                  width: 175,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              item.word,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.volume_up_rounded, size: 17),
                            tooltip: '播放读音',
                            splashRadius: 14,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                            onPressed: () => audio.playWord(word: item.word),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        item.phonetic,
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.colorScheme.primary,
                          fontFamily: 'Gentium Plus DC',
                        ),
                      ),
                      if (item.meaning != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          item.meaning!,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildCombinationsSection(BuildContext context, ThemeData theme, bool isDark) {
    final audio = AudioManager();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.hub_outlined, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            const Text(
              '与其它音标的组合发音与连读规则',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '涵盖声母拼读、辅音连缀、尾音闭合及不送气浊化等高频组合',
          style: TextStyle(fontSize: 12, color: theme.hintColor),
        ),
        const SizedBox(height: 12),

        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: phoneme.combinations.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final combo = phoneme.combinations[index];

            return Card(
              elevation: 0,
              color: isDark ? const Color(0xFF1E2430) : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Combination Header
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            combo.category,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            combo.formula,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14.5,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Explanation
                    Text(
                      combo.explanation,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white70 : Colors.black87,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Combination Example Word Pills
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: combo.words.map((w) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isDark ? Colors.white12 : const Color(0xFFCBD5E1),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        w.word,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13.5,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        w.phonetic,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: theme.colorScheme.primary,
                                          fontFamily: 'Gentium Plus DC',
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (w.meaning != null) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      w.meaning!,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: theme.hintColor,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(width: 6),
                              IconButton(
                                icon: const Icon(Icons.volume_up_rounded, size: 16),
                                tooltip: '播放',
                                splashRadius: 14,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                                onPressed: () => audio.playWord(word: w.word),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
