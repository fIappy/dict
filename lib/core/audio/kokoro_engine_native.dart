import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'kokoro_model.dart';
import 'pcm_audio.dart';
import 'sherpa_runtime.dart';

/// Runs Kokoro in a worker isolate, so the UI thread never waits for ONNX.
///
/// Synthesis takes roughly half a second per sentence. Doing it on the UI
/// isolate made the whole window stutter for that long on every line — the
/// complaint that "clicking anything while it reads is slow". The worker is
/// started once, keeps the model loaded, and answers one request at a time;
/// requests queue behind each other, which is also what makes prefetching work.
class KokoroEngine {
  KokoroEngine(this.files, {required this.config, this.sampleRate = 24000});

  final KokoroModelFiles files;
  final sherpa.OfflineTtsKokoroModelConfig config;
  final int sampleRate;

  Isolate? _isolate;
  SendPort? _requests;
  ReceivePort? _replies;
  Future<String?>? _starting;
  String? _startError;
  int _nextId = 0;
  Completer<SendPort?>? _readyPort;
  final Map<int, Completer<Uint8List?>> _pending = {};

  /// Loads the model in the worker. Answers an error string, or null on success.
  Future<String?> start() {
    if (_requests != null) return Future<String?>.value(null);
    return _starting ??= _start().then((err) {
      if (err != null) {
        _starting = null;
      }
      return err;
    });
  }

  Future<String?> _start() async {
    final ready = Completer<SendPort?>();
    _readyPort = ready;
    _replies = ReceivePort()..listen(_onMessage);
    try {
      _isolate = await Isolate.spawn<List<Object?>>(
        _kokoroMain,
        <Object?>[_replies!.sendPort, files.model, files.voices, files.tokens, files.dataDir],
        onError: _replies!.sendPort,
        onExit: _replies!.sendPort,
      );
      // The worker reports back with its own request port, or with an error.
      final port = await ready.future.timeout(const Duration(seconds: 60));
      _requests = port;
      if (port == null) {
        _cleanupFailedStart();
        return _startError ?? 'model load failed';
      }
      return null;
    } catch (e) {
      _startError = '$e';
      _cleanupFailedStart();
      return _startError;
    }
  }

  void _cleanupFailedStart() {
    _replies?.close();
    _replies = null;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _readyPort = null;
  }

  void _onMessage(dynamic message) {
    if (message is SendPort) {
      final pending = _readyPort;
      _readyPort = null;
      if (pending != null && !pending.isCompleted) pending.complete(message);
      return;
    }
    if (message == null) {
      // Worker exited (`onExit` sends null): unblock start and any waiting synthesis.
      _startError ??= 'Kokoro worker exited unexpectedly';
      final pendingStart = _readyPort;
      _readyPort = null;
      if (pendingStart != null && !pendingStart.isCompleted) {
        pendingStart.complete(null);
      }
      _requests = null;
      for (final completer in _pending.values) {
        if (!completer.isCompleted) completer.complete(null);
      }
      _pending.clear();
      return;
    }
    if (message is List && message.length == 2) {
      // The isolate's onError channel: [error, stack], or explicit load error.
      _startError = '${message.first}';
      debugPrint('Kokoro worker error: $_startError');
      final pending = _readyPort;
      _readyPort = null;
      if (pending != null && !pending.isCompleted) pending.complete(null);
      return;
    }
    if (message is List && message.length == 3) {
      final id = message[0] as int;
      final raw = message[1];
      final Uint8List? bytes = switch (raw) {
        TransferableTypedData t => t.materialize().asUint8List(),
        Uint8List b => b,
        _ => null,
      };
      final error = message[2] as String?;
      if (error != null) debugPrint('Kokoro worker: $error');
      _pending.remove(id)?.complete(bytes);
    }
  }


  Future<PcmClip?> synthesize(String text, double speed) async {
    final requests = _requests;
    if (requests == null) return null;
    final id = _nextId++;
    final completer = Completer<Uint8List?>();
    _pending[id] = completer;
    requests.send(<Object?>[id, text, speed]);
    final bytes = await completer.future;
    if (bytes == null || bytes.isEmpty) return null;
    return decodeWavWithBytes(bytes);
  }

  void dispose() {
    for (final pending in _pending.values) {
      if (!pending.isCompleted) pending.complete(null);
    }
    _pending.clear();
    final requests = _requests;
    _requests = null;
    final isolate = _isolate;
    _isolate = null;
    _replies?.close();
    _replies = null;
    _readyPort = null;
    _starting = null;
    if (requests != null) {
      // Ask the worker to free its C++ OfflineTts handle before exiting.
      requests.send(null);
    } else {
      isolate?.kill(priority: Isolate.immediate);
    }
  }
}

/// The worker: loads the model once, then turns text into WAV bytes.
void _kokoroMain(List<Object?> args) {
  final replies = args[0] as SendPort;
  final files = KokoroModelFiles(
    model: args[1] as String,
    voices: args[2] as String,
    tokens: args[3] as String,
    dataDir: args[4] as String,
    folder: '',
  );
  _tts = _load(files);
  if (_tts == null) {
    replies.send(<Object?>['Kokoro model could not be loaded in the worker', null]);
    return;
  }
  final requests = ReceivePort();
  replies.send(requests.sendPort);
  requests.listen((message) {
    if (message == null) {
      _tts?.free();
      _tts = null;
      requests.close();
      return;
    }
    final list = message as List<Object?>;
    final id = list[0] as int;
    final text = list[1] as String;
    final speed = list[2] as double;
    try {
      final bytes = _speak(files, text, speed);
      replies.send(<Object?>[
        id,
        bytes == null ? null : TransferableTypedData.fromList([bytes]),
        null,
      ]);
    } catch (e) {
      replies.send(<Object?>[id, null, '$e']);
    }
  });
}

sherpa.OfflineTts? _tts;

Uint8List? _speak(KokoroModelFiles files, String text, double speed) {
  final tts = _tts ??= _load(files);
  if (tts == null) return null;
  final audio = tts.generateWithConfig(
    text: text,
    config: sherpa.OfflineTtsGenerationConfig(speed: speed),
  );
  if (audio.samples.isEmpty) return null;
  return encodeFloat32Wav(audio.samples, sampleRate: audio.sampleRate);
}

sherpa.OfflineTts? _load(KokoroModelFiles files) {
  try {
    preloadOnnxRuntime();
    sherpa.initBindings();
    return sherpa.OfflineTts(
      sherpa.OfflineTtsConfig(
        model: sherpa.OfflineTtsModelConfig(
          kokoro: kokoroConfigForFiles(files),
          // ONNX is the slow part and it is embarrassingly parallel; the SDK's
          // default of one thread leaves most of the machine idle while the
          // reader waits. Four is where the gain flattens out.
          numThreads: Platform.numberOfProcessors.clamp(1, 4),
          debug: false,
        ),
        maxNumSenetences: 1,
      ),
    );
  } catch (e) {
    debugPrint('Kokoro model could not be loaded in the worker: $e');
    return null;
  }
}

/// The model's documented defaults, built from [files] alone — see
/// `kokoroConfigFor` in `kokoro_voice.dart` for why nothing is overridden.
sherpa.OfflineTtsKokoroModelConfig kokoroConfigForFiles(KokoroModelFiles files) =>
    sherpa.OfflineTtsKokoroModelConfig(
      model: files.model,
      voices: files.voices,
      tokens: files.tokens,
      dataDir: files.dataDir,
      lang: 'en',
    );
