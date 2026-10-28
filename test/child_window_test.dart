import 'package:flutter_test/flutter_test.dart';
import 'package:local_dict/core/platform/ai_window_launcher.dart';

/// The AI window is a second process launched with the theme on its command
/// line; this is the only piece of that contract the main window has to parse.
void main() {
  test('the flag carries the theme id', () {
    expect(aiWindowSceneId(['local_dict.exe', '--ai-window=weather']), 'weather');
    expect(aiWindowSceneId(['--ai-window=medical']), 'medical');
    expect(aiWindowSceneId(['--verbose', '--ai-window=sports', '--x']), 'sports');
  });

  test('the main window has no theme', () {
    expect(aiWindowSceneId(const []), isNull);
    expect(aiWindowSceneId(['--verbose']), isNull);
    expect(aiWindowSceneId(['--ai-window=']), isNull);
    expect(aiWindowSceneId(['--ai-window=   ']), isNull);
  });
}
