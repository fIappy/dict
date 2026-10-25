import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

/// Remembers the main window's frame — corner, size, and whether it was
/// maximised.
///
/// Desktop only: a phone owns that frame, and on the web there is no window to
/// place, so every call here is a no-op. Restoring runs before the first frame
/// (the runner shows the window only when Dart asks for it), and saving is
/// debounced because dragging a frame fires one move event per pixel.
class WindowFrame {
  static const String _keyX = 'ui_window_x';
  static const String _keyY = 'ui_window_y';
  static const String _keyW = 'ui_window_w';
  static const String _keyH = 'ui_window_h';
  static const String _keyMaximized = 'ui_window_maximized';

  /// Used the first time the app runs, and whenever the remembered frame is
  /// unusable (a monitor that no longer exists, a hand-edited pref).
  static const Size defaultSize = Size(1280, 800);

  /// Below this the desktop layout — rail, list, detail pane — stops fitting.
  static const Size minimumSize = Size(900, 600);

  static bool get isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS);

  static bool _usable(double? width, double? height) =>
      width != null &&
      height != null &&
      width >= minimumSize.width &&
      height >= minimumSize.height &&
      width < 10000 &&
      height < 10000;

  static bool _onScreen(double? x, double? y) =>
      x != null && y != null && x.abs() < 20000 && y.abs() < 20000;

  /// Applies the remembered frame, then shows the window.
  ///
  /// Await it before `runApp`: the window stays hidden until the callback runs,
  /// so the reader never sees the runner's default 1280×720 box first.
  static Future<void> restore() async {
    if (!isDesktop) return;
    try {
      await windowManager.ensureInitialized();
      final prefs = await SharedPreferences.getInstance();
      final width = prefs.getDouble(_keyW);
      final height = prefs.getDouble(_keyH);
      final x = prefs.getDouble(_keyX);
      final y = prefs.getDouble(_keyY);
      final maximized = prefs.getBool(_keyMaximized) ?? false;

      final sized = _usable(width, height);
      final placed = sized && _onScreen(x, y);
      final frame = sized ? Size(width!, height!) : defaultSize;
      final origin = placed ? Offset(x!, y!) : null;

      await windowManager.waitUntilReadyToShow(
        WindowOptions(
          size: frame,
          center: origin == null,
          minimumSize: minimumSize,
          title: '本地词典 - Local Dictionary',
        ),
        () async {
          if (origin != null) await windowManager.setPosition(origin);
          await windowManager.show();
          // After the window is up: the plugin posts SC_MAXIMIZE, and a message
          // posted to a still-hidden window is dropped.
          if (maximized) await windowManager.maximize();
          await windowManager.focus();
        },
      );
    } on Exception catch (e) {
      // A frame that cannot be restored must not keep the app from opening.
      debugPrint('Window frame not restored: $e');
    }
  }

  /// Writes the current frame. Called a beat after the last move/resize, and
  /// once more on close.
  static Future<void> save() async {
    if (!isDesktop) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final maximized = await windowManager.isMaximized();
      await prefs.setBool(_keyMaximized, maximized);
      // While maximised the frame is the screen's, not the reader's; keep the
      // size we had before so un-maximising next launch still fits.
      if (maximized) return;
      final bounds = await windowManager.getBounds();
      if (bounds.width <= 0 || bounds.height <= 0) return;
      await prefs.setDouble(_keyX, bounds.left);
      await prefs.setDouble(_keyY, bounds.top);
      await prefs.setDouble(_keyW, bounds.width);
      await prefs.setDouble(_keyH, bounds.height);
    } on Exception catch (e) {
      debugPrint('Window frame not saved: $e');
    }
  }
}

/// Saves the frame whenever the reader stops dragging or resizing it.
///
/// Sits above the app and draws nothing. Closing is held for one save so the
/// last drag is not lost: the window is destroyed after the write, not before.
class WindowFrameKeeper extends StatefulWidget {
  final Widget child;

  const WindowFrameKeeper({super.key, required this.child});

  @override
  State<WindowFrameKeeper> createState() => _WindowFrameKeeperState();
}

class _WindowFrameKeeperState extends State<WindowFrameKeeper>
    with WindowListener {
  Timer? _pending;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    if (!WindowFrame.isDesktop) return;
    windowManager
      ..addListener(this)
      ..setPreventClose(true);
  }

  @override
  void dispose() {
    _pending?.cancel();
    if (WindowFrame.isDesktop) windowManager.removeListener(this);
    super.dispose();
  }

  void _later() {
    _pending?.cancel();
    _pending = Timer(const Duration(milliseconds: 400), WindowFrame.save);
  }

  @override
  void onWindowMove() => _later();

  @override
  void onWindowResize() => _later();

  @override
  void onWindowMaximize() => _later();

  @override
  void onWindowUnmaximize() => _later();

  @override
  Future<void> onWindowClose() async {
    if (_closing) return;
    _closing = true;
    _pending?.cancel();
    await WindowFrame.save();
    // Hand the close back to the runner: destroying from here only posts a quit
    // message, and the window would sit there until the engine finished
    // shutting down (seconds, with the speech model loaded).
    await windowManager.setPreventClose(false);
    await windowManager.close();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
