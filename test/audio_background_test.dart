import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_dict/core/audio/audio_background.dart';

/// The background service is the difference between "keeps reading a word when
/// the screen goes off" and "goes silent the moment the launcher opens", and the
/// refcount is the part that can silently tear it down mid-clip.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> calls;

  setUp(() {
    calls = <String>[];
    AudioBackground.debugReset();
    AudioBackground.debugForceSupported = true;
    AudioBackground.debugLinger = const Duration(milliseconds: 30);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AudioBackground.debugChannel, (call) async {
      calls.add(call.method);
      return null;
    });
  });

  tearDown(() {
    AudioBackground.debugReset();
    AudioBackground.debugForceSupported = null;
    AudioBackground.debugLinger = const Duration(seconds: 8);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AudioBackground.debugChannel, null);
  });

  test('overlapping clips start the service once', () async {
    AudioBackground.begin();
    AudioBackground.begin();
    await Future<void>.delayed(Duration.zero);
    expect(calls, ['start']);

    // The first clip ending must not tear down the second one.
    AudioBackground.end();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(calls, ['start']);
  });

  test('the service stops once nothing is playing', () async {
    AudioBackground.begin();
    AudioBackground.end();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(calls, ['start', 'stop']);
  });

  test('a new clip cancels the pending stop', () async {
    AudioBackground.begin();
    AudioBackground.end();
    AudioBackground.begin();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(calls, ['start'], reason: 'the stop was still pending');

    AudioBackground.end();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(calls, ['start', 'stop']);
  });

  test('stopNow stops at once and does not stop twice', () async {
    AudioBackground.begin();
    AudioBackground.stopNow();
    await Future<void>.delayed(Duration.zero);
    expect(calls, ['start', 'stop']);

    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(calls, ['start', 'stop'], reason: 'the cancelled linger must not fire');
  });

  test('other platforms never touch the channel', () async {
    AudioBackground.debugForceSupported = null;
    AudioBackground.begin();
    AudioBackground.end();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    if (!Platform.isAndroid) expect(calls, isEmpty);
  });
}
