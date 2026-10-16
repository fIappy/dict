import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'pcm_audio.dart';
import 'piper_model_store.dart';

/// Speaks with the bundled Piper voice: a small VITS model run locally by
/// sherpa-onnx.
///
/// This is the engine that sounds like a person reading the whole number rather
/// than a list of words, and it is the *same* model on Windows, Android and in
/// the browser (WebAssembly) — one voice, offline, on all three.
///
/// Availability is a property of the installation, not of the platform: without a
/// model on disk every call answers null and the caller keeps using another
/// engine. The model is read once per accent and kept; loading it is the slow
/// part (~20 MB from disk, a second or two), synthesis itself is quick.
class PiperVoice {
  PiperVoice({Future<PiperModelFiles?> Function(String accent)? finder})
      : _find = finder ?? findPiperModel;

  final Future<PiperModelFiles?> Function(String accent) _find;

  final Map<String, sherpa.OfflineTts> _engines = {};
  bool _bindingsReady = false;

  /// Whether [accent]'s model is installed and loaded.
  Future<bool> isReady(String accent) async => await _engine(accent) != null;

  /// What the UI says about this engine, or null when the model is missing.
  Future<String?> label(String accent) async {
    final engine = await _engine(accent);
    if (engine == null) return null;
    final files = await _find(accent);
    return '已加载 ${files?.folder ?? piperAccentFolder(accent)}'
        '（${engine.sampleRate} Hz 本机推理，三端同一模型）';
  }

  /// The sentence as audio, or null when this machine cannot speak it (no model,
  /// or the model failed to load) — the caller then falls back.
  Future<PcmClip?> synthesize(
    String text, {
    required String accent,
    required double rate,
  }) async {
    final engine = await _engine(accent);
    if (engine == null || text.trim().isEmpty) return null;
    try {
      final audio = engine.generateWithConfig(
        text: text,
        config: sherpa.OfflineTtsGenerationConfig(
          speed: rate.clamp(0.25, 3.0),
        ),
      );
      if (audio.samples.isEmpty) return null;
      return fromFloat32(audio.samples.toList(), audio.sampleRate);
    } catch (e) {
      debugPrint('Piper synthesis failed: $e');
      return null;
    }
  }

  void dispose() {
    for (final engine in _engines.values) {
      engine.free();
    }
    _engines.clear();
  }

  /// The loaded model for [accent], loading it on first use. Failures are not
  /// cached: a model installed while the app runs is picked up on the next try.
  Future<sherpa.OfflineTts?> _engine(String accent) async {
    final folder = piperAccentFolder(accent);
    final existing = _engines[folder];
    if (existing != null) return existing;

    final files = await _find(accent);
    if (files == null) return null;

    try {
      if (!_bindingsReady) {
        await sherpa.initBindingsAsync();
        _bindingsReady = true;
      }
      // Native: the files are already on disk. Web: they are fetched into the
      // wasm's file system, because the library inside cannot read HTTP paths.
      await preparePiperModel(files);
      final engine = sherpa.OfflineTts(
        sherpa.OfflineTtsConfig(
          model: sherpa.OfflineTtsModelConfig(
            vits: sherpa.OfflineTtsVitsModelConfig(
              model: files.model,
              tokens: files.tokens,
              dataDir: files.dataDir,
            ),
            numThreads: 1,
            debug: false,
          ),
          maxNumSenetences: 1,
        ),
      );
      _engines[folder] = engine;
      return engine;
    } catch (e) {
      debugPrint('Piper model at ${files.model} could not be loaded: $e');
      return null;
    }
  }
}
