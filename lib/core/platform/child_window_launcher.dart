import 'dart:io';

import 'package:flutter/foundation.dart';

/// A window the main one can open beside itself, each as its own process.
///
/// A second engine inside this process would come up without any plugin of its
/// own — no storage, no audio, no window manager — so a second window is a
/// second **process**: an ordinary app that cannot block this one.
enum ChildWindow {
  /// AI 练习: generated sentences and passages for one theme.
  ai('--ai-window=', 'AI 练习'),

  /// 背词: the theme's words with their meanings and stars.
  vocabulary('--vocab-window=', '背词');

  const ChildWindow(this.flag, this.windowTitle);

  final String flag;
  final String windowTitle;
}

/// Which child window the command line asks for, and for which theme.
({ChildWindow window, String sceneId})? childWindowRequest(List<String> args) {
  for (final window in ChildWindow.values) {
    for (final arg in args) {
      if (!arg.startsWith(window.flag)) continue;
      final id = arg.substring(window.flag.length).trim();
      if (id.isNotEmpty) return (window: window, sceneId: id);
    }
  }
  return null;
}

/// Whether this build can open child windows at all.
///
/// Only Windows for now: the runner there forwards its command line to Dart,
/// which is what tells the new process which window to show. Elsewhere the
/// pages open as normal routes instead.
bool get childWindowsSupported => !kIsWeb && Platform.isWindows;

/// Windows already open, by kind and theme, so a second click on the same
/// button does not stack duplicates. An entry leaves when that window closes.
final Map<String, Process> _openWindows = {};

String _keyOf(ChildWindow window, String sceneId) => '${window.name}:$sceneId';

/// Opens (or reuses) [window] for [sceneId]. False when this build cannot.
Future<bool> openChildWindow(ChildWindow window, String sceneId) async {
  if (!childWindowsSupported) return false;
  final key = _keyOf(window, sceneId);
  if (_openWindows.containsKey(key)) return true;
  try {
    final process = await Process.start(
      Platform.resolvedExecutable,
      ['${window.flag}$sceneId'],
    );
    // Nobody reads the child's output; without draining, a chatty child would
    // eventually block writing into a full pipe.
    process.stdout.drain<void>();
    process.stderr.drain<void>();
    _openWindows[key] = process;
    process.exitCode.then((_) => _openWindows.remove(key));
    return true;
  } on Exception catch (e) {
    debugPrint('Could not open the ${window.windowTitle} window: $e');
    return false;
  }
}
