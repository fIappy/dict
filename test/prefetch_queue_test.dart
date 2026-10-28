import 'package:flutter_test/flutter_test.dart';
import 'package:local_dict/core/audio/prefetch_queue.dart';

void main() {
  test('prepares the next items while the current one plays', () async {
    final log = <String>[];
    final queue = PrefetchQueue(window: 3);

    await queue.run(
      6,
      prepare: (index) async {
        log.add('prepare $index');
        await Future<void>.delayed(const Duration(milliseconds: 20));
      },
      play: (index) async {
        log.add('play $index');
        await Future<void>.delayed(const Duration(milliseconds: 30));
        log.add('end $index');
      },
    );

    // Items 1..3 were prepared before the first play finished.
    final firstEnd = log.indexOf('end 0');
    for (final index in [1, 2, 3]) {
      expect(log.indexOf('prepare $index'), lessThan(firstEnd),
          reason: 'item $index should be ready before item 0 ends');
    }
    // Nothing beyond the window is prepared that early.
    expect(log.indexOf('prepare 4'), greaterThan(firstEnd));
  });

  test('the gap between sounds is the gap asked for, not gap + prepare',
      () async {
    final starts = <int>[];
    final watch = Stopwatch()..start();
    final queue = PrefetchQueue(window: 5);

    await queue.run(
      5,
      prepare: (index) async {
        // Slower than the playback: without prefetching this would be heard.
        await Future<void>.delayed(const Duration(milliseconds: 120));
      },
      play: (index) async {
        starts.add(watch.elapsedMilliseconds);
        await Future<void>.delayed(const Duration(milliseconds: 60));
      },
      gap: const Duration(milliseconds: 40),
    );

    final gaps = [
      for (var i = 1; i < starts.length; i++) starts[i] - starts[i - 1],
    ];
    for (final gap in gaps) {
      expect(gap, inInclusiveRange(90, 130),
          reason: 'clip 60 ms + gap 40 ms; prepare must not show up');
    }
  });

  test('a cancelled run stops at the next boundary', () async {
    var plays = 0;
    var cancelled = false;
    final queue = PrefetchQueue(window: 2);

    await queue.run(
      100,
      isCancelled: () => cancelled,
      prepare: (index) async {},
      play: (index) async {
        plays++;
        if (plays == 3) cancelled = true;
        await Future<void>.delayed(const Duration(milliseconds: 5));
      },
    );

    expect(plays, 3);
  });

  test('a failing prepare does not kill the run', () async {
    var played = 0;
    await PrefetchQueue(window: 2).run(
      3,
      prepare: (index) async {
        if (index == 1) throw StateError('no audio');
      },
      play: (index) async => played++,
    );
    expect(played, 3);
  });

  test('nothing to play is not a run', () async {
    var called = false;
    await PrefetchQueue(window: 5).run(
      0,
      prepare: (index) async => called = true,
      play: (index) async => called = true,
    );
    expect(called, isFalse);
  });
}
