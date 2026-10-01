import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../services/dictionary_service.dart';

class AudioManager {
  static final AudioManager _instance = AudioManager._();
  factory AudioManager() => _instance;
  AudioManager._();

  final AudioPlayer _player = AudioPlayer();
  final DictionaryService _dictService = DictionaryService();

  bool _isPlaying = false;
  String? _currentlyPlayingTag;

  bool get isPlaying => _isPlaying;
  String? get currentlyPlayingTag => _currentlyPlayingTag;

  /// Plays a pronunciation for [word].
  ///
  /// Resolution order:
  /// * **American** — the archive's own `.mdd` recording first (offline, exact),
  ///   then an online dictionary voice, then OS text-to-speech.
  /// * **British** — the bundled `.mdd` holds *American* recordings, so it is
  ///   never used here; British playback goes online, then OS text-to-speech.
  ///
  /// The online step is what keeps a dictionary imported **without** its `.mdd`
  /// audible: previously "美音" was a silent no-op on anything but Windows.
  Future<void> playWord({
    required String word,
    String? soundKey,
    String accent = 'us', // 'us' (美音) or 'uk' (英音)
    void Function(bool isPlaying)? onStateChanged,
  }) async {
    final playTag = '${word}_$accent';
    _currentlyPlayingTag = playTag;
    _isPlaying = true;
    onStateChanged?.call(true);

    try {
      if (accent == 'uk') {
        final ukClip = await _cachedOnlineClip(word, 'uk');
        if (ukClip != null) {
          await _player.stop();
          await _player.play(DeviceFileSource(ukClip));
          return;
        }
        await _speakWithOs(word);
        return;
      }

      // 1. The archive's own recording, available when the dictionary ships an .mdd.
      Uint8List? audioBytes;
      if (soundKey != null && soundKey.isNotEmpty) {
        audioBytes = await _dictService.getAudioBytes(soundKey);
      }
      audioBytes ??= await _dictService.getAudioBytes('$word.mp3');

      if (audioBytes != null && audioBytes.isNotEmpty) {
        try {
          if (Platform.isWindows) {
            final tempDir = await getTemporaryDirectory();
            final tempFile = File(p.join(tempDir.path, 'temp_audio_us.mp3'));
            await tempFile.writeAsBytes(audioBytes, flush: true);
            await _player.stop();
            await _player.play(DeviceFileSource(tempFile.path));
          } else {
            await _player.stop();
            await _player.play(BytesSource(audioBytes));
          }
          return;
        } catch (e) {
          debugPrint('AudioPlayer error: $e');
        }
      }

      // 2. No .mdd in this archive (e.g. an .mdx imported on its own): use the
      //    online voice instead of staying silent.
      final usClip = await _cachedOnlineClip(word, 'us');
      if (usClip != null) {
        await _player.stop();
        await _player.play(DeviceFileSource(usClip));
        return;
      }

      // 3. Offline and no archive audio: fall back to OS text-to-speech.
      await _speakWithOs(word);
    } catch (e) {
      debugPrint('Error playing pronunciation for $word: $e');
    } finally {
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (_currentlyPlayingTag == playTag) {
          _isPlaying = false;
          _currentlyPlayingTag = null;
          onStateChanged?.call(false);
        }
      });
    }
  }

  /// Downloads one dictionary-voice clip and caches it on disk.
  ///
  /// Returns the cached file path, or null when the network is unavailable.
  Future<String?> _cachedOnlineClip(String word, String accent) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final safe = word.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
      final file = File(p.join(tempDir.path, 'tts_${accent}_$safe.mp3'));
      if (file.existsSync() && file.lengthSync() > 500) return file.path;

      // type=1 -> British voice, type=2 -> American voice.
      final type = accent == 'uk' ? 1 : 2;
      final url = Uri.parse(
        'https://dict.youdao.com/dictvoice?audio=${Uri.encodeComponent(word)}&type=$type',
      );
      final res = await http.get(url).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200 && res.bodyBytes.length > 500) {
        await file.writeAsBytes(res.bodyBytes, flush: true);
        return file.path;
      }
    } catch (e) {
      debugPrint('Failed to download $accent audio for $word: $e');
    }
    return null;
  }

  /// Last-resort speech synthesis; only Windows exposes a usable CLI.
  Future<void> _speakWithOs(String word) async {
    if (!Platform.isWindows) return;
    final clean = word.replaceAll("'", '').replaceAll('"', '');
    try {
      await Process.run('powershell', [
        '-Command',
        "(New-Object -ComObject SAPI.SpVoice).Speak('$clean')",
      ]);
    } catch (e) {
      debugPrint('OS speech failed for $word: $e');
    }
  }

  Future<void> playIpaPhoneme(
    String audioAssetKey, {
    void Function(bool isPlaying)? onStateChanged,
  }) async {
    final playTag = 'ipa_$audioAssetKey';
    _currentlyPlayingTag = playTag;
    _isPlaying = true;
    onStateChanged?.call(true);

    try {
      await _player.stop();
      await _player.play(AssetSource('audio/ipa/$audioAssetKey.mp3'));
    } catch (e) {
      debugPrint('Error playing IPA phoneme audio $audioAssetKey: $e');
    } finally {
      Future.delayed(const Duration(milliseconds: 1000), () {
        if (_currentlyPlayingTag == playTag) {
          _isPlaying = false;
          _currentlyPlayingTag = null;
          onStateChanged?.call(false);
        }
      });
    }
  }

  Future<void> playLetter(
    String letterKey, {
    String accent = 'us',
    void Function(bool isPlaying)? onStateChanged,
  }) async {
    final playTag = 'letter_${letterKey}_$accent';
    _currentlyPlayingTag = playTag;
    _isPlaying = true;
    onStateChanged?.call(true);

    try {
      final assetPath = 'audio/letters/${letterKey.toLowerCase()}_$accent.mp3';
      await _player.stop();
      await _player.play(AssetSource(assetPath));
    } catch (e) {
      debugPrint('Error playing letter audio $letterKey ($accent): $e');
    } finally {
      Future.delayed(const Duration(milliseconds: 800), () {
        if (_currentlyPlayingTag == playTag) {
          _isPlaying = false;
          _currentlyPlayingTag = null;
          onStateChanged?.call(false);
        }
      });
    }
  }

  Future<void> stop() async {
    try {
      await _player.stop();
      _isPlaying = false;
      _currentlyPlayingTag = null;
    } catch (_) {}
  }

  void dispose() {
    _player.dispose();
  }
}
