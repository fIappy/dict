import 'dart:io';

import 'package:flutter/foundation.dart';

/// The flag an AI window is launched with: `local_dict --ai-window=<sceneId>`.
const String aiWindowFlag = '--ai-window=';

/// The theme an AI window was opened for, or null when this is the main window.
String? aiWindowSceneId(List<String> args) {
  for (final arg in args) {
    if (!arg.startsWith(aiWindowFlag)) continue;
    final id = arg.substring(aiWindowFlag.length).trim();
    if (id.isNotEmpty) return id;
  }
  return null;
}

/// Whether this build can open the AI practice in its own OS window.
///
/// Only Windows for now: the runner there already forwards its command line to
/// Dart, which is what tells the new process which theme to show. Elsewhere the
/// page opens as a normal route instead.
bool get aiWindowsSupported => !kIsWeb && Platform.isWindows;

/// Windows already open, by theme, so a second click on the same theme does not
/// stack duplicates. An entry leaves the map when that window closes.
final Map<String, Process> _openWindows = {};

/// Opens (or reuses) the AI window for [sceneId].
///
/// A second window is a second **process**: an engine created inside this one by
/// a multi-window plugin would come up without any plugin of its own — no
/// storage, no audio — and the AI page needs both. A fresh process is an
/// ordinary app, so everything works and the two windows cannot block each
/// other.
Future<bool> openAiWindow(String sceneId) async {
  if (!aiWindowsSupported) return false;
  if (_openWindows.containsKey(sceneId)) return true;
  try {
    final process = await Process.start(
      Platform.resolvedExecutable,
      ['$aiWindowFlag$sceneId'],
    );
    // Nobody reads the child's output; without draining, a chatty child would
    // eventually block writing into a full pipe.
    process.stdout.drain<void>();
    process.stderr.drain<void>();
    _openWindows[sceneId] = process;
    process.exitCode.then((_) => _openWindows.remove(sceneId));
    return true;
  } on Exception catch (e) {
    debugPrint('Could not open the AI window: $e');
    return false;
  }
}
