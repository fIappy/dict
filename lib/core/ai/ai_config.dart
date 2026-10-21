/// How hard the model should think before answering.
///
/// `low` is the default: these are short teaching texts, and a model that
/// deliberates for thirty seconds to write five example sentences makes the
/// page feel broken. Servers that do not know the parameter are retried
/// without it, so this never becomes a hard requirement.
enum AiReasoningEffort { none, minimal, low, medium, high }

extension AiReasoningEffortLabel on AiReasoningEffort {
  String get label => switch (this) {
        AiReasoningEffort.none => '关',
        AiReasoningEffort.minimal => '最低',
        AiReasoningEffort.low => '低',
        AiReasoningEffort.medium => '中',
        AiReasoningEffort.high => '高',
      };
}

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
    this.reasoningEffort = AiReasoningEffort.low,
  });

  static const String defaultBaseUrl = 'https://api.openai.com/v1';
  static const String defaultModel = 'gpt-4o-mini';

  /// Base URL as the reader typed it, e.g. `http://127.0.0.1:11434/v1`.
  final String baseUrl;

  /// Bearer token. A local runtime usually ignores it, so an empty key is only
  /// refused by servers that actually require one.
  final String apiKey;

  final String model;

  final AiReasoningEffort reasoningEffort;

  bool get isConfigured => baseUrl.trim().isNotEmpty && model.trim().isNotEmpty;

  /// The base the client library gets: trailing slashes dropped, and a full
  /// `/chat/completions` endpoint (pasted in by mistake) reduced to its base,
  /// because the library appends the path itself.
  String get apiBaseUrl {
    var base = baseUrl.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    const suffix = '/chat/completions';
    if (base.endsWith(suffix)) {
      base = base.substring(0, base.length - suffix.length);
    }
    return base;
  }

  /// For display and for the tests that pin the normalisation.
  String get chatCompletionsUrl => '$apiBaseUrl/chat/completions';

  @override
  String toString() => 'AiConfig($chatCompletionsUrl, model: $model)';
}
