import 'package:shared_preferences/shared_preferences.dart';

/// The handful of "put me back where I was" values.
///
/// Everything here is a *place*, not a preference: which section was open, how
/// wide the split was, which word/phoneme/letter/group was selected. Each owner
/// (a provider or the home shell) reads and writes its own key, so no central
/// state has to know about the others.
class UiMemory {
  static const String section = 'ui_section';
  static const String paneWidth = 'ui_pane_width';
  static const String word = 'ui_word';
  static const String ipaSymbol = 'ui_ipa_symbol';
  static const String ipaAccent = 'ui_ipa_accent';
  static const String ipaVariants = 'ui_ipa_variants';
  static const String letter = 'ui_alphabet_letter';
  static const String customGroup = 'ui_custom_group';

  static Future<int?> readInt(String key) async =>
      (await SharedPreferences.getInstance()).getInt(key);

  static Future<double?> readDouble(String key) async =>
      (await SharedPreferences.getInstance()).getDouble(key);

  static Future<bool?> readBool(String key) async =>
      (await SharedPreferences.getInstance()).getBool(key);

  static Future<String?> readString(String key) async =>
      (await SharedPreferences.getInstance()).getString(key);

  static Future<void> writeInt(String key, int value) async =>
      (await SharedPreferences.getInstance()).setInt(key, value);

  static Future<void> writeDouble(String key, double value) async =>
      (await SharedPreferences.getInstance()).setDouble(key, value);

  static Future<void> writeBool(String key, bool value) async =>
      (await SharedPreferences.getInstance()).setBool(key, value);

  static Future<void> writeString(String key, String value) async =>
      (await SharedPreferences.getInstance()).setString(key, value);
}
