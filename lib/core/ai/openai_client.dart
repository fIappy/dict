import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai_config.dart';

/// A failed call, already turned into something the reader can act on —
/// "401 means the key was rejected", not a stack trace.
class AiException implements Exception {
  const AiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Minimal OpenAI-compatible chat client: one text completion per call.
class OpenAiClient {
  OpenAiClient({
    required this.config,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 90),
  }) : _http = httpClient ?? http.Client();

  final AiConfig config;
  final http.Client _http;
  final Duration timeout;

  /// Sends [system] + [user] and returns the assistant text.
  ///
  /// JSON mode is deliberately not requested: compatible servers disagree about
  /// `response_format`, and a prompt that asks for JSON plus a lenient parser
  /// works on all of them.
  Future<String> complete({
    required String system,
    required String user,
    double temperature = 0.7,
    int? maxTokens,
  }) async {
    if (!config.isConfigured) {
      throw const AiException('尚未配置 AI 接口，请到设置里填写 Base URL 与模型');
    }

    final body = <String, Object?>{
      'model': config.model,
      'temperature': temperature,
      'messages': [
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': user},
      ],
      'max_tokens': ?maxTokens,
    };

    // A local runtime ignores the token, so an empty key is simply not sent.
    final headers = <String, String>{'Content-Type': 'application/json'};
    final key = config.apiKey.trim();
    if (key.isNotEmpty) headers['Authorization'] = 'Bearer $key';

    final http.Response response;
    try {
      response = await _http
          .post(
            Uri.parse(config.chatCompletionsUrl),
            headers: headers,
            body: jsonEncode(body),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw AiException('接口超时（${timeout.inSeconds} 秒没有响应）');
    } on Exception catch (e) {
      throw AiException('无法连接接口：$e');
    }

    if (response.statusCode != 200) {
      throw AiException(_statusMessage(response));
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const AiException('接口返回的不是 JSON');
    }
    if (decoded is! Map) {
      throw const AiException('接口返回的 JSON 结构不对');
    }

    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      throw const AiException('接口没有返回任何内容（choices 为空）');
    }
    final message = (choices.first as Map?)?['message'];
    final content = (message as Map?)?['content'];
    if (content is! String || content.trim().isEmpty) {
      throw const AiException('接口返回了空内容');
    }
    return content;
  }

  /// Turns the usual failures into one sentence each; anything else keeps the
  /// server's own words so a proxy can say what it wants.
  String _statusMessage(http.Response response) {
    final detail = _errorDetail(response);
    switch (response.statusCode) {
      case 401:
      case 403:
        return '鉴权失败（${response.statusCode}）：API Key 被拒绝${detail.isEmpty ? '' : '·$detail'}';
      case 404:
        return '接口地址不对（404）：检查 Base URL 是否以 /v1 结尾${detail.isEmpty ? '' : '·$detail'}';
      case 429:
        return '触发限流（429）：稍后再试${detail.isEmpty ? '' : '·$detail'}';
      default:
        final text = detail.isEmpty ? response.reasonPhrase ?? '' : detail;
        return '接口报错（${response.statusCode}）${text.isEmpty ? '' : '：$text'}';
    }
  }

  String _errorDetail(http.Response response) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is Map && error['message'] is String) {
          return error['message'] as String;
        }
        if (error is String) return error;
        if (decoded['message'] is String) return decoded['message'] as String;
      }
    } on Exception {
      // Not JSON: fall through to the raw body.
    }
    final raw = utf8.decode(response.bodyBytes, allowMalformed: true).trim();
    return raw.length > 160 ? '${raw.substring(0, 160)}…' : raw;
  }

  void close() => _http.close();
}
