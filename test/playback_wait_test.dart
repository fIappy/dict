import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_dict/core/audio/playback_wait.dart';

void main() {
  test('a cancel ends the wait before the clip does', () async {
    final completions = StreamController<void>.broadcast();
    final durations = StreamController<Duration>.broadcast();
    addTearDown(completions.close);
    addTearDown(durations.close);
    final cancel = Completer<void>();

    final wait = awaitPlayback(
      completions: completions.stream,
      durations: durations.stream,
      start: () async {
        durations.add(const Duration(seconds: 20));
      },
      minPlausible: const Duration(milliseconds: 5),
      durationWait: const Duration(milliseconds: 20),
      stallGuard: (_) => const Duration(seconds: 30),
      cancel: cancel.future,
    );

    await Future<void>.delayed(const Duration(milliseconds: 30));
    cancel.complete();
    expect(await wait, isFalse, reason: 'stopped is not "played to the end"');
  });

  test('a completion before the plausibility window is ignored', () async {
    final completions = StreamController<void>.broadcast();
    final durations = StreamController<Duration>.broadcast();
    addTearDown(completions.close);
    addTearDown(durations.close);

    final wait = awaitPlayback(
      completions: completions.stream,
      durations: durations.stream,
      start: () async {
        // The previous source being torn down reports a completion right away.
        completions.add(null);
        durations.add(const Duration(milliseconds: 100));
      },
      minPlausible: const Duration(milliseconds: 50),
      durationWait: const Duration(milliseconds: 10),
      stallGuard: (_) => const Duration(milliseconds: 120),
    );

    // The early event must not count; the stall guard ends the wait instead.
    expect(await wait, isFalse);
  });

  test('the clip finishing normally reports true', () async {
    final completions = StreamController<void>.broadcast();
    final durations = StreamController<Duration>.broadcast();
    addTearDown(completions.close);
    addTearDown(durations.close);

    final wait = awaitPlayback(
      completions: completions.stream,
      durations: durations.stream,
      start: () async {
        durations.add(const Duration(milliseconds: 200));
        Timer(const Duration(milliseconds: 15), () => completions.add(null));
      },
      minPlausible: const Duration(milliseconds: 5),
      durationWait: const Duration(milliseconds: 50),
      stallGuard: (_) => const Duration(seconds: 2),
    );

    expect(await wait, isTrue);
  });
}
