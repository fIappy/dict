import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  double _fontSizeScale = 1.0;
  String _ttsLanguage = 'en-US';
  double _speechRate = 1.0;
  double _sentenceGapSeconds = 1.0;

  ThemeMode get themeMode => _themeMode;
  double get fontSizeScale => _fontSizeScale;
  String get ttsLanguage => _ttsLanguage;
  double get speechRate => _speechRate;

  /// Pause between two lines during 顺序播放 of an entry's phrases/examples.
  Duration get sentenceGap =>
      Duration(milliseconds: (_sentenceGapSeconds * 1000).round());

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final themeStr = prefs.getString('theme_mode') ?? 'system';
    switch (themeStr) {
      case 'light':
        _themeMode = ThemeMode.light;
        break;
      case 'dark':
        _themeMode = ThemeMode.dark;
        break;
      default:
        _themeMode = ThemeMode.system;
    }
    _fontSizeScale = prefs.getDouble('font_size_scale') ?? 1.0;
    _ttsLanguage = prefs.getString('tts_language') ?? 'en-US';
    _speechRate = prefs.getDouble('speech_rate') ?? 1.0;
    _sentenceGapSeconds = prefs.getDouble('sentence_gap_seconds') ?? 1.0;
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', mode.name);
  }

  Future<void> setFontSizeScale(double scale) async {
    _fontSizeScale = scale;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('font_size_scale', scale);
  }

  Future<void> setTtsLanguage(String lang) async {
    _ttsLanguage = lang;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tts_language', lang);
  }

  Future<void> setSpeechRate(double rate) async {
    _speechRate = rate;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('speech_rate', rate);
  }

  Future<void> setSentenceGapSeconds(double seconds) async {
    _sentenceGapSeconds = seconds;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('sentence_gap_seconds', seconds);
  }
}
