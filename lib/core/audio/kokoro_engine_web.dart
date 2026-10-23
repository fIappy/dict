import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'kokoro_model.dart';
import 'pcm_audio.dart';

/// Runs Kokoro on the calling thread (the browser has no isolates).
class KokoroEngine {
  KokoroEngine(this.files, {required this.config, this.sampleRate = 24000});

  final KokoroModelFiles files;
  final sherpa.OfflineTtsKokoroModelConfig config;
  final int sampleRate;

  sherpa.OfflineTts? _tts;

  Future<String?> start() async {
    await sherpa.initBindingsAsync();
    return _load();
  }

  String? _load() {
    try {
      _tts = sherpa.OfflineTts(
        sherpa.OfflineTtsConfig(
          model: sherpa.OfflineTtsModelConfig(kokoro: config, numThreads: 1, debug: false),
          maxNumSenetences: 1,
        ),
      );
      return null;
    } catch (e) {
      return '$e';
    }
  }

  Future<PcmClip?> synthesize(String text, double speed) async {
    final tts = _tts;
    if (tts == null) return null;
    final audio = tts.generateWithConfig(
      text: text,
      config: sherpa.OfflineTtsGenerationConfig(speed: speed),
    );
    if (audio.samples.isEmpty) return null;
    return fromFloat32(audio.samples.toList(), audio.sampleRate);
  }

  void dispose() {
    _tts?.free();
    _tts = null;
  }
}
