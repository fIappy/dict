/// Endpoint, key and model for an OpenAI-compatible chat completion API.
///
/// The shape is the de-facto standard: `POST <base>/chat/completions` with
/// `messages`, answered with `choices[0].message.content`. Local runtimes
/// (Ollama, LM Studio, vLLM, one-api) speak it, and so does the official
/// service, so one client covers all of them.
class AiConfig {
  const AiConfig({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
  });

  static const String defaultBaseUrl = 'https://api.openai.com/v1';
  static const String defaultModel = 'gpt-4o-mini';

  /// Base URL as the reader typed it, e.g. `http://127.0.0.1:11434/v1`.
  final String baseUrl;

  /// Bearer token. A local runtime usually ignores it, so an empty key is only
  /// refused by servers that actually require one.
  final String apiKey;

  final String model;

  bool get isConfigured => baseUrl.trim().isNotEmpty && model.trim().isNotEmpty;

  /// Accepts a base ending in `/v1`, or a full endpoint pasted in by mistake.
  String get chatCompletionsUrl {
    var base = baseUrl.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    if (base.endsWith('/chat/completions')) return base;
    return '$base/chat/completions';
  }

  @override
  String toString() => 'AiConfig($chatCompletionsUrl, model: $model)';
}
