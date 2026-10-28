import 'package:flutter_test/flutter_test.dart';
import 'package:local_dict/core/platform/child_window_launcher.dart';

/// A child window is a second process launched with the theme on its command
/// line; this is the only piece of that contract the main window has to parse.
void main() {
  test('the AI flag carries the theme id', () {
    expect(childWindowRequest(['local_dict.exe', '--ai-window=weather']),
        (window: ChildWindow.ai, sceneId: 'weather'));
    expect(childWindowRequest(['--ai-window=medical']),
        (window: ChildWindow.ai, sceneId: 'medical'));
    expect(childWindowRequest(['--verbose', '--ai-window=sports', '--x']),
        (window: ChildWindow.ai, sceneId: 'sports'));
  });

  test('the vocabulary flag carries the theme id', () {
    expect(childWindowRequest(['local_dict.exe', '--vocab-window=health']),
        (window: ChildWindow.vocabulary, sceneId: 'health'));
    expect(childWindowRequest(['--vocab-window=t01']),
        (window: ChildWindow.vocabulary, sceneId: 't01'));
  });

  test('the main window has no theme', () {
    expect(childWindowRequest(const []), isNull);
    expect(childWindowRequest(['--verbose']), isNull);
    expect(childWindowRequest(['--ai-window=']), isNull);
    expect(childWindowRequest(['--ai-window=   ']), isNull);
    expect(childWindowRequest(['--vocab-window=']), isNull);
  });
}
