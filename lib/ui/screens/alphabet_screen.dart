import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/alphabet/alphabet_model.dart';
import '../../core/audio/audio_manager.dart';
import '../../providers/alphabet_provider.dart';
import 'alphabet_detail_view.dart';

class AlphabetScreen extends StatelessWidget {
  final bool isPaneView;
  final void Function(AlphabetLetter letter)? onSelectLetter;

  const AlphabetScreen({
    super.key,
    this.isPaneView = false,
    this.onSelectLetter,
  });

  void _onLetterTapped(BuildContext context, AlphabetLetter letter) {
    final provider = context.read<AlphabetProvider>();
    provider.selectLetter(letter.upper);

    if (onSelectLetter != null) {
      onSelectLetter!(letter);
    } else if (!isPaneView) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AlphabetDetailView(letter: letter),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final provider = context.watch<AlphabetProvider>();
    final letters = provider.filteredLetters;

    return Scaffold(
      appBar: isPaneView
          ? null
          : AppBar(
              title: const Text('26个英文字母发音', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
      body: Column(
        children: [
          // Filter Chips
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                  children: [
                    Icon(Icons.text_fields_rounded, color: theme.colorScheme.primary, size: 18),
                    const SizedBox(width: 8),
                    const Text(
                      '26个字母发音表',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: LetterCategory.values.map((cat) {
                    final isSel = provider.selectedCategory == cat;
                    return FilterChip(
                      selected: isSel,
                      label: Text(cat.label, style: const TextStyle(fontSize: 12)),
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onSelected: (_) => provider.selectCategory(cat),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),

          // 26 Letters Grid
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 1.35,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: letters.length,
              itemBuilder: (context, index) {
                final l = letters[index];
                final isSelected = provider.selectedChar == l.upper;
                return _buildLetterCard(context, l, isSelected, theme, isDark);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLetterCard(
    BuildContext context,
    AlphabetLetter letter,
    bool isSelected,
    ThemeData theme,
    bool isDark,
  ) {
    return Material(
      color: isSelected
          ? theme.colorScheme.primaryContainer.withValues(alpha: isDark ? 0.35 : 0.6)
          : (isDark ? const Color(0xFF1E2430) : Colors.white),
      borderRadius: BorderRadius.circular(12),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _onLetterTapped(context, letter),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? theme.colorScheme.primary
                  : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Text(
                          letter.displayLetter,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isSelected ? theme.colorScheme.primary : null,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            letter.nameIpa,
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.primary,
                              fontFamily: 'Gentium Plus DC',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: letter.isVowel
                          ? const Color(0xFF1D4ED8)
                          : (letter.isSemiVowel ? const Color(0xFF7C3AED) : const Color(0xFF0F766E)),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      letter.isVowel ? '元音' : (letter.isSemiVowel ? '半元' : '辅音'),
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      letter.rhymeGroup,
                      style: TextStyle(fontSize: 10.5, color: theme.hintColor),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.volume_up_rounded, size: 16),
                    tooltip: '试听美音',
                    splashRadius: 14,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                    onPressed: () => AudioManager().playLetter(letter.audioKey, accent: 'us'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
