import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:langchain/langchain.dart';
import 'package:langchain_openai/langchain_openai.dart';
import 'package:openai_dart/openai_dart.dart' as oai;

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

/// Chat completions against an OpenAI-compatible endpoint.
///
/// The transport is `langchain_openai`'s [ChatOpenAI] rather than a hand-rolled
/// POST: it owns request/response mapping, retries and error types, and the same
/// `BaseChatModel` interface is what every other provider in langchain_dart
/// speaks. This class adds the app's configuration, its timeout, the reasoning
/// effort knob and the user-facing error wording.
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

  /// Sends [system] + [user] and returns the answer with its reasoning.
  ///
  /// JSON mode is deliberately not requested: compatible servers disagree about
  /// `responseFormat`, and a prompt that asks for JSON plus a lenient parser
  /// works on all of them.
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
    try {
      try {
        return await _invoke(
          system: system,
          user: user,
          temperature: temperature,
          maxTokens: maxTokens,
          effort: config.reasoningEffort,
          timeout: timeout,
        );
      } on oai.ApiException catch (e) {
        // Older servers reject the parameter outright. Asking again without it
        // is cheaper than making the reader discover a toggle.
        if (!_rejectsReasoning(e)) rethrow;
        return await _invoke(
          system: system,
          user: user,
          temperature: temperature,
          maxTokens: maxTokens,
          effort: null,
          timeout: timeout,
        );
      }
    } on AiException {
      rethrow;
    } on TimeoutException {
      throw AiException('接口超时（${(timeout ?? this.timeout).inSeconds} 秒没有响应）');
    } on oai.ApiException catch (e) {
      throw AiException(_statusMessage(e.statusCode, e.message));
    } on oai.OpenAIException catch (e) {
      throw AiException('接口调用失败：${e.message}');
    } on Exception catch (e) {
      throw AiException('无法连接接口：$e');
    }
  }

  Future<AiReply> _invoke({
    required String system,
    required String user,
    required double temperature,
    required int? maxTokens,
    required AiReasoningEffort? effort,
    Duration? timeout,
  }) async {
    final reply = await _chat(
      [ChatMessage.system(system), ChatMessage.humanText(user)],
      options: ChatOpenAIOptions(
        model: config.model,
        temperature: temperature,
        maxTokens: maxTokens,
        reasoningEffort: effort == null ? null : _chatEffort(effort),
      ),
    ).timeout(timeout ?? this.timeout);

    final text = reply.contentAsString;
    if (text.trim().isEmpty) {
      throw const AiException('接口返回了空内容');
    }
    final reasoning = reply.content
        .whereType<AIChatMessageReasoningBlock>()
        .map((block) => block.reasoning.trim())
        .where((part) => part.isNotEmpty)
        .join('\n\n');
    return AiReply(
      text: text,
      reasoning: reasoning.isEmpty ? null : reasoning,
    );
  }

  /// The model ids the endpoint advertises — the reader's way to find out what
  /// a host actually serves instead of guessing names.
  Future<List<String>> listModels() async {
    if (!config.isConfigured) {
      throw const AiException('先把 Base URL 填上，才能读取模型列表');
    }
    final client = oai.OpenAIClient(
      config: oai.OpenAIConfig(
        authProvider: oai.ApiKeyProvider(config.apiKey.trim()),
        baseUrl: config.apiBaseUrl,
      ),
      httpClient: _http,
    );
    try {
      final list = await client.models.list().timeout(timeout);
      final ids = [for (final model in list.data) model.id]..sort();
      if (ids.isEmpty) {
        throw const AiException('接口没有返回任何模型');
      }
      return ids;
    } on AiException {
      rethrow;
    } on TimeoutException {
      throw AiException('读取模型列表超时（${timeout.inSeconds} 秒）');
    } on oai.ApiException catch (e) {
      throw AiException(_statusMessage(e.statusCode, e.message));
    } on oai.OpenAIException catch (e) {
      throw AiException('读取模型列表失败：${e.message}');
    } on Exception catch (e) {
      throw AiException('无法连接接口：$e');
    }
  }

  static ChatOpenAIReasoningEffort _chatEffort(AiReasoningEffort effort) =>
      ChatOpenAIReasoningEffort.values.firstWhere(
        (value) => value.name == effort.name,
        orElse: () => ChatOpenAIReasoningEffort.low,
      );

  static bool _rejectsReasoning(oai.ApiException error) {
    if (error.statusCode != 400 && error.statusCode != 422) return false;
    final text =
        '${error.message} ${error.code ?? ''} ${error.type ?? ''}'.toLowerCase();
    return text.contains('reasoning') || text.contains('unsupported');
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
