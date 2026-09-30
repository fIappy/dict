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
    final phonemes = ipaProvider.filteredPhonemes;

    return Scaffold(
      appBar: isPaneView
          ? null
          : AppBar(
              title: const Text('国际音标 (IPA) 学习', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
      body: Column(
        children: [
          // Category Filter Chips
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
                    Icon(Icons.graphic_eq_rounded, color: theme.colorScheme.primary, size: 18),
                    const SizedBox(width: 8),
                    const Text(
                      'IPA 音标分类 (48音标)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    FilterChip(
                      selected: selectedCat == null,
                      label: const Text('全部 (48)', style: TextStyle(fontSize: 12)),
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onSelected: (_) => ipaProvider.selectCategory(null),
                    ),
                    for (final cat in IpaCategory.values)
                      FilterChip(
                        selected: selectedCat == cat,
                        label: Text(
                          '${cat.labelZh} (${IpaData.getByCategory(cat).length})',
                          style: const TextStyle(fontSize: 12),
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
                childAspectRatio: 1.5,
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
    final firstExample = phoneme.examples.isNotEmpty ? phoneme.examples.first : null;

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
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    phoneme.symbol,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Gentium Plus DC',
                      color: isSelected
                          ? theme.colorScheme.primary
                          : (isDark ? Colors.white : Colors.black87),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: _getPhonemeBadgeColor(phoneme, isDark),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      phoneme.category == IpaCategory.monophthong
                          ? (phoneme.symbol.contains('ː') ? '长元音' : '短元音')
                          : phoneme.category.labelZh,
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (firstExample != null)
                    Expanded(
                      child: Row(
                        children: [
                          Text(
                            firstExample.word,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              firstExample.phonetic,
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.hintColor,
                                fontFamily: 'Gentium Plus DC',
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  IconButton(
                    icon: const Icon(Icons.volume_up_rounded, size: 16),
                    tooltip: '试听音标发音',
                    splashRadius: 14,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                    onPressed: () => AudioManager().playIpaPhoneme(phoneme.audioAssetKey),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getPhonemeBadgeColor(IpaPhoneme phoneme, bool isDark) {
    if (phoneme.category == IpaCategory.monophthong) {
      return phoneme.symbol.contains('ː')
          ? const Color(0xFF1D4ED8) // Deep Blue for Long Vowels
          : const Color(0xFF0284C7); // Cyan / Sky Blue for Short Vowels
    }
    switch (phoneme.category) {
      case IpaCategory.monophthong:
        return const Color(0xFF2563EB);
      case IpaCategory.diphthong:
        return const Color(0xFF7C3AED); // Purple
      case IpaCategory.plosive:
        return const Color(0xFFDC2626); // Red
      case IpaCategory.fricative:
        return const Color(0xFFD97706); // Amber
      case IpaCategory.affricate:
        return const Color(0xFF059669); // Emerald
      case IpaCategory.nasal:
        return const Color(0xFF0891B2); // Cyan
      case IpaCategory.approximant:
        return const Color(0xFF4F46E5); // Indigo
    }
  }
}
