// Local dictionary backend.
//
// Serves MDict (.mdx / .mdd) archives over HTTP so the Flutter web client can
// search, look up, and play pronunciations that the browser sandbox cannot read
// from disk directly. Reuses the exact same parsers as the desktop/mobile apps
// (package:local_dict/core/mdx/*), so there is a single parsing implementation.
//
// Build: dart pub get
// Run:   dart run server/dict_server.dart [--dir <folder>] [--port 8080] [--host 127.0.0.1]
// Deps:  shelf, shelf_router

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:local_dict/core/mdx/mdd_reader.dart';
import 'package:local_dict/core/mdx/mdx_entry.dart';
import 'package:local_dict/core/mdx/mdx_reader.dart';
import 'package:local_dict/core/models/dictionary_info.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

const Map<String, String> _corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Range',
  'Access-Control-Expose-Headers': 'Content-Range, Content-Length, Accept-Ranges',
};

Future<void> main(List<String> args) async {
  final opts = _Options.parse(args);

  final server = DictServer();
  await server.scan(opts.directories);

  if (server.dictionaries.isEmpty) {
    stdout.writeln(
      'warning: no .mdx archive found in ${opts.directories.join(', ')}',
    );
    stdout.writeln('         pass --dir <folder> or set DICT_DIR to point at one.');
  }

  final handler = const Pipeline()
      .addMiddleware(_corsMiddleware)
      .addMiddleware(_loggingMiddleware)
      .addHandler(server.router.call);

  final httpServer = await shelf_io.serve(handler, opts.host, opts.port);
  httpServer.autoCompress = false;

  stdout.writeln('local dictionary backend listening on '
      'http://${httpServer.address.host}:${httpServer.port}');
  stdout.writeln('dictionaries: ${server.dictionaries.length}');
  for (final d in server.dictionaries) {
    stdout.writeln(
        '  - ${d.info.name}  (${d.info.entryCount} entries, '
        'audio: ${d.mdd != null ? "yes" : "no"})');
  }
  stdout.writeln('api base: http://${opts.host}:${httpServer.port}');
}

class _Options {
  final List<String> directories;
  final String host;
  final int port;

  _Options(this.directories, this.host, this.port);

  static _Options parse(List<String> args) {
    String? dir;
    String host = Platform.environment['DICT_HOST'] ?? '127.0.0.1';
    int port = int.tryParse(Platform.environment['DICT_PORT'] ?? '') ?? 8080;

    for (var i = 0; i < args.length; i++) {
      switch (args[i]) {
        case '--dir':
        case '-d':
          if (i + 1 < args.length) dir = args[++i];
          break;
        case '--host':
          if (i + 1 < args.length) host = args[++i];
          break;
        case '--port':
        case '-p':
          if (i + 1 < args.length) port = int.tryParse(args[++i]) ?? port;
          break;
      }
    }

    final envDir = Platform.environment['DICT_DIR'];
    final dirs = <String>[
      ?dir,
      if (envDir != null) ...envDir.split(';'),
      if (dir == null && envDir == null) ..._defaultSearchRoots(),
    ];

    return _Options(
      dirs.map((d) => d.trim()).where((d) => d.isNotEmpty).toList(),
      host,
      port,
    );
  }

  static List<String> _defaultSearchRoots() => const [
        'Dictionary.com 20260913_hahaya',
        '.',
      ];
}

/// A dictionary loaded from disk, together with its optional audio archive.
class LoadedDict {
  final DictionaryInfo info;
  final MdxReader mdx;
  final MddReader? mdd;

  LoadedDict({required this.info, required this.mdx, this.mdd});

  void close() {
    mdx.close();
    mdd?.close();
  }
}

class DictServer {
  final List<LoadedDict> dictionaries = [];
  final Router router = Router();

  DictServer() {
    router.get('/api/health', _health);
    router.get('/api/dictionaries', _listDictionaries);
    router.post('/api/dictionaries/<id>/enabled', _setEnabled);
    router.get('/api/search', _search);
    router.get('/api/lookup', _lookup);
    router.get('/api/audio', _audio);
    router.get('/', _index);
    router.all('/<ignored|.*>', _notFound);
  }

  // ---------------------------------------------------------------- loading

  /// Scans [directories] recursively for `.mdx` archives.
  Future<void> scan(List<String> directories) async {
    final seenPaths = <String>{};

    for (final dirPath in directories) {
      final dir = Directory(dirPath);
      if (!dir.existsSync()) continue;

      final mdxFiles = dir
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.mdx'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

      for (final file in mdxFiles) {
        final abs = file.absolute.path;
        if (!seenPaths.add(abs)) continue;
        final loaded = await _load(abs);
        if (loaded != null) dictionaries.add(loaded);
      }
    }

    dictionaries.sort((a, b) => a.info.priority.compareTo(b.info.priority));
  }

