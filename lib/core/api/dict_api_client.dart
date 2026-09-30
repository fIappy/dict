import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../mdx/mdx_entry.dart';
import '../models/dictionary_info.dart';
import 'api_config.dart';

/// Result row of `/api/search`.
class ApiSearchHit {
  final String word;
  final String matchType;
  final String dictionaryId;
  final String dictionaryName;

  const ApiSearchHit({
    required this.word,
    required this.matchType,
    required this.dictionaryId,
    required this.dictionaryName,
  });

  factory ApiSearchHit.fromJson(Map<String, dynamic> json) => ApiSearchHit(
        word: json['word'] as String? ?? '',
        matchType: json['matchType'] as String? ?? 'substring',
        dictionaryId: json['dictionaryId'] as String? ?? '',
        dictionaryName: json['dictionaryName'] as String? ?? '',
      );
}

class DictApiException implements Exception {
  final String message;
  const DictApiException(this.message);

  @override
  String toString() => message;
}

/// Thin HTTP client for the local dictionary backend.
class DictApiClient {
  DictApiClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const Duration _timeout = Duration(seconds: 8);

  Future<bool> health() async {
    try {
      final res =
          await _client.get(ApiConfig.endpoint('/api/health')).timeout(_timeout);
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<List<DictionaryInfo>> dictionaries() async {
    final res = await _client
        .get(ApiConfig.endpoint('/api/dictionaries'))
        .timeout(_timeout);
    if (res.statusCode != 200) {
      throw DictApiException('后端返回 ${res.statusCode}');
    }
    final body = _decode(res);
    final list = (body['dictionaries'] as List?) ?? const [];
    return list
        .whereType<Map>()
        .map((e) => DictionaryInfo.fromMap(_stringKeyed(e)))
        .toList();
  }

  Future<void> setDictionaryEnabled(String id, bool enabled) async {
    await _client
        .post(
          ApiConfig.endpoint('/api/dictionaries/$id/enabled'),
          headers: const {'Content-Type': 'application/json'},
          body: json.encode({'enabled': enabled}),
        )
        .timeout(_timeout);
  }

  Future<List<ApiSearchHit>> search(String query, {int limit = 60}) async {
    final res = await _client
        .get(ApiConfig.endpoint('/api/search', {'q': query, 'limit': '$limit'}))
        .timeout(_timeout);
    if (res.statusCode != 200) {
      throw DictApiException('后端返回 ${res.statusCode}');
    }
    final body = _decode(res);
    final list = (body['results'] as List?) ?? const [];
    return list
        .whereType<Map>()
        .map((e) => ApiSearchHit.fromJson(_stringKeyed(e)))
        .toList();
  }

  Future<MdxEntry?> lookup(String word) async {
    final res = await _client
        .get(ApiConfig.endpoint('/api/lookup', {'word': word}))
        .timeout(_timeout);
    if (res.statusCode != 200) {
      throw DictApiException('后端返回 ${res.statusCode}');
    }
    final body = _decode(res);
    if (body['found'] != true) return null;
    final entry = body['entry'];
    if (entry is! Map) return null;
    return MdxEntry.fromJson(_stringKeyed(entry));
  }

  /// Raw pronunciation bytes read from the server-side `.mdd` archive.
  Future<Uint8List?> audioBytes(String soundKey) async {
    final res = await _client
        .get(ApiConfig.endpoint('/api/audio', {'key': soundKey}))
        .timeout(_timeout);
    if (res.statusCode != 200 || res.bodyBytes.isEmpty) return null;
    return res.bodyBytes;
  }

  Map<String, dynamic> _decode(http.Response res) {
    final decoded = json.decode(utf8.decode(res.bodyBytes));
    if (decoded is! Map) {
      throw const DictApiException('后端返回了非预期的响应体');
    }
    return _stringKeyed(decoded);
  }

  static Map<String, dynamic> _stringKeyed(Map raw) =>
      raw.map((k, v) => MapEntry(k.toString(), v));
}
