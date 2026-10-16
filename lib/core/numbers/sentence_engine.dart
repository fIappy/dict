import 'dart:typed_data';

import '../audio/asset_bytes.dart';
import '../audio/pcm_audio.dart';
import '../audio/speech_clip_player.dart';
import 'number_audio.dart';

/// Resolves the clip that exists for one word in one accent.
///
/// Defaults to the bundled asset manifest; injectable so the sequencing logic
/// can be tested without the asset bundle.
typedef ClipResolver = Future<String?> Function(String word, String accent);

/// Reads the bytes of an `assets/`-relative file, or null when it is missing.
typedef AssetBytesLoader = Future<Uint8List?> Function(String assetPath);

/// Which engine reads a whole number sentence.
///
/// The module never *depends* on one: whatever is selected, a sentence the engine
/// cannot say falls back to the recorded words, so a machine without that engine
/// still speaks every number.
enum SentenceEngine {
  system(
    '系统语音',
    '交给宿主的语音合成：Windows OneCore/SAPI、Android TextToSpeech、浏览器 speechSynthesis（音色随机器而异）',
  ),
  spliced(
    '录音拼接',
    '把自带的单词录音在内存里拼成一句再播放：无接缝、完全离线、三端逐字节相同（仍是逐词读音）',
  ),
  piper(
    'Piper 神经语音',
    '随应用分发的 Piper 模型在本机推理：三端同一音色、连读自然，完全离线（需先放好模型）',
  );

  final String labelZh;
  final String hint;

  const SentenceEngine(this.labelZh, this.hint);

  /// Whether the user can pick this engine.
  ///
  /// 录音拼接 is not offered: its voice is the same dictionary recording the
  /// word-by-word mode uses, so it is not a voice anyone would choose — but it is
  /// kept as the last resort of [NumberSpeaker.sentenceFallback], where "the
  /// device has no voice and no model" must still produce one continuous number
  /// instead of two separate words.
  bool get selectable => this != SentenceEngine.spliced;
}

/// Speaks one sentence out of the module's recorded words.
///
/// This is the engine that behaves identically everywhere: the same WAV bytes are
/// decoded, spliced and played on Windows, Android and the browser, and the work
/// is pure Dart, so the part that used to differ between platforms — where the
/// words are, where the pauses go — is covered by a unit test instead of by three
/// manual checks.
///
/// It cannot make the words sound connected: each clip keeps its citation form.
/// That is what the [SentenceEngine.system] and Piper engines are for.
class SplicedSentence {
  SplicedSentence({
    required SpeechClipPlayer player,
    ClipResolver? resolver,
    AssetBytesLoader? loader,
  })  : _player = player,
        _resolve = resolver ?? NumberAudio.resolve,
        _load = loader ?? loadAssetBytes;

  final SpeechClipPlayer _player;
  final ClipResolver _resolve;
  final AssetBytesLoader _load;

  /// Silence between the groups a comma separates (phone numbers), the same
  /// pause the word-by-word playback leaves.
  static const Duration groupPause = Duration(milliseconds: 200);

  /// Splices and plays [sentence] as one clip.
  ///
  /// Returns false when not a single word of it had a recording: the caller then
  /// speaks the number word by word, which is the module's standing fallback.
  Future<bool> speak(
    String sentence, {
    required String accent,
    required double rate,
  }) async {
    final parts = <PcmClip>[];
    final groups = NumberAudio.pauseGroups(sentence);

    for (var group = 0; group < groups.length; group++) {
      final groupClips = <PcmClip>[];
      for (final word in NumberAudio.words(groups[group])) {
        final clip = await _clipFor(word, accent);
        if (clip != null) groupClips.add(clip);
      }
      if (groupClips.isEmpty) continue;
      // The pause belongs *between* groups, so it is only added once something
      // is already queued; the clip's own sample rate carries it.
      if (parts.isNotEmpty) {
        parts.add(PcmClip.silence(groupPause, groupClips.first.sampleRate));
      }
      parts.addAll(groupClips);
    }

    if (parts.isEmpty) return false;

    final joined = joinClips(parts);
    await _player.playAudioBytes(
      encodeWav(joined.samples, sampleRate: joined.sampleRate),
      rate: rate,
    );
    return true;
  }

  /// The clip for [word], or null when the word has no recording (unknown word,
  /// missing asset, or a file this build cannot read).
  Future<PcmClip?> _clipFor(String word, String accent) async {
    final path = await _resolve(word, accent);
    if (path == null) return null;
    final bytes = await _load(path);
    if (bytes == null) return null;
    try {
      return decodeWav(bytes);
    } on FormatException {
      return null;
    }
  }
}