  Future<LoadedDict?> _load(String mdxPath) async {
    try {
      final mdx = await MdxReader.open(mdxPath);
      final file = File(mdxPath);
      final dir = file.parent.path;
      final baseName = _baseName(mdxPath);

      MddReader? mdd;
      final mddCandidate = File('$dir${Platform.pathSeparator}$baseName.mdd');
      if (mddCandidate.existsSync()) {
        try {
          mdd = await MddReader.open(mddCandidate.absolute.path);
        } catch (e) {
          stderr.writeln('warning: failed to open $mddCandidate: $e');
        }
      }

      final info = DictionaryInfo(
        id: _slug(baseName),
        name: _titleFromHeader(mdx.headerText) ?? baseName,
        mdxPath: file.absolute.path,
        mddPath: mdd == null ? null : mddCandidate.absolute.path,
        cssPath: _findCss(dir, baseName),
        isEnabled: true,
        priority: dictionaries.length,
        entryCount: mdx.numEntries,
        createdAt: file.statSync().modified,
      );

      return LoadedDict(info: info, mdx: mdx, mdd: mdd);
    } catch (e) {
      stderr.writeln('warning: failed to load $mdxPath: $e');
      return null;
    }
  }

  static String _baseName(String path) {
    final name = path.split(RegExp(r'[/\\]')).last;
    final dot = name.lastIndexOf('.');
    return dot == -1 ? name : name.substring(0, dot);
  }

  static String? _titleFromHeader(String header) {
    final m = RegExp(r'Title="([^"]*)"').firstMatch(header);
    final title = m?.group(1)?.trim();
    return (title == null || title.isEmpty) ? null : title;
  }

  static String? _findCss(String dir, String baseName) {
    final exact = File('$dir${Platform.pathSeparator}$baseName.css');
    if (exact.existsSync()) return exact.absolute.path;
    final candidates = Directory(dir)
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.css'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    return candidates.isEmpty ? null : candidates.first.absolute.path;
  }

  static String _slug(String value) {
    final slug = value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return slug.isEmpty ? 'dictionary' : slug;
  }

  List<LoadedDict> get _enabled =>
      dictionaries.where((d) => d.info.isEnabled).toList();

  // -------------------------------------------------------------- handlers

  Response _index(Request req) => _json({
        'name': 'local-dict-backend',
        'endpoints': [
          'GET /api/health',
          'GET /api/dictionaries',
          'POST /api/dictionaries/<id>/enabled',
          'GET /api/search?q=&limit=',
          'GET /api/lookup?word=',
          'GET /api/audio?key=',
        ],
      });

  Response _notFound(Request req) =>
      _json({'error': 'not found', 'path': req.url.path}, status: 404);

  Response _health(Request req) => _json({
        'status': 'ok',
        'dictionaries': dictionaries.length,
        'enabled': _enabled.length,
        'totalEntries':
            dictionaries.fold<int>(0, (sum, d) => sum + d.info.entryCount),
        'uptimeSeconds': _startedAt.elapsed.inSeconds,
      });

  Response _listDictionaries(Request req) => _json({
        'dictionaries': dictionaries.map((d) => d.info.toMap()).toList(),
      });

  Future<Response> _setEnabled(Request req, String id) async {
    final loaded = dictionaries.where((d) => d.info.id == id).firstOrNull;
    if (loaded == null) {
      return _json({'error': 'unknown dictionary', 'id': id}, status: 404);
    }
    bool enabled = true;
    try {
      final body = await req.readAsString();
      if (body.isNotEmpty) {
        final decoded = json.decode(body);
        if (decoded is Map && decoded['enabled'] is bool) {
          enabled = decoded['enabled'] as bool;
        }
      }
    } catch (_) {
      return _json({'error': 'invalid JSON body'}, status: 400);
    }

    final index = dictionaries.indexWhere((d) => d.info.id == id);
    dictionaries[index] = LoadedDict(
      info: loaded.info.copyWith(isEnabled: enabled),
      mdx: loaded.mdx,
      mdd: loaded.mdd,
    );
    return _json({'id': id, 'isEnabled': enabled});
  }

  Response _search(Request req) {
    final query = (req.url.queryParameters['q'] ?? '').trim();
    final limit =
        int.tryParse(req.url.queryParameters['limit'] ?? '')?.clamp(1, 500) ?? 60;

    if (query.isEmpty) {
      return _json({'query': query, 'results': const []});
    }

    final lower = query.toLowerCase();
    final results = <Map<String, dynamic>>[];
    final seen = <String>{};

    void add(LoadedDict dict, String word, String matchType) {
      final key = word.toLowerCase();
      if (!seen.add(key)) return;
      results.add({
        'word': word,
        'matchType': matchType,
        'dictionaryId': dict.info.id,
        'dictionaryName': dict.info.name,
      });
    }

    final enabled = _enabled;

    // 1. Exact matches (an entry actually exists for the query).
    for (final dict in enabled) {
      if (dict.mdx.getEntry(lower) != null) {
        add(dict, lower, 'exact');
      }
    }

    // 2. Prefix matches.
    for (final dict in enabled) {
      for (final word in dict.mdx.search(lower, limit: limit, prefixOnly: true)) {
        if (results.length >= limit) return _json({'query': query, 'results': results});
        add(dict, word, 'prefix');
      }
    }

    // 3. Substring (infix) matches.
    if (results.length < limit) {
      for (final dict in enabled) {
        for (final word in dict.mdx.search(lower, limit: limit, prefixOnly: false)) {
          if (results.length >= limit) return _json({'query': query, 'results': results});
          add(dict, word, 'substring');
        }
      }
    }

    return _json({'query': query, 'results': results});
  }

