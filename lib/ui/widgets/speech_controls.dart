import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/entry_speech_provider.dart';
import '../../providers/settings_provider.dart';

/// 播放 / 暂停·继续 / 停止 / 循环, for every player that reads more than one line.
///
/// [onStart] starts the current screen's run; once running, the first button
/// becomes pause/resume. Pausing cuts the sound immediately — a TTS engine has
/// no mid-utterance pause — and resuming says the interrupted line again.
class SpeechControls extends StatelessWidget {
  const SpeechControls({
    super.key,
    required this.onStart,
    this.idleLabel = '播放',
    this.labels = false,
  });

  final VoidCallback onStart;

  /// Text on the idle button when [labels] is true.
  final String idleLabel;

  /// Show a labelled button instead of a bare icon.
  final bool labels;

  @override
  Widget build(BuildContext context) {
    final speech = context.watch<EntrySpeechProvider>();
    final settings = context.watch<SettingsProvider>();
    final playing = speech.isPlaying;
    final paused = speech.isPaused;
    final theme = Theme.of(context);

    final icon = Icon(
      playing
          ? (paused ? Icons.play_arrow_rounded : Icons.pause_rounded)
          : Icons.playlist_play_rounded,
      size: 18,
    );
    final label = playing ? (paused ? '继续' : '暂停') : idleLabel;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (labels)
          FilledButton.tonalIcon(
            icon: icon,
            label: Text(label),
            onPressed: playing ? speech.togglePause : onStart,
          )
        else
          IconButton(
            tooltip: label,
            icon: icon,
            onPressed: playing ? speech.togglePause : onStart,
          ),
        if (playing)
          IconButton(
            tooltip: '停止',
            icon: const Icon(Icons.stop_rounded, size: 18),
            onPressed: speech.stop,
          ),
        IconButton(
          tooltip: settings.speechLoop ? '循环播放：开' : '循环播放：关',
          icon: Icon(
            Icons.repeat_rounded,
            size: 18,
            color: settings.speechLoop ? theme.colorScheme.primary : theme.hintColor,
          ),
          onPressed: () {
            final next = !settings.speechLoop;
            settings.setSpeechLoop(next);
            context.read<EntrySpeechProvider>().setLoop(next);
          },
        ),
      ],
    );
  }
}
