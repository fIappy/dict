import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'online_tts.dart';
import 'speech_engine.dart';

/// Fetches word pronunciation audio online without touching `.mdd` archives.
///
/// Tries Youdao's dictionary voice first (`type=1` British, `type=2` American),
/// then falls back to Google and Baidu online TTS endpoints when needed.
Future<Uint8List?> fetchOnlineWordAudio(
  String word, {
  String accent = 'us',
  http.Client? client,
}) async {
  final trimmed = word.trim();
  if (trimmed.isEmpty) return null;
  final normAccent = accent.toLowerCase() == 'uk' ? 'uk' : 'us';
  final type = normAccent == 'uk' ? 1 : 2;
  final youdaoUri = Uri.parse(
    'https://dict.youdao.com/dictvoice?audio=${Uri.encodeComponent(trimmed)}&type=$type',
  );

  final ownedClient = client == null;
  final httpClient = client ?? http.Client();
  try {
    try {
      final res = await httpClient
          .get(
            youdaoUri,
            headers: const {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'},
          )
          .timeout(const Duration(seconds: 4));
      if (res.statusCode == 200 && OnlineTts.looksLikeAudio(res.bodyBytes)) {
        return res.bodyBytes;
      }
    } catch (_) {}

    final google = await OnlineTts.synthesize(
      SpeechEngine.google,
      text: trimmed,
      accent: normAccent,
      client: httpClient,
    );
    if (google != null && OnlineTts.looksLikeAudio(google)) {
      return google;
    }

    final baidu = await OnlineTts.synthesize(
      SpeechEngine.baidu,
      text: trimmed,
      accent: normAccent,
      client: httpClient,
    );
    if (baidu != null && OnlineTts.looksLikeAudio(baidu)) {
      return baidu;
    }
    return null;
  } finally {
    if (ownedClient) httpClient.close();
  }
}