  Response _lookup(Request req) {
    final word = (req.url.queryParameters['word'] ?? '').trim();
    if (word.isEmpty) {
      return _json({'error': 'missing ?word='}, status: 400);
    }

    for (final dict in _enabled) {
      final html = dict.mdx.getEntry(word);
      if (html != null) {
        final entry = MdxEntry.parse(word, html);
        return _json({
          'found': true,
          'query': word,
          'dictionaryId': dict.info.id,
          'dictionaryName': dict.info.name,
          'entry': entry.toJson(),
        });
      }
    }

    return _json({'found': false, 'query': word, 'entry': null});
  }

  Future<Response> _audio(Request req) async {
    final key = (req.url.queryParameters['key'] ?? '').trim();
    if (key.isEmpty) {
      return _json({'error': 'missing ?key='}, status: 400);
    }

    for (final dict in _enabled) {
      final mdd = dict.mdd;
      if (mdd == null) continue;
      final bytes = mdd.getResource(key);
      if (bytes != null && bytes.isNotEmpty) {
        return _bytes(bytes, req, 'audio/mpeg');
      }
    }
    return _json({'error': 'audio not found', 'key': key}, status: 404);
  }

  // --------------------------------------------------------------- helpers

  static final Stopwatch _startedAt = Stopwatch()..start();

  static Response _json(Object payload, {int status = 200}) => Response(
        status,
        body: json.encode(payload),
        headers: {
          HttpHeaders.contentTypeHeader: 'application/json; charset=utf-8',
          ..._corsHeaders,
        },
      );

  /// Serves [data] honouring a single-range `Range` request.
  static Response _bytes(Uint8List data, Request req, String contentType) {
    final total = data.length;
    final rangeHeader = req.headers[HttpHeaders.rangeHeader];

    if (rangeHeader == null || rangeHeader.isEmpty) {
      return Response.ok(
        data,
        headers: {
          HttpHeaders.contentTypeHeader: contentType,
          HttpHeaders.contentLengthHeader: '$total',
          HttpHeaders.acceptRangesHeader: 'bytes',
          ..._corsHeaders,
        },
      );
    }

    final match = RegExp(r'bytes=(\d*)-(\d*)').firstMatch(rangeHeader);
    if (match == null) return _json({'error': 'invalid range'}, status: 416);

    final startRaw = match.group(1) ?? '';
    final endRaw = match.group(2) ?? '';
    int start;
    int end;

    if (startRaw.isEmpty) {
      // Suffix range: last N bytes.
      final suffix = int.tryParse(endRaw) ?? 0;
      if (suffix <= 0) return _json({'error': 'invalid range'}, status: 416);
      start = (total - suffix).clamp(0, total - 1);
      end = total - 1;
    } else {
      start = int.parse(startRaw);
      end = endRaw.isEmpty ? total - 1 : int.parse(endRaw);
    }

    if (start >= total || start > end) {
      return Response(416, headers: {
        HttpHeaders.contentRangeHeader: 'bytes */$total',
        ..._corsHeaders,
      });
    }
    end = end.clamp(start, total - 1);

    final slice = Uint8List.sublistView(data, start, end + 1);
    return Response(206, body: slice, headers: {
      HttpHeaders.contentTypeHeader: contentType,
      HttpHeaders.contentRangeHeader: 'bytes $start-$end/$total',
      HttpHeaders.contentLengthHeader: '${end - start + 1}',
      HttpHeaders.acceptRangesHeader: 'bytes',
      ..._corsHeaders,
    });
  }
}

Handler _corsMiddleware(Handler inner) {
  return (Request req) async {
    if (req.method == 'OPTIONS') {
      return Response.ok('', headers: _corsHeaders);
    }
    final res = await inner(req);
    return res.change(headers: {...res.headers, ..._corsHeaders});
  };
}

Handler _loggingMiddleware(Handler inner) {
  return (Request req) async {
    final sw = Stopwatch()..start();
    final res = await inner(req);
    stdout.writeln(
      '${res.statusCode} ${req.method} /${req.url.path}'
      '${req.url.query.isEmpty ? '' : '?${req.url.query}'} '
      '(${sw.elapsedMilliseconds}ms)',
    );
    return res;
  };
}
