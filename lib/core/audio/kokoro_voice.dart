import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'kokoro_engine.dart';
import 'kokoro_model_store.dart';
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

  KokoroEngine? _engine;
  Future<KokoroEngine?>? _loading;

  /// Whether the model is installed and loaded.
  Future<bool> isReady() async => await _load() != null;

  /// What the UI says about this engine, or null when the model is missing.
  Future<String?> label() async {
    final engine = await _load();
    if (engine == null) return null;
    final files = await _find();
    return 'Kokoro（${files?.folder ?? kokoroModelFolder}）'
        '· ${engine.sampleRate} Hz · 后台推理';
  }

  /// The sentence as audio, or null when the model is missing or failed.
  Future<PcmClip?> synthesize(
    String text, {
    required String accent,
    required double rate,
  }) async {
    final engine = await _load();
    if (engine == null || text.trim().isEmpty) return null;
    return engine.synthesize(text, rate.clamp(0.25, 3.0));
  }

  void dispose() {
    _engine?.dispose();
    _engine = null;
    _loading = null;
  }

  /// The engine, started on first use. A failed start is not cached: a model
  /// installed while the app runs is picked up on the next try.
  Future<KokoroEngine?> _load() {
    final existing = _engine;
    if (existing != null) return Future.value(existing);
    return _loading ??= _start();
  }

  Future<KokoroEngine?> _start() async {
    final files = await _find();
    if (files == null) {
      _loading = null;
      return null;
    }
    final engine = KokoroEngine(files, config: kokoroConfigFor(files));
    final error = await engine.start();
    if (error != null) {
      debugPrint('Kokoro could not start: $error');
      engine.dispose();
      _loading = null;
      return null;
    }
    _engine = engine;
    return engine;
  }

}

/// The Kokoro config for [files].
///
/// `lang: 'en'` is required by the model in use (the v1.x multi-lingual bundle),
/// and it is what the bundle's README tells you to pass — without a language or a
/// lexicon it refuses to load outright.
///
/// It was *not* harmless on the older English-only v0.19 model: there the same
/// flag switched to a front end that read "four" with an open /a/ — "fa", with
/// "for" nearly as wide (first formant 989 Hz against 565 Hz; the /ɔː/ reference,
/// "caught", sits at 544 Hz). That model is gone; this one has a single English
/// front end, and the same measurement on it is 625 Hz for "four" and 546 Hz for
/// "for".
///
/// Everything else stays at the SDK default, and `test/kokoro_config_test.dart`
/// fails if any of it is overridden.
sherpa.OfflineTtsKokoroModelConfig kokoroConfigFor(KokoroModelFiles files) =>
    sherpa.OfflineTtsKokoroModelConfig(
      model: files.model,
      voices: files.voices,
      tokens: files.tokens,
      dataDir: files.dataDir,
      lang: 'en',
    );
