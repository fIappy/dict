// Engine: Dart (pure) | Target: lib/core/audio
//
// Waits for one playback to finish, given the player's event streams.
//
// Two traps live here, and both end a clip a few milliseconds after it starts —
// heard as the opening of an utterance being clipped:
//
// 1. `stream.first` looks like the obvious tool and **cannot be cancelled**. When
//    the future it returns loses the race against the stall guard, its
//    subscription stays alive, so the *next* playback's completion also resolves
//    the abandoned future — and an orphan that fires early is indistinguishable
//    from the real thing at the call site.
//
// 2. The player also emits a completion for a source it is **tearing down**.
//    Replacing a still-sounding source produces exactly such an event a few
//    milliseconds later, and a fresh playback cannot tell it apart from its own
//    completion. That replacement happens whenever the stall guard fired and the
//    next clip started while the old one was still sounding, which is why this
//    shows up as "sometimes" and at group boundaries.
//
// So the wait subscribes explicitly and cancels in `finally`, and refuses a
// completion that arrives before the playback could plausibly have played.
// Everything here is plain Dart over two streams, so the behaviour is covered by
// unit tests instead of by listening to a speaker.

import 'dart:async';

/// Runs [start] (which begins exactly one playback) and completes when that
/// playback finishes.
///
/// Returns true when the player reported completion, false when the stall guard
/// ran out first — the caller can log that, and either way the next clip may
/// start: the guard is sized so it can never cut a clip short.
///
/// * [completions] fires once per finished playback.
/// * [durations] reports the duration of whichever playback is loaded, used to
///   size the stall guard.
/// * [minPlausible] is how soon after starting a completion stops being
///   believable as *this* playback's own (it is the previous source being torn
///   down). Must be shorter than the shortest clip the caller plays.
/// * [durationWait] bounds how long to wait for [durations] before giving up.
/// * [stallGuard] turns the reported duration (null when none arrived) into the
///   longest this playback may take.
Future<bool> awaitPlayback({
  required Stream<void> completions,
  required Stream<Duration> durations,
  required Future<void> Function() start,
  required Duration minPlausible,
  required Duration durationWait,
  required Duration Function(Duration? reported) stallGuard,
}) async {
  final finished = Completer<void>();
  final reported = Completer<Duration?>();
  final started = Stopwatch()..start();

  final completeSub = completions.listen((_) {
    if (started.elapsed >= minPlausible && !finished.isCompleted) {
      finished.complete();
    }
  });
  final durationSub = durations.listen((value) {
    if (!reported.isCompleted) reported.complete(value);
  });

  try {
    await start();
    final duration = await Future.any<Duration?>([
      reported.future,
      Future<Duration?>.delayed(durationWait),
    ]);
    if (finished.isCompleted) return true;
    await Future.any<void>([
      finished.future,
      Future<void>.delayed(stallGuard(duration)),
    ]);
    return finished.isCompleted;
  } finally {
    await completeSub.cancel();
    await durationSub.cancel();
  }
}
