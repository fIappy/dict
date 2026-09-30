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
      final tempDir = await getTemporaryDirectory();

      if (accent == 'uk') {
        // 1. British English (UK) Audio
        final ukFile = File(p.join(tempDir.path, 'uk_${word.toLowerCase()}.mp3'));
        if (!ukFile.existsSync()) {
          try {
            final url = Uri.parse('https://dict.youdao.com/dictvoice?audio=${Uri.encodeComponent(word)}&type=1');
            final res = await http.get(url).timeout(const Duration(seconds: 4));
            if (res.statusCode == 200 && res.bodyBytes.length > 500) {
              await ukFile.writeAsBytes(res.bodyBytes, flush: true);
            }
          } catch (e) {
            debugPrint('Failed to download UK audio for $word: $e');
          }
        }

        if (ukFile.existsSync()) {
          await _player.stop();
          await _player.play(DeviceFileSource(ukFile.path));
          return;
        }

        // Offline fallback for UK
        if (Platform.isWindows) {
          final clean = word.replaceAll("'", "").replaceAll('"', '');
          await Process.run('powershell', [
            '-Command',
            "(New-Object -ComObject SAPI.SpVoice).Speak('$clean')",
          ]);
          return;
        }
      }

      // 2. American English (US) Audio - Native MDD file
      Uint8List? audioBytes;
      if (soundKey != null && soundKey.isNotEmpty) {
        audioBytes = await _dictService.getAudioBytes(soundKey);
      }
      audioBytes ??= await _dictService.getAudioBytes('$word.mp3');

      if (audioBytes != null && audioBytes.isNotEmpty) {
        try {
          if (Platform.isWindows) {
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

      // 3. Fallback to Windows SAPI TTS if on Windows
      if (Platform.isWindows) {
        final cleanWord = word.replaceAll("'", "").replaceAll('"', '');
        await Process.run('powershell', [
          '-Command',
          "(New-Object -ComObject SAPI.SpVoice).Speak('$cleanWord')",
        ]);
      }
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
