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

/// One answer: the text to parse, plus whatever the model was willing to say
/// about how it got there.
class AiReply {
  const AiReply({required this.text, this.reasoning});

  final String text;

  /// The model's own reasoning (DeepSeek `reasoning_content`, OpenAI
  /// `reasoning`), when the endpoint exposes it. Null when it does not.
  final String? reasoning;
}

/// Chat completions against an OpenAI-compatible endpoint over plain REST.
class OpenAiClient {
  OpenAiClient({
    required this.config,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 90),
  }) : _http = httpClient ?? http.Client();

  final AiConfig config;
  final http.Client _http;
  final Duration timeout;

  Map<String, String> _headers({bool jsonBody = false}) {
    final headers = <String, String>{'Accept': 'application/json'};
    if (jsonBody) {
      headers['Content-Type'] = 'application/json; charset=utf-8';
    }
    final key = config.apiKey.trim();
    if (key.isNotEmpty) {
      headers['Authorization'] = 'Bearer $key';
    }
    return headers;
  }

  /// Sends [system] + [user] and returns the answer with its reasoning.
  Future<AiReply> complete({
    required String system,
    required String user,
    double temperature = 0.7,
    int? maxTokens,
    Duration? timeout,
  }) async {
    if (!config.isConfigured) {
      throw const AiException('尚未配置 AI 接口，请到设置里填写 Base URL 与模型');
    }
    final effectiveTimeout = timeout ?? this.timeout;
    try {
      try {
        return await _invoke(
          system: system,
          user: user,
          temperature: temperature,
          maxTokens: maxTokens,
          effort: config.reasoningEffort,
          timeout: effectiveTimeout,
        );
      } on _ApiHttpError catch (e) {
        if (!_rejectsReasoning(e)) rethrow;
        return await _invoke(
          system: system,
          user: user,
          temperature: temperature,
          maxTokens: maxTokens,
          effort: null,
          timeout: effectiveTimeout,
        );
      }
    } on AiException {
      rethrow;
    } on TimeoutException {
      throw AiException('接口超时（${effectiveTimeout.inSeconds} 秒没有响应）');
    } on _ApiHttpError catch (e) {
      throw AiException(_redact(_statusMessage(e.statusCode, e.message)));
    } on FormatException {
      throw const AiException('接口返回内容无法解析为 JSON');
    } on Exception catch (e) {
      throw AiException(_redact('无法连接接口：$e'));
    }
  }

  Future<AiReply> _invoke({
    required String system,
    required String user,
    required double temperature,
    required int? maxTokens,
    required AiReasoningEffort? effort,
    required Duration timeout,
  }) async {
    final payload = <String, dynamic>{
      'model': config.model.trim(),
      'messages': [
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': user},
      ],
      'temperature': temperature,
      'max_tokens': ?maxTokens,
      if (effort != null) 'reasoning_effort': effort.name,
    };

    final uri = Uri.parse(config.chatCompletionsUrl);
    final res = await _http
        .post(uri, headers: _headers(jsonBody: true), body: jsonEncode(payload))
        .timeout(timeout);

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw _ApiHttpError(res.statusCode, _extractErrorDetail(res.body));
    }

    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (decoded is! Map) {
      throw const AiException('接口返回格式异常');
    }
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty || choices.first is! Map) {
      throw const AiException('接口没有返回 choices');
    }
    final message = (choices.first as Map)['message'];
    if (message is! Map) {
      throw const AiException('接口返回缺少 message');
    }

    final reasoningParts = <String>[];
    for (final key in const ['reasoning_content', 'reasoning']) {
      final raw = message[key];
      if (raw is String && raw.trim().isNotEmpty) {
        reasoningParts.add(raw.trim());
      }
    }

    final rawContent = message['content'];
    String text = '';
    if (rawContent is String) {
      text = rawContent;
    } else if (rawContent is List) {
      final textBuf = StringBuffer();
      for (final block in rawContent) {
        if (block is! Map) continue;
        final type = block['type'];
        if (type == 'reasoning' && block['reasoning'] is String) {
          final r = (block['reasoning'] as String).trim();
          if (r.isNotEmpty) reasoningParts.add(r);
        } else if (block['text'] is String) {
          textBuf.write(block['text'] as String);
        }
      }
      text = textBuf.toString();
    }

    if (text.trim().isEmpty) {
      throw const AiException('接口返回了空内容');
    }
    final reasoning = reasoningParts.join('\n\n').trim();
    return AiReply(
      text: text,
      reasoning: reasoning.isEmpty ? null : reasoning,
    );
  }

  /// The model ids the endpoint advertises.
  Future<List<String>> listModels() async {
    if (!config.isConfigured) {
      throw const AiException('先把 Base URL 填上，才能读取模型列表');
    }
    final uri = Uri.parse('${config.apiBaseUrl}/models');
    try {
      final res = await _http.get(uri, headers: _headers()).timeout(timeout);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw _ApiHttpError(res.statusCode, _extractErrorDetail(res.body));
      }
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is! Map || decoded['data'] is! List) {
        throw const AiException('模型列表格式异常');
      }
      final ids = <String>[
        for (final item in decoded['data'] as List)
          if (item is Map && item['id'] is String)
            (item['id'] as String).trim(),
      ]..removeWhere((id) => id.isEmpty);
      ids.sort();
      if (ids.isEmpty) {
        throw const AiException('接口没有返回任何模型');
      }
      return ids;
    } on AiException {
      rethrow;
    } on TimeoutException {
      throw AiException('读取模型列表超时（${timeout.inSeconds} 秒）');
    } on _ApiHttpError catch (e) {
      throw AiException(_redact(_statusMessage(e.statusCode, e.message)));
    } on FormatException {
      throw const AiException('模型列表返回内容无法解析为 JSON');
    } on Exception catch (e) {
      throw AiException(_redact('无法连接接口：$e'));
    }
  }

  static String _extractErrorDetail(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final err = decoded['error'];
        if (err is Map && err['message'] != null) {
          return '${err['message']}';
        }
        if (err is String) return err;
        if (decoded['message'] != null) return '${decoded['message']}';
      }
    } catch (_) {}
    final trimmed = body.trim();
    return trimmed.length > 200 ? trimmed.substring(0, 200) : trimmed;
  }

  static bool _rejectsReasoning(_ApiHttpError error) {
    if (error.statusCode != 400 && error.statusCode != 422) return false;
    final text = error.message.toLowerCase();
    return text.contains('reasoning') || text.contains('unsupported');
  }

  String _statusMessage(int statusCode, String detail) {
    final trimmed = detail.trim();
    final suffix = trimmed.isEmpty ? '' : '·$trimmed';
    switch (statusCode) {
      case 401:
      case 403:
        return '鉴权失败（$statusCode）：API Key 被拒绝$suffix';
      case 404:
        return '接口地址不对（404）：检查 Base URL 是否以 /v1 结尾$suffix';
      case 429:
        return '触发限流（429）：稍后再试$suffix';
      default:
        return '接口报错（$statusCode）${trimmed.isEmpty ? '' : '：$trimmed'}';
    }
  }

  String _redact(String message) {
    final secret = config.apiKey.trim();
    if (secret.length < 4) return message;
    return message.replaceAll(secret, '***');
  }

  void close() => _http.close();
}

class _ApiHttpError implements Exception {
  const _ApiHttpError(this.statusCode, this.message);
  final int statusCode;
  final String message;
}
