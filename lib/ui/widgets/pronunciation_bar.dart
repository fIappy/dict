import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/audio/audio_manager.dart';
import 'speakable_selection.dart';

class PronunciationBar extends StatefulWidget {
  final String word;
  final String phonetic;
  final List<String> phonetics;
  final String? soundKey;
  final List<String> soundKeys;

  const PronunciationBar({
    super.key,
    required this.word,
    required this.phonetic,
    this.phonetics = const [],
    this.soundKey,
    this.soundKeys = const [],
  });

  @override
  State<PronunciationBar> createState() => _PronunciationBarState();
}

class _PronunciationBarState extends State<PronunciationBar> {
  final AudioManager _audio = AudioManager();
  String? _playingAccent;

  void _play(String accent, {String? customSoundKey}) {
    setState(() => _playingAccent = accent);
    _audio.playWord(
      word: widget.word,
      soundKey: customSoundKey ?? widget.soundKey,
      accent: accent,
      onStateChanged: (playing) {
        if (mounted) {
          setState(() {
            _playingAccent = playing ? accent : null;
          });
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasPhonetic = widget.phonetic.isNotEmpty;

    // Detect if there are secondary distinct pronunciations
    final secondaryVariants = <MapEntry<String, String?>>[];
    if (widget.phonetics.length > 1) {
      for (int i = 1; i < widget.phonetics.length; i++) {
        final p = widget.phonetics[i];
        if (p != widget.phonetic) {
          final sKey = i < widget.soundKeys.length ? widget.soundKeys[i] : null;
          secondaryVariants.add(MapEntry(p, sKey));
        }
      }
    }

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // 1. US Pronunciation Button (美音 / 本地离线MDD)
        _buildAccentPill(
          label: '美',
          accent: 'us',
          tooltip: '美音发音 (Dictionary.com 本地原声)',
          theme: theme,
          onTap: () => _play('us'),
        ),

        // 2. UK Pronunciation Button (英音)
        _buildAccentPill(
          label: '英',
          accent: 'uk',
          tooltip: '英音发音 (标准英式发音)',
          theme: theme,
          onTap: () => _play('uk'),
        ),

        // 3. Primary Phonetic Transcription
        if (hasPhonetic)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Tooltip(
              message: '点击复制音标',
              child: InkWell(
                borderRadius: BorderRadius.circular(4),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: widget.phonetic));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('已复制音标'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
                child: SpeakableText(
                  widget.phonetic,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontFamily: 'Gentium Plus DC',
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),

        // 4. Secondary heteronym pronunciations (e.g. lead [led], read [red])
        for (int idx = 0; idx < secondaryVariants.length; idx++) ...[
          _buildVariantPill(
            variant: secondaryVariants[idx],
            index: idx + 2,
            theme: theme,
          ),
        ],
      ],
    );
  }

  Widget _buildAccentPill({
    required String label,
    required String accent,
    required String tooltip,
    required ThemeData theme,
    required VoidCallback onTap,
  }) {
    final isThisPlaying = _playingAccent == accent;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: isThisPlaying
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isThisPlaying)
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.colorScheme.primary,
                    ),
                  )
                else
                  Icon(
                    Icons.volume_up_rounded,
                    size: 15,
                    color: theme.colorScheme.primary,
                  ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVariantPill({
    required MapEntry<String, String?> variant,
    required int index,
    required ThemeData theme,
  }) {
    final variantKey = 'var_$index';
    final isPlaying = _playingAccent == variantKey;

    return Tooltip(
      message: '多音字读音 ${variant.key}',
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () {
            if (variant.value != null) {
              _play(variantKey, customSoundKey: variant.value);
            } else {
              _play(variantKey);
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.volume_up_outlined,
                  size: 14,
                  color: isPlaying ? theme.colorScheme.primary : theme.hintColor,
                ),
                const SizedBox(width: 4),
                Text(
                  variant.key,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                    fontFamily: 'Gentium Plus DC',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
