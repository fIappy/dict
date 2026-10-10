import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/audio/audio_manager.dart';
import '../../core/ipa/ipa_data.dart';
import '../../core/ipa/ipa_model.dart';
import '../../providers/ipa_provider.dart';
import 'ipa_detail_view.dart';

class IpaScreen extends StatelessWidget {
  final bool isPaneView;
  final void Function(IpaPhoneme phoneme)? onSelectPhoneme;

  const IpaScreen({
    super.key,
    this.isPaneView = false,
    this.onSelectPhoneme,
  });

  void _onPhonemeTapped(BuildContext context, IpaPhoneme phoneme) {
    final ipaProvider = context.read<IpaProvider>();
    ipaProvider.selectPhoneme(phoneme.symbol);

    if (onSelectPhoneme != null) {
      onSelectPhoneme!(phoneme);
    } else if (!isPaneView) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => IpaDetailView(phoneme: phoneme),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final ipaProvider = context.watch<IpaProvider>();

    final selectedCat = ipaProvider.selectedCategory;
    final selectedAccent = ipaProvider.selectedAccent;
    final phonemes = ipaProvider.filteredPhonemes;

    return Scaffold(
      appBar: isPaneView
          ? null
          : AppBar(
              title: const Text('剑桥国际音标 (IPA) 学习', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
      body: Column(
        children: [
          // Filter Header: Accents & Categories
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
                // Accent Filter Bar
                Row(
                  children: [
                    Icon(Icons.public_rounded, color: theme.colorScheme.primary, size: 17),
                    const SizedBox(width: 6),
                    const Text(
                      '发音体系:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            ChoiceChip(
                              label: const Text('全部体系', style: TextStyle(fontSize: 12)),
                              selected: selectedAccent == null,
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              onSelected: (_) => ipaProvider.selectAccent(null),
                            ),
                            const SizedBox(width: 6),
                            ChoiceChip(
                              avatar: const Text('🇬🇧', style: TextStyle(fontSize: 11)),
                              label: const Text('英音体系 (UK)', style: TextStyle(fontSize: 12)),
                              selected: selectedAccent == IpaAccent.ukOnly,
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              onSelected: (_) => ipaProvider.selectAccent(
                                selectedAccent == IpaAccent.ukOnly ? null : IpaAccent.ukOnly,
                              ),
                            ),
                            const SizedBox(width: 6),
                            ChoiceChip(
                              avatar: const Text('🇺🇸', style: TextStyle(fontSize: 11)),
                              label: const Text('美音体系 (US)', style: TextStyle(fontSize: 12)),
                              selected: selectedAccent == IpaAccent.usOnly,
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              onSelected: (_) => ipaProvider.selectAccent(
                                selectedAccent == IpaAccent.usOnly ? null : IpaAccent.usOnly,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Category Filter Chips
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    FilterChip(
                      selected: selectedCat == null,
                      label: Text('全部分类 (${phonemes.length})', style: const TextStyle(fontSize: 11.5)),
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onSelected: (_) => ipaProvider.selectCategory(null),
                    ),
                    for (final cat in IpaCategory.values)
                      FilterChip(
                        selected: selectedCat == cat,
                        label: Text(
                          '${cat.labelZh} (${IpaData.getByCategory(cat).length})',
                          style: const TextStyle(fontSize: 11.5),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        onSelected: (_) => ipaProvider.selectCategory(cat),
                      ),
                  ],
                ),
              ],
            ),
          ),

          // IPA Cards Grid
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 1.28,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: phonemes.length,
              itemBuilder: (context, index) {
                final p = phonemes[index];
                final isSelected = ipaProvider.selectedSymbol == p.symbol;
                return _buildIpaCard(context, p, isSelected, theme, isDark);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIpaCard(
    BuildContext context,
    IpaPhoneme phoneme,
    bool isSelected,
    ThemeData theme,
    bool isDark,
  ) {
    final audio = AudioManager();
    final exampleWord = phoneme.cambridgeExampleWord.isNotEmpty
        ? phoneme.cambridgeExampleWord
        : (phoneme.examples.isNotEmpty ? phoneme.examples.first.word : '');
    final ukP = phoneme.cambridgeUkPhonetic.isNotEmpty
        ? phoneme.cambridgeUkPhonetic
        : (phoneme.examples.isNotEmpty ? phoneme.examples.first.ukPhonetic : '');
    final usP = phoneme.cambridgeUsPhonetic.isNotEmpty
        ? phoneme.cambridgeUsPhonetic
        : (phoneme.examples.isNotEmpty ? phoneme.examples.first.usPhonetic : '');

    return Material(
      color: isSelected
          ? theme.colorScheme.primaryContainer.withValues(alpha: isDark ? 0.35 : 0.6)
          : (isDark ? const Color(0xFF1E2430) : Colors.white),
      borderRadius: BorderRadius.circular(12),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _onPhonemeTapped(context, phoneme),
        child: Container(
          padding: const EdgeInsets.all(10),
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
              // Top Row: Big Symbol & Badges
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    phoneme.symbol,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Gentium Plus DC',
                      color: isSelected
                          ? theme.colorScheme.primary
                          : (isDark ? Colors.white : Colors.black87),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Accent badge
                      _buildAccentBadge(phoneme.accent),
                      const SizedBox(width: 4),
                      // Category badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: _getPhonemeBadgeColor(phoneme, isDark),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          phoneme.category == IpaCategory.monophthong
                              ? (phoneme.symbol.contains('ː') ? '长元音' : '短元音')
                              : phoneme.category.labelZh,
                          style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              // Middle: Pure Phoneme Audio Button & Note
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () {
                      final targetAccent = phoneme.accent == IpaAccent.usOnly ? 'us' : 'uk';
                      audio.playIpaPhoneme(phoneme.audioAssetKey, accent: targetAccent);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: isDark ? 0.2 : 0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: theme.colorScheme.primary.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.volume_up_rounded, size: 14, color: theme.colorScheme.primary),
                          const SizedBox(width: 3),
                          Text(
                            '音标读音',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (phoneme.counterpartSymbol != null)
                    Flexible(
                      child: Text(
                        phoneme.accent == IpaAccent.ukOnly
                            ? '美:${phoneme.counterpartSymbol}'
                            : '英:${phoneme.counterpartSymbol}',
                        style: TextStyle(fontSize: 10, color: theme.hintColor),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),

              const Divider(height: 1),

              // Bottom Row: Example Word with UK/US audio
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '例: $exampleWord',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          ukP != usP && usP.isNotEmpty ? '🇬🇧$ukP 🇺🇸$usP' : ukP,
                          style: TextStyle(
                            fontSize: 10,
                            color: theme.hintColor,
                            fontFamily: 'Gentium Plus DC',
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.music_note_rounded, size: 16),
                    tooltip: '试听例词发音: $exampleWord',
                    splashRadius: 14,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                    onPressed: () {
                      final acc = phoneme.accent == IpaAccent.usOnly ? 'us' : 'uk';
                      audio.playWord(word: exampleWord, accent: acc);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAccentBadge(IpaAccent accent) {
    Color bg;
    String label;
    switch (accent) {
      case IpaAccent.ukOnly:
        bg = const Color(0xFF1E40AF); // Deep blue
        label = '🇬🇧 英音';
        break;
      case IpaAccent.usOnly:
        bg = const Color(0xFFB45309); // Amber
        label = '🇺🇸 美音';
        break;
      case IpaAccent.both:
        bg = const Color(0xFF0F766E); // Teal
        label = '🌐 通用';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.white),
      ),
    );
  }

  Color _getPhonemeBadgeColor(IpaPhoneme phoneme, bool isDark) {
    if (phoneme.category == IpaCategory.monophthong) {
      return phoneme.symbol.contains('ː')
          ? const Color(0xFF1D4ED8)
          : const Color(0xFF0284C7);
    }
    switch (phoneme.category) {
      case IpaCategory.monophthong:
        return const Color(0xFF2563EB);
      case IpaCategory.diphthong:
        return const Color(0xFF7C3AED);
      case IpaCategory.plosive:
        return const Color(0xFFDC2626);
      case IpaCategory.fricative:
        return const Color(0xFFD97706);
      case IpaCategory.affricate:
        return const Color(0xFF059669);
      case IpaCategory.nasal:
        return const Color(0xFF0891B2);
      case IpaCategory.approximant:
        return const Color(0xFF4F46E5);
    }
  }
}
