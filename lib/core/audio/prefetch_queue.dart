import 'dart:async';

import 'package:flutter/foundation.dart';

/// Runs a list of speakable items with the next [window] of them prepared while
/// the current one sounds.
///
/// The reader configures a gap between lines; a line that still has to be
/// synthesised (or downloaded) when its turn comes turns that gap into
/// "gap + render". Preparing ahead means only the very first item pays.
///
/// [prepare] is called in order and may take as long as it likes; [play] is
/// called once the item it belongs to is ready and must return when the sound
/// has finished. Nothing is prepared beyond [window], so a long list does not
/// fill memory with audio.
class PrefetchQueue {
  PrefetchQueue({this.window = 10});

  /// How many items may be prepared ahead of the one playing.
  final int window;

  /// Runs [count] items.
  ///
  /// [isCancelled] is polled before every step, so a stop takes effect at the
  /// next boundary rather than at the end of the list.
  Future<void> run(
    int count, {
    required Future<void> Function(int index) prepare,
    required Future<void> Function(int index) play,
    Duration gap = Duration.zero,
    bool Function()? isCancelled,
    void Function(int index)? onStart,
  }) async {
    if (count <= 0) return;
    final pending = <int, Future<void>>{};

    // A failure while preparing must not become an unhandled error in a future
    // nobody is awaiting yet: it is recorded and surfaces when the item plays.
    Future<void> prepareAt(int index) {
      if (index < 0 || index >= count) return Future<void>.value();
      return pending[index] ??= prepare(index).catchError((Object error) {
        debugPrint('Prefetch of item $index failed: $error');
      });
    }

    void fill(int from) {
      for (var ahead = from; ahead < from + window && ahead < count; ahead++) {
        unawaited(prepareAt(ahead));
      }
    }

    fill(0);
    for (var index = 0; index < count; index++) {
      if (isCancelled?.call() ?? false) return;
      await prepareAt(index);
      pending.remove(index);
      fill(index + 1);
      if (isCancelled?.call() ?? false) return;
      onStart?.call(index);
      await play(index);
      if (isCancelled?.call() ?? false) return;
      if (gap > Duration.zero && index + 1 < count) {
        await Future<void>.delayed(gap);
      }
    }
  }
}
