import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/audio/audio_manager.dart';
import '../../core/ipa/ipa_data.dart';
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
            // 1. Top Hero Card (Phoneme symbol, accent classification & pure phoneme audio)
            _buildHeroCard(context, theme, isDark),
            const SizedBox(height: 18),

            // 2. UK vs US Contrast Card (If counterpart exists)
            if (phoneme.counterpartSymbol != null) ...[
              _buildContrastCard(theme, isDark),
              const SizedBox(height: 18),
            ],

            // 3. Common Spelling Patterns
            if (phoneme.commonSpellings.isNotEmpty) ...[
              _buildSpellingPatternsCard(theme, isDark),
              const SizedBox(height: 18),
            ],

            // 4. Example Words with UK/US Audio
            _buildExampleWordsSection(context, theme, isDark),
            const SizedBox(height: 24),

            // 5. Phoneme Combinations (与其它音标的组合发音)
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

  /// US side of the pure-phoneme pair.
  ///
  /// Cambridge ships a US recording only for the sounds US English has, so a
  /// UK-only row plays the counterpart entry (`/ɒ/` -> `/ɑː/`, `/ɜː/` -> `/ɝː/`,
  /// `/əʊ/` -> `/oʊ/`) and is disabled when there is none (`/ɪə/` `/eə/` `/ʊə/`),
  /// rather than being a button that silently plays nothing.
  Widget _usPhonemeButton(AudioManager audio, ThemeData theme) {
    final counterpart = phoneme.accent == IpaAccent.ukOnly
        ? IpaData.counterpartPhoneme(phoneme)
        : null;
    final enabled = phoneme.accent != IpaAccent.ukOnly || counterpart != null;
    final label = !enabled
        ? '美音无对应音标'
        : counterpart == null
            ? '试听美音纯音'
            : '美音转 ${counterpart.symbol}';
    return OutlinedButton.icon(
      icon: const Text('🇺🇸', style: TextStyle(fontSize: 14)),
      label: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
      ),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 8),
        side: BorderSide(
          color: enabled
              ? const Color(0xFFB45309)
              : Colors.grey.withValues(alpha: 0.3),
        ),
      ),
      onPressed: enabled
          ? () => audio.playIpaPhoneme(
                counterpart?.audioAssetKey ?? phoneme.audioAssetKey,
                accent: 'us',
              )
          : null,
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
                // Big IPA Symbol Avatar (Tap to play pure phoneme sound)
                Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      final acc = phoneme.accent == IpaAccent.usOnly ? 'us' : 'uk';
                      audio.playIpaPhoneme(phoneme.audioAssetKey, accent: acc);
                    },
                    child: Container(
                      width: 82,
                      height: 82,
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
                          const SizedBox(width: 10),
                          _buildAccentTag(phoneme.accent),
                          const Spacer(),
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

            // Pure Phoneme Audio Playback Section (明确标明：音标纯音示范，非单词读音)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.graphic_eq_rounded, size: 16, color: theme.colorScheme.primary),
                      const SizedBox(width: 6),
                      const Text(
                        '音标纯音示范 (非单词读音):',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      Text(
                        '基于剑桥发音标准',
                        style: TextStyle(fontSize: 11, color: theme.hintColor),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      // UK Phoneme Button
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Text('🇬🇧', style: TextStyle(fontSize: 14)),
                          label: Text(
                            phoneme.accent == IpaAccent.usOnly ? '英音无此音标' : '试听英音纯音',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            side: BorderSide(
                              color: phoneme.accent == IpaAccent.usOnly
                                  ? Colors.grey.withValues(alpha: 0.3)
                                  : const Color(0xFF1E40AF),
                            ),
                          ),
                          onPressed: phoneme.accent == IpaAccent.usOnly
                              ? null
                              : () => audio.playIpaPhoneme(phoneme.audioAssetKey, accent: 'uk'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // US Phoneme Button
                      Expanded(child: _usPhonemeButton(audio, theme)),
                    ],
                  ),
                ],
              ),
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

  Widget _buildAccentTag(IpaAccent accent) {
    Color bg;
    String label;
    switch (accent) {
      case IpaAccent.ukOnly:
        bg = const Color(0xFF1E40AF);
        label = '🇬🇧 英音标准音标';
        break;
      case IpaAccent.usOnly:
        bg = const Color(0xFFB45309);
        label = '🇺🇸 美音标准音标';
        break;
      case IpaAccent.both:
        bg = const Color(0xFF0F766E);
        label = '🌐 英美通用音标';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
      ),
    );
  }

  Widget _buildContrastCard(ThemeData theme, bool isDark) {
    final audio = AudioManager();
    final word = phoneme.cambridgeExampleWord.isNotEmpty ? phoneme.cambridgeExampleWord : 'word';

    return Card(
      elevation: 0,
      color: isDark ? const Color(0xFF172033) : const Color(0xFFEFF6FF),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isDark ? const Color(0xFF1E3A8A) : const Color(0xFFBFDBFE),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.compare_arrows_rounded, color: Color(0xFF2563EB), size: 20),
                const SizedBox(width: 8),
                const Text(
                  '英美发音体系对照与转换',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2563EB).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '对应: ${phoneme.counterpartSymbol ?? ""}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2563EB),
                    ),
                  ),
                ),
              ],
            ),
            if (phoneme.counterpartExplanation != null) ...[
              const SizedBox(height: 8),
              Text(
                phoneme.counterpartExplanation!,
                style: const TextStyle(fontSize: 13, height: 1.55),
              ),
            ],
            const SizedBox(height: 12),

            // Benchmark Word Audio Comparison
            if (phoneme.cambridgeExampleWord.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0F172A) : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '剑桥对照例词: $word',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '🇬🇧 ${phoneme.cambridgeUkPhonetic}   🇺🇸 ${phoneme.cambridgeUsPhonetic}',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.hintColor,
                              fontFamily: 'Gentium Plus DC',
                            ),
                          ),
                        ],
                      ),
                    ),
                    FilledButton.tonalIcon(
                      icon: const Text('🇬🇧', style: TextStyle(fontSize: 12)),
                      label: const Text('英音词', style: TextStyle(fontSize: 11.5)),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () => audio.playWord(word: word, accent: 'uk'),
                    ),
                    const SizedBox(width: 6),
                    FilledButton.tonalIcon(
                      icon: const Text('🇺🇸', style: TextStyle(fontSize: 12)),
                      label: const Text('美音词', style: TextStyle(fontSize: 11.5)),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () => audio.playWord(word: word, accent: 'us'),
                    ),
                  ],
                ),
              ),
            ],
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
            Expanded(
              child: Text(
                '🇬🇧 英音 / 🇺🇸 美音 独立试听，点击卡片查词',
                style: TextStyle(fontSize: 11.5, color: theme.hintColor),
                overflow: TextOverflow.ellipsis,
              ),
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
                  width: 195,
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
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              item.spellingPattern,
                              style: TextStyle(
                                fontSize: 10.5,
                                color: theme.colorScheme.primary,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (item.meaning != null) ...[
                        const SizedBox(height: 3),
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
                      const SizedBox(height: 8),

                      // UK Pronunciation Row
                      Row(
                        children: [
                          const Text('🇬🇧', style: TextStyle(fontSize: 12)),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              item.ukPhonetic,
                              style: const TextStyle(
                                fontSize: 12,
                                fontFamily: 'Gentium Plus DC',
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => audio.playWord(word: item.word, accent: 'uk'),
                            child: const Padding(
                              padding: EdgeInsets.all(2),
                              child: Icon(Icons.volume_up_rounded, size: 16, color: Color(0xFF1E40AF)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),

                      // US Pronunciation Row
                      Row(
                        children: [
                          const Text('🇺🇸', style: TextStyle(fontSize: 12)),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              item.usPhonetic,
                              style: const TextStyle(
                                fontSize: 12,
                                fontFamily: 'Gentium Plus DC',
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => audio.playWord(word: item.word, accent: 'us'),
                            child: const Padding(
                              padding: EdgeInsets.all(2),
                              child: Icon(Icons.volume_up_rounded, size: 16, color: Color(0xFFB45309)),
                            ),
                          ),
                        ],
                      ),
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

                    // Combination Words
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: combo.words.map((cw) {
                        return InkWell(
                          borderRadius: BorderRadius.circular(6),
                          onTap: () => audio.playWord(word: cw.word),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  cw.word,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  cw.phonetic,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: theme.colorScheme.primary,
                                    fontFamily: 'Gentium Plus DC',
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.volume_up_rounded,
                                  size: 14,
                                  color: theme.colorScheme.primary,
                                ),
                              ],
                            ),
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
