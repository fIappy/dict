import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/audio/audio_manager.dart';
import '../../core/alphabet/alphabet_model.dart';
import '../../providers/dictionary_provider.dart';
import 'word_detail_screen.dart';

class AlphabetDetailView extends StatelessWidget {
  final AlphabetLetter letter;
  final bool isPaneView;

  const AlphabetDetailView({
    super.key,
    required this.letter,
    this.isPaneView = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final audio = AudioManager();

    final content = SelectionArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Hero Card: Letter, Pronunciations, Rhyme group
            Card(
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
                        // Big Letter Avatar
                        Material(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(16),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => audio.playLetter(letter.audioKey, accent: 'us'),
                            child: Container(
                              width: 84,
                              height: 84,
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
                                    letter.displayLetter,
                                    style: const TextStyle(
                                      fontSize: 30,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                      letterSpacing: 2,
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

                        // Title, Phonetics & US/UK Audio buttons
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    '字母 ${letter.upper}',
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  IconButton(
                                    icon: const Icon(Icons.copy_rounded, size: 18),
                                    tooltip: '复制字母',
                                    onPressed: () {
                                      Clipboard.setData(ClipboardData(text: letter.upper));
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('已复制字母 ${letter.upper}')),
                                      );
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),

                              // US and UK Audio Buttons
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                children: [
                                  FilledButton.tonalIcon(
                                    icon: const Icon(Icons.volume_up_rounded, size: 16),
                                    label: Text('美音 ${letter.usNameIpa}', style: const TextStyle(fontSize: 12.5)),
                                    style: FilledButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      minimumSize: Size.zero,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    onPressed: () => audio.playLetter(letter.audioKey, accent: 'us'),
                                  ),
                                  OutlinedButton.icon(
                                    icon: const Icon(Icons.volume_up_outlined, size: 16),
                                    label: Text('英音 ${letter.ukNameIpa}', style: const TextStyle(fontSize: 12.5)),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      minimumSize: Size.zero,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    onPressed: () => audio.playLetter(letter.audioKey, accent: 'uk'),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: letter.isVowel
                                          ? const Color(0xFF1D4ED8)
                                          : (letter.isSemiVowel ? const Color(0xFF7C3AED) : const Color(0xFF0F766E)),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      letter.typeLabel,
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.primaryContainer,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      letter.rhymeGroup,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: theme.colorScheme.onPrimaryContainer,
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
                    const SizedBox(height: 10),

                    // Tips
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.tips_and_updates_outlined, size: 18, color: Colors.amber[700]),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            letter.tips,
                            style: const TextStyle(fontSize: 13.5, height: 1.55),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // 2. Phonics Rules Card (自然拼读读音与发音规则)
            Card(
              elevation: 0,
              color: isDark ? const Color(0xFF1E2430) : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.auto_stories_rounded, size: 18, color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        const Text(
                          '自然拼读核心规律 (Phonics)',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        letter.phonicsSummary,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Rules List
                    for (int i = 0; i < letter.phonicsRules.length; i++) ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              radius: 8,
                              backgroundColor: theme.colorScheme.primaryContainer,
                              child: Text(
                                '${i + 1}',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                letter.phonicsRules[i],
                                style: const TextStyle(fontSize: 13.5, height: 1.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // 3. Representative Words with Audio
            Row(
              children: [
                Icon(Icons.menu_book_rounded, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  '代表性词汇 (${letter.examples.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(width: 8),
                Text(
                  '点击喇叭收听读音，点击卡片查看词典释义',
                  style: TextStyle(fontSize: 12, color: theme.hintColor),
                ),
              ],
            ),
            const SizedBox(height: 10),

            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: letter.examples.map((item) {
                return Material(
                  color: isDark ? const Color(0xFF1E2430) : Colors.white,
                  borderRadius: BorderRadius.circular(10),
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
        ),
      ),
    );

    if (isPaneView) {
      return content;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('字母发音与规则: ${letter.displayLetter}'),
      ),
      body: content,
    );
  }
}
