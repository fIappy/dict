import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Keeps the app running while sound is playing.
///
/// On Android a backgrounded app is frozen and its process becomes a kill
/// candidate, so a word being read out stops the moment the launcher opens or
/// the screen goes off. The platform side runs a media-playback foreground
/// service (plus a wake lock) for exactly as long as this class says sound is
/// on. Everywhere else this is a no-op.
class AudioBackground {
  AudioBackground._();

  static const MethodChannel _channel =
      MethodChannel('local_dict/audio_background');

  /// How long the service lingers after the last clip. A word list plays clip
  /// after clip; tearing the service down between two words would drop the
  /// notification and re-acquire the wake lock for nothing.
  static Duration _linger = const Duration(seconds: 8);

  static int _active = 0;
  static Timer? _lingerTimer;
  static bool _running = false;

  /// Tests run on the host, where [Platform.isAndroid] is false; these two
  /// hooks let them drive the countdown without a phone.
  @visibleForTesting
  static bool? debugForceSupported;

  @visibleForTesting
  static MethodChannel get debugChannel => _channel;

  @visibleForTesting
  static set debugLinger(Duration value) => _linger = value;

  /// Clears the counters between tests, in the state a fresh launch would have.
  @visibleForTesting
  static void debugReset() {
    _active = 0;
    _lingerTimer?.cancel();
    _lingerTimer = null;
    _running = false;
  }

  static bool get _supported => debugForceSupported ?? (!kIsWeb && Platform.isAndroid);

  /// One clip started. Every call must be paired with [end].
  static void begin() {
    if (!_supported) return;
    _lingerTimer?.cancel();
    _lingerTimer = null;
    _active++;
    if (_running) return;
    _running = true;
    _invoke('start');
  }

  /// A clip finished (or failed). The service stops once nothing is playing.
  static void end() {
    if (!_supported) return;
    if (_active > 0) _active--;
    if (_active > 0 || !_running) return;
    _lingerTimer?.cancel();
    _lingerTimer = Timer(_linger, () {
      _lingerTimer = null;
      if (_active > 0 || !_running) return;
      _running = false;
      _invoke('stop');
    });
  }

  /// The reader asked for silence: stop now instead of waiting out the linger.
  static void stopNow() {
    if (!_supported) return;
    _active = 0;
    _lingerTimer?.cancel();
    _lingerTimer = null;
    if (!_running) return;
    _running = false;
    _invoke('stop');
  }

  static void _invoke(String method) {
    _channel.invokeMethod<void>(method).catchError((Object error) {
      // The platform side is missing (an old build, a desktop run): silence is
      // still correct, so never let this break playback.
      debugPrint('Audio background $method failed: $error');
      if (method == 'start') _running = false;
    });
  }
}
