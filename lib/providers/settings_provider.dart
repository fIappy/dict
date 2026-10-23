import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/ai/ai_config.dart';
import '../core/ai/passage_style.dart';
import '../core/audio/speech_engine.dart';

class SettingsProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  double _fontSizeScale = 1.0;
  String _ttsLanguage = 'en-US';
  double _speechRate = 1.0;
  double _sentenceGapSeconds = 1.0;
  String _aiBaseUrl = 'https://api.openai.com/v1';
  String _aiApiKey = '';
  String _aiModel = 'gpt-4o-mini';
  AiReasoningEffort _aiReasoningEffort = AiReasoningEffort.low;
  bool _speechLoop = false;
  SpeechEngine _speechEngine = SpeechEngine.kokoro;
  double _speechVolume = 1.0;
  int _passageLength = 140;
  PassageStyle _passageStyle = PassageStyle.descriptive;

  ThemeMode get themeMode => _themeMode;
  double get fontSizeScale => _fontSizeScale;
  String get ttsLanguage => _ttsLanguage;
  double get speechRate => _speechRate;

  /// OpenAI-compatible endpoint used by the 主题 AI practice page. Kept here
  /// rather than in its own store so one settings screen owns every knob.
  String get aiBaseUrl => _aiBaseUrl;
  String get aiApiKey => _aiApiKey;
  String get aiModel => _aiModel;
  AiReasoningEffort get aiReasoningEffort => _aiReasoningEffort;

  /// Playback level, 0–1, for every screen that speaks.
  double get speechVolume => _speechVolume;

  /// Which engine reads aloud, for every screen that speaks.
  SpeechEngine get speechEngine => _speechEngine;

  /// 循环播放, shared by every multi-line player (dictionary order play,
  /// AI cards, custom passages).
  bool get speechLoop => _speechLoop;

  /// How long the reader wants generated passages, in words.
  int get passageLength => _passageLength;
  PassageStyle get passageStyle => _passageStyle;

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
    _aiBaseUrl = prefs.getString('ai_base_url') ?? 'https://api.openai.com/v1';
    _aiApiKey = prefs.getString('ai_api_key') ?? '';
    _aiModel = prefs.getString('ai_model') ?? 'gpt-4o-mini';
    _speechLoop = prefs.getBool('speech_loop') ?? false;
    _speechEngine = SpeechEngine.byName(prefs.getString('speech_engine'));
    _speechVolume = (prefs.getDouble('speech_volume') ?? 1.0).clamp(0.0, 1.0);
    _passageLength = prefs.getInt('passage_length') ?? 140;
    _passageStyle = PassageStyle.byName(prefs.getString('passage_style'));
    final effortName = prefs.getString('ai_reasoning_effort');
    _aiReasoningEffort = AiReasoningEffort.values.firstWhere(
      (e) => e.name == effortName,
      orElse: () => AiReasoningEffort.low,
    );
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

  Future<void> setSpeechVolume(double volume) async {
    final value = volume.clamp(0.0, 1.0);
    if (value == _speechVolume) return;
    _speechVolume = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('speech_volume', value);
  }

  Future<void> setSpeechEngine(SpeechEngine engine) async {
    if (engine == _speechEngine) return;
    _speechEngine = engine;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('speech_engine', engine.name);
  }

  Future<void> setSpeechLoop(bool value) async {
    if (value == _speechLoop) return;
    _speechLoop = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('speech_loop', value);
  }

  Future<void> setPassageLength(int words) async {
    final value = words.clamp(20, 10000);
    if (value == _passageLength) return;
    _passageLength = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('passage_length', value);
  }

  Future<void> setPassageStyle(PassageStyle style) async {
    if (style == _passageStyle) return;
    _passageStyle = style;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('passage_style', style.name);
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

  Future<void> setAiBaseUrl(String value) async {
    final clean = value.trim();
    if (_aiBaseUrl == clean) return;
    _aiBaseUrl = clean;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ai_base_url', clean);
  }

  Future<void> setAiApiKey(String value) async {
    final clean = value.trim();
    if (_aiApiKey == clean) return;
    _aiApiKey = clean;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ai_api_key', clean);
  }

  Future<void> setAiModel(String value) async {
    final clean = value.trim();
    if (_aiModel == clean) return;
    _aiModel = clean;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ai_model', clean);
  }

  Future<void> setAiReasoningEffort(AiReasoningEffort effort) async {
    if (_aiReasoningEffort == effort) return;
    _aiReasoningEffort = effort;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ai_reasoning_effort', effort.name);
  }
}
