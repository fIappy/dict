import 'package:flutter_test/flutter_test.dart';
import 'package:local_dict/core/ui/ui_memory.dart';
import 'package:local_dict/core/audio/speech_engine.dart';
import 'package:local_dict/providers/alphabet_provider.dart';
import 'package:local_dict/providers/custom_text_provider.dart';
import 'package:local_dict/providers/ipa_provider.dart';
import 'package:local_dict/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the custom group reopens where it was left', () async {
    final first = CustomTextProvider();
    await first.initialize();
    await first.addGroup('家庭场景');
    final group = first.groups.single;
    first.selectGroup(group.id);

    final second = CustomTextProvider();
    await second.initialize();

    expect(second.selectedGroupId, group.id);
    expect(second.selectedGroupName, '家庭场景');
  });

  test('a group that no longer exists falls back to 未分组', () async {
    SharedPreferences.setMockInitialValues({
      'flutter.${UiMemory.customGroup}': 'gone',
    });
    final provider = CustomTextProvider();
    await provider.initialize();
    expect(provider.selectedGroupId, CustomTextProvider.ungroupedId);
  });

  test('the phoneme list reopens on the same symbol', () async {
    SharedPreferences.setMockInitialValues({
      'flutter.${UiMemory.ipaSymbol}': '/æ/',
      'flutter.${UiMemory.ipaAccent}': 'usOnly',
    });
    final provider = IpaProvider();
    await provider.restore();
    expect(provider.selectedSymbol, '/æ/');
    expect(provider.selectedAccent?.name, 'usOnly');
  });

  test('the alphabet list reopens on the same letter', () async {
    SharedPreferences.setMockInitialValues({
      'flutter.${UiMemory.letter}': 'M',
    });
    final provider = AlphabetProvider();
    await provider.restore();
    expect(provider.selectedChar, 'M');
  });

  test('the engine choice is remembered', () async {
    final first = SettingsProvider();
    await first.initialize();
    expect(first.speechEngine, SpeechEngine.kokoro);

    await first.setSpeechEngine(SpeechEngine.system);

    final second = SettingsProvider();
    await second.initialize();
    expect(second.speechEngine, SpeechEngine.system);
  });

  test('the volume is remembered', () async {
    final first = SettingsProvider();
    await first.initialize();
    expect(first.speechVolume, 1.0);

    await first.setSpeechVolume(0.4);

    final second = SettingsProvider();
    await second.initialize();
    expect(second.speechVolume, closeTo(0.4, 1e-9));
  });
}
