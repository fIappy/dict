import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_dict/core/audio/online_tts.dart';
import 'package:local_dict/core/audio/speech_engine.dart';

void main() {
  test('the free voices are the online ones, and they need no key', () {
    final online = SpeechEngine.values.where((e) => e.isOnline).toList();
    expect(online, containsAll([SpeechEngine.edge, SpeechEngine.google,
        SpeechEngine.baidu]));
    expect(SpeechEngine.kokoro.isOnline, isFalse);
    expect(SpeechEngine.system.isOnline, isFalse);
    for (final engine in online) {
      expect(engine.hint, contains('免费'));
    }
  });

  test('each online voice has its own endpoint', () {
    final us = {
      for (final engine in [SpeechEngine.google, SpeechEngine.baidu])
        engine: OnlineTts.urlFor(engine, text: 'A sentence.', accent: 'us')!,
    };
    expect(us[SpeechEngine.google]!.host, 'translate.google.com');
    expect(us[SpeechEngine.google]!.queryParameters['tl'], 'en');
    expect(us[SpeechEngine.baidu]!.host, 'fanyi.baidu.com');

    final uk = OnlineTts.urlFor(SpeechEngine.google,
        text: 'A sentence.', accent: 'uk')!;
    expect(uk.queryParameters['tl'], 'en-GB',
        reason: 'the accent picks the voice, not just the wording');

    // Edge speaks over a socket, not a GET.
    expect(
      OnlineTts.urlFor(SpeechEngine.edge, text: 'A sentence.', accent: 'us'),
      isNull,
    );
  });

  test('百度的 spd carries the speed, and stays inside the service range', () {
    expect(OnlineTts.baiduSpeed(0.5), 1);
    expect(OnlineTts.baiduSpeed(1.0), 3, reason: 'the service normal pace');
    expect(OnlineTts.baiduSpeed(1.5), 5);
    expect(OnlineTts.baiduSpeed(2.0), 7, reason: '8 answers an empty body');
    expect(OnlineTts.baiduSpeed(3.0), 7, reason: 'clamped, not rejected');

    final slow = OnlineTts.urlFor(SpeechEngine.baidu,
        text: 'Hello.', accent: 'us', rate: 0.5)!;
    final normal = OnlineTts.urlFor(SpeechEngine.baidu,
        text: 'Hello.', accent: 'us', rate: 1.0)!;
    expect(slow.queryParameters['spd'], '1');
    expect(normal.queryParameters['spd'], '3');
  });

  test('only the services that bake speed are marked as such', () {
    expect(SpeechEngine.edge.bakesRate, isTrue);
    expect(SpeechEngine.baidu.bakesRate, isTrue);
    expect(SpeechEngine.google.bakesRate, isFalse,
        reason: 'its endpoint ignores the speed, so the player does it');
    expect(SpeechEngine.kokoro.bakesRate, isFalse);
  });

  test('the local engines never touch the network', () async {
    for (final engine in [SpeechEngine.kokoro, SpeechEngine.system]) {
      expect(
        await OnlineTts.synthesize(engine, text: 'Hello.', accent: 'us'),
        isNull,
        reason: '${engine.name} must not fetch anything',
      );
    }
  });

  test('an empty line is not sent anywhere', () async {
    expect(
      await OnlineTts.synthesize(SpeechEngine.edge,
          text: '   ', accent: 'us'),
      isNull,
    );
  });

  test('audio is recognised by its leading bytes', () {
    // The check the fetcher applies before it trusts a response.
    expect(OnlineTts.looksLikeAudio(Uint8List.fromList([0x49, 0x44, 0x33, 0, 0])),
        isFalse,
        reason: 'an ID3 tag alone is shorter than the minimum clip');
    expect(
      OnlineTts.looksLikeAudio(
          Uint8List.fromList([0xFF, 0xF3, 0x64, ...List<int>.filled(600, 0)])),
      isTrue,
    );
    expect(
      OnlineTts.looksLikeAudio(Uint8List.fromList(
          [0x3C, 0x21, 0x44, ...List<int>.filled(600, 0)])),
      isFalse,
      reason: 'an HTML error page is not audio',
    );
  });
}
