import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'kokoro_model_store.dart';
import 'sherpa_runtime.dart';
import 'pcm_audio.dart';

/// Speaks with Kokoro: an 82M-parameter model run locally by sherpa-onnx.
///
/// This replaced the Piper voice *and* every platform voice: one model, one
/// timbre, on Windows, Android and in the browser (WebAssembly). Without the
/// model on disk the engine answers null and the UI says the model is missing —
/// there is no second engine to fall back to by design.
class KokoroVoice {
  KokoroVoice({Future<KokoroModelFiles?> Function()? finder})
      : _find = finder ?? findKokoroModel;

  final Future<KokoroModelFiles?> Function() _find;

  sherpa.OfflineTts? _engine;
  bool _bindingsReady = false;

  /// Whether the model is installed and loaded.
  Future<bool> isReady() async => await _load() != null;

  /// What the UI says about this engine, or null when the model is missing.
  Future<String?> label() async {
    final engine = await _load();
    if (engine == null) return null;
    final files = await _find();
    return 'Kokoro（${files?.folder ?? kokoroModelFolder}）'
        '· ${engine.sampleRate} Hz · 本机推理';
  }

  /// The sentence as audio, or null when the model is missing or failed.
  Future<PcmClip?> synthesize(
    String text, {
    required String accent,
    required double rate,
  }) async {
    final engine = await _load();
    if (engine == null || text.trim().isEmpty) return null;
    try {
      final audio = engine.generateWithConfig(
        text: text,
        config: sherpa.OfflineTtsGenerationConfig(
          speed: rate.clamp(0.25, 3.0),
          sid: kokoroSpeakerId,
        ),
      );
      if (audio.samples.isEmpty) return null;
      return fromFloat32(audio.samples.toList(), audio.sampleRate);
    } catch (e) {
      debugPrint('Kokoro synthesis failed: $e');
      return null;
    }
  }

  void dispose() {
    _engine?.free();
    _engine = null;
  }

  /// The loaded model, loading it on first use. A failed load is not cached, so
  /// a model installed while the app runs is picked up on the next try.
  Future<sherpa.OfflineTts?> _load() async {
    final existing = _engine;
    if (existing != null) return existing;

    final files = await _find();
    if (files == null) return null;

    try {
      if (!_bindingsReady) {
        preloadOnnxRuntime();
        await sherpa.initBindingsAsync();
        _bindingsReady = true;
      }
      // Native: the files are already on disk. Web: they are fetched into the
      // wasm's file system, because the library inside cannot read HTTP paths.
      await prepareKokoroModel(files);
      final engine = sherpa.OfflineTts(
        sherpa.OfflineTtsConfig(
          model: sherpa.OfflineTtsModelConfig(
            kokoro: sherpa.OfflineTtsKokoroModelConfig(
              model: files.model,
              voices: files.voices,
              tokens: files.tokens,
              dataDir: files.dataDir,
              lang: 'en',
            ),
            numThreads: 1,
            debug: false,
          ),
          maxNumSenetences: 1,
        ),
      );
      _engine = engine;
      return engine;
    } catch (e) {
      debugPrint('Kokoro model at ${files.model} could not be loaded: $e');
      return null;
    }
  }

}
