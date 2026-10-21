import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:langchain/langchain.dart';
import 'package:langchain_openai/langchain_openai.dart';
import 'package:openai_dart/openai_dart.dart' show ApiException, OpenAIException;

import 'ai_config.dart';

/// A failed call, already turned into something the reader can act on —
/// "401 means the key was rejected", not a stack trace.
class AiException implements Exception {
  const AiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// One chat completion against an OpenAI-compatible endpoint.
///
/// The transport is `langchain_openai`'s [ChatOpenAI] rather than a hand-rolled
/// POST: it owns the request/response mapping, retries and error types, and the
/// same `BaseChatModel` interface is what every other provider in langchain_dart
/// speaks — so swapping in another vendor later is a constructor change, not a
/// rewrite. This class only adds the app's configuration, its timeout and its
/// user-facing error wording.
class OpenAiClient {
  OpenAiClient({
    required this.config,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 90),
  }) : _http = httpClient ?? http.Client() {
    _chat = ChatOpenAI(
      apiKey: config.apiKey.trim().isEmpty ? null : config.apiKey.trim(),
      baseUrl: config.apiBaseUrl,
      client: _http,
      defaultOptions: ChatOpenAIOptions(model: config.model),
    );
  }

  final AiConfig config;
  final http.Client _http;
  final Duration timeout;

  late final ChatOpenAI _chat;

  /// Sends [system] + [user] and returns the assistant text.
  ///
  /// JSON mode is deliberately not requested: compatible servers disagree about
  /// `responseFormat`, and a prompt that asks for JSON plus a lenient parser
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

    final AIChatMessage reply;
    try {
      reply = await _chat(
        [ChatMessage.system(system), ChatMessage.humanText(user)],
        options: ChatOpenAIOptions(
          model: config.model,
          temperature: temperature,
          maxTokens: maxTokens,
        ),
      ).timeout(timeout);
    } on TimeoutException {
      throw AiException('接口超时（${timeout.inSeconds} 秒没有响应）');
    } on ApiException catch (e) {
      throw AiException(_statusMessage(e.statusCode, e.message));
    } on OpenAIException catch (e) {
      throw AiException('接口调用失败：${e.message}');
    } on Exception catch (e) {
      throw AiException('无法连接接口：$e');
    }

    final text = reply.contentAsString;
    if (text.trim().isEmpty) {
      throw const AiException('接口返回了空内容');
    }
    return text;
  }

  /// Turns the usual failures into one sentence each; anything else keeps the
  /// server's own words so a proxy can say what it wants.
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

  void close() => _http.close();
}
