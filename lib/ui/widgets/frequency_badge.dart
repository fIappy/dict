import 'package:flutter/material.dart';
import '../../core/frequency/frequency_service.dart';

class FrequencyBadge extends StatelessWidget {
  final WordFrequencyInfo? info;

  const FrequencyBadge({super.key, this.info});

  @override
  Widget build(BuildContext context) {
    if (info == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // CEFR Level Chip
        if (info!.cefr != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: _getCefrColor(info!.cefr!, isDark),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              info!.cefr!,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
          ),

        // Frequency Rank Chip
        if (info!.rank != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2D3748) : const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isDark ? Colors.white12 : Colors.black12,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.trending_up,
                  size: 12,
                  color: isDark ? Colors.amber[300] : Colors.orange[800],
                ),
                const SizedBox(width: 4),
                Text(
                  info!.frequencyLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.grey[200] : Colors.grey[800],
                  ),
                ),
              ],
            ),
          ),

        // Collins Stars
        if (info!.collins != null || info!.rank != null)
          Text(
            info!.collinsStars,
            style: const TextStyle(
              color: Color(0xFFF59E0B),
              fontSize: 12,
              letterSpacing: 1,
            ),
          ),

        // Exam tags
        for (final tag in info!.examTags)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
            decoration: BoxDecoration(
              color: _getExamTagColor(tag, isDark),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              tag,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: _getExamTagTextColor(tag, isDark),
              ),
            ),
          ),
      ],
    );
  }

  Color _getCefrColor(String cefr, bool isDark) {
    switch (cefr.toUpperCase()) {
      case 'A1':
      case 'A2':
        return isDark ? const Color(0xFF15803D) : const Color(0xFF16A34A); // Green
      case 'B1':
      case 'B2':
        return isDark ? const Color(0xFF1D4ED8) : const Color(0xFF2563EB); // Blue
      case 'C1':
      case 'C2':
        return isDark ? const Color(0xFF7E22CE) : const Color(0xFF9333EA); // Purple
      default:
        return Colors.blueGrey;
    }
  }

  Color _getExamTagColor(String tag, bool isDark) {
    if (tag.contains('CET') || tag.contains('四') || tag.contains('六')) {
      return isDark ? const Color(0x333B82F6) : const Color(0xFFEFF6FF);
    } else if (tag.contains('GRE') || tag.contains('托福') || tag.contains('TOEFL')) {
      return isDark ? const Color(0x33EF4444) : const Color(0xFFFEF2F2);
    } else if (tag.contains('雅思') || tag.contains('IELTS')) {
      return isDark ? const Color(0x3310B981) : const Color(0xFFECFDF5);
    } else if (tag.contains('考研')) {
      return isDark ? const Color(0x33F59E0B) : const Color(0xFFFFFBEB);
    }
    return isDark ? Colors.white10 : const Color(0xFFF1F5F9);
  }

  Color _getExamTagTextColor(String tag, bool isDark) {
    if (tag.contains('CET') || tag.contains('四') || tag.contains('六')) {
      return isDark ? const Color(0xFF93C5FD) : const Color(0xFF1D4ED8);
    } else if (tag.contains('GRE') || tag.contains('托福') || tag.contains('TOEFL')) {
      return isDark ? const Color(0xFFFCA5A5) : const Color(0xFFB91C1C);
    } else if (tag.contains('雅思') || tag.contains('IELTS')) {
      return isDark ? const Color(0xFF6EE7B7) : const Color(0xFF047857);
    } else if (tag.contains('考研')) {
      return isDark ? const Color(0xFFFCD34D) : const Color(0xFFB45309);
    }
    return isDark ? Colors.white70 : Colors.black87;
  }
}
