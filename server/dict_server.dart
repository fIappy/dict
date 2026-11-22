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

import 'package:local_dict/core/audio/disk_word_audio_cache.dart';
import 'package:local_dict/core/audio/online_word_audio.dart';
import 'package:local_dict/core/lexicon/coca_sqlite_store.dart';
import 'package:local_dict/core/mdx/mdd_reader.dart';
import 'package:local_dict/core/mdx/mdx_entry.dart';
import 'package:local_dict/core/mdx/mdx_reader.dart';
import 'package:local_dict/core/models/dictionary_info.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const Map<String, String> _baseCorsHeaders = {
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Range, Authorization',
  'Access-Control-Expose-Headers': 'Content-Range, Content-Length, Accept-Ranges',
};

Map<String, String> _corsHeadersFor(Request req) {
  final configured = Platform.environment['DICT_CORS_ORIGIN']?.trim();
  final origin = req.headers['origin']?.trim();
  String? allowOrigin;
  if (configured != null && configured.isNotEmpty) {
    if (configured == '*') {
      allowOrigin = '*';
    } else if (origin != null &&
        configured.split(',').map((s) => s.trim()).contains(origin)) {
      allowOrigin = origin;
    }
  } else if (origin != null && _isLoopbackOrigin(origin)) {
    // Allow local dev servers (e.g. `flutter run -d chrome`) without opening *
    // to arbitrary remote sites.
    allowOrigin = origin;
  }
  if (allowOrigin == null) return const {};
  return {
    ..._baseCorsHeaders,
    'Access-Control-Allow-Origin': allowOrigin,
    if (allowOrigin != '*') 'Vary': 'Origin',
  };
}

bool _isLoopbackOrigin(String origin) {
  final uri = Uri.tryParse(origin);
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
    return false;
  }
  return uri.host == 'localhost' ||
      uri.host == '127.0.0.1' ||
      uri.host == '[::1]' ||
      uri.host == '::1';
}

Future<void> main(List<String> args) async {
  final opts = _Options.parse(args);

  final server = DictServer();
  await server.openLexicon(opts.lexiconPath);
  server.configureWordAudioCache();
  await server.scan(opts.directories);

  if (!server.hasLexicon && server.dictionaries.isEmpty) {
    stdout.writeln(
      'warning: no coca_learn.db or .mdx archive found in ${opts.directories.join(', ')}',
    );
    stdout.writeln('         pass --lexicon <db> / --dir <folder> or set COCA_DB_PATH / DICT_DIR.');
  }

  final handler = const Pipeline()
      .addMiddleware(_corsMiddleware)
      .addMiddleware(_loggingMiddleware)
      .addHandler(server.router.call);

  final httpServer = await shelf_io.serve(handler, opts.host, opts.port);
  httpServer.autoCompress = false;

  stdout.writeln('local dictionary backend listening on '
      'http://${httpServer.address.host}:${httpServer.port}');
  if (server.hasLexicon) {
    stdout.writeln('lexicon: ${server.lexiconEntries} entries (${server.lexiconPath})');
  }
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
  final String? lexiconPath;
  final String host;
  final int port;

  _Options(this.directories, this.lexiconPath, this.host, this.port);

  static _Options parse(List<String> args) {
    String? dir;
    String? lexicon;
    String host = Platform.environment['DICT_HOST'] ?? '127.0.0.1';
    int port = int.tryParse(Platform.environment['DICT_PORT'] ?? '') ?? 8080;

    for (var i = 0; i < args.length; i++) {
      switch (args[i]) {
        case '--dir':
        case '-d':
          if (i + 1 < args.length) dir = args[++i];
          break;
        case '--lexicon':
        case '-l':
          if (i + 1 < args.length) lexicon = args[++i];
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
      lexicon ?? Platform.environment['COCA_DB_PATH'],
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
  final List<LoadedDict> _dicts = [];
  final Router router = Router();
  Future<void> _mutationQueue = Future<void>.value();

  CocaSqliteStore? _lexicon;
  String? _lexiconPath;
  int _lexiconEntryCount = 0;
  DiskWordAudioCache? _wordAudioCache;

  /// Roots last passed to [scan]; used by `/api/reload`.
  List<String> _roots = const [];

  /// Ids the operator disabled, preserved across reloads.
  final Set<String> _disabled = {};

  List<LoadedDict> get dictionaries => List.unmodifiable(_dicts);
  bool get hasLexicon => _lexicon != null;
  int get lexiconEntries => _lexiconEntryCount;
  String? get lexiconPath => _lexiconPath;

  DictServer() {
    router.get('/api/health', _health);
    router.get('/api/lexicon/info', _lexiconInfo);
    router.get('/api/lexicon/search', _lexiconSearch);
    router.get('/api/lexicon/lookup', _lexiconLookup);
    router.get('/api/word-audio', _wordAudio);
    router.get('/api/dictionaries', _listDictionaries);
    router.post('/api/dictionaries/<id>/enabled', _setEnabled);
    router.post('/api/reload', _reload);
    router.get('/api/search', _search);
    router.get('/api/lookup', _lookup);
    router.get('/api/audio', _audio);
    router.get('/', _index);
    router.all('/<ignored|.*>', _notFound);
  }

  void configureWordAudioCache([Directory? dir]) {
    final target = dir ??
        Directory(
          Platform.environment['WORD_AUDIO_CACHE_DIR'] ??
              p.join(Directory.current.path, '.word_audio_cache'),
        );
    _wordAudioCache = DiskWordAudioCache(target);
  }

  Future<bool> openLexicon([String? explicitPath]) => _serialized(() async {
        final candidates = <String>[
          if (explicitPath != null && explicitPath.trim().isNotEmpty)
            explicitPath.trim(),
          if ((Platform.environment['COCA_DB_PATH'] ?? '').trim().isNotEmpty)
            Platform.environment['COCA_DB_PATH']!.trim(),
          p.join(Directory.current.path, 'content', 'coca-ai', 'pack', 'coca_learn.db'),
          p.join(Directory.current.path, 'coca_learn.db'),
          '/app/data/coca_learn.db',
        ];
        String? resolved;
        for (final c in candidates) {
          final f = File(c);
          if (f.existsSync() && f.lengthSync() > 0) {
            resolved = f.absolute.path;
            break;
          }
        }
        if (resolved == null) return false;

        sqfliteFfiInit();
        final db = await databaseFactoryFfi.openDatabase(
          resolved,
          options: OpenDatabaseOptions(readOnly: true),
        );
        final store = CocaSqliteStore(db);
        final count = await store.countEntries();
        final prev = _lexicon;
        _lexicon = store;
        _lexiconPath = resolved;
        _lexiconEntryCount = count;
        if (prev != null) {
          try {
            await prev.close();
          } catch (_) {}
        }
        return true;
      });

  Future<void> close() async {
    await scan(const []);
    final prev = _lexicon;
    _lexicon = null;
    _lexiconPath = null;
    _lexiconEntryCount = 0;
    if (prev != null) {
      await prev.close();
    }
  }

  Future<T> _serialized<T>(Future<T> Function() action) {
    final prev = _mutationQueue;
    final completer = Completer<T>();
    final next = prev.catchError((_) {}).then((_) async {
      try {
        completer.complete(await action());
      } catch (e, s) {
        completer.completeError(e, s);
      }
    });
    _mutationQueue = next;
    return completer.future;
  }

  // ---------------------------------------------------------------- loading

  /// Scans [directories] recursively for `.mdx` archives and swaps them in.
  ///
  /// Archives can be added or removed on the mounted volume at any time; call
  /// this again (or hit `POST /api/reload`) to pick the change up without
  /// restarting the container.
  Future<void> scan(List<String> directories) => _serialized(() async {
        _roots = List.unmodifiable(directories);

        final loaded = <LoadedDict>[];
        final seenPaths = <String>{};
        final usedIds = <String>{};

        for (final dirPath in _roots) {
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
            final entry = await _load(abs, priority: loaded.length, usedIds: usedIds);
            if (entry != null) loaded.add(entry);
          }
        }

        loaded.sort((a, b) => a.info.priority.compareTo(b.info.priority));

        // Swap under a single synchronous section, then release the old handles.
        final previous = List<LoadedDict>.of(_dicts);
        _dicts
          ..clear()
          ..addAll(loaded.map(
            (d) => _disabled.contains(d.info.id)
                ? LoadedDict(
                    info: d.info.copyWith(isEnabled: false),
                    mdx: d.mdx,
                    mdd: d.mdd,
                  )
                : d,
          ));

        // Readers were re-opened, so every previous handle can be released.
        for (final old in previous) {
          try {
            old.close();
          } catch (_) {
            // Already gone; nothing to do.
          }
        }
      });

  Future<LoadedDict?> _load(
    String mdxPath, {
    required int priority,
    required Set<String> usedIds,
  }) async {
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

      var id = _slug(baseName, uniqueSeed: file.absolute.path);
      if (!usedIds.add(id)) {
        var suffix = 2;
        while (!usedIds.add('$id-$suffix')) {
          suffix++;
        }
        id = '$id-$suffix';
      }

      final info = DictionaryInfo(
        id: id,
        name: _titleFromHeader(mdx.headerText) ?? baseName,
        mdxPath: file.absolute.path,
        mddPath: mdd == null ? null : mddCandidate.absolute.path,
        cssPath: _findCss(dir, baseName),
        isEnabled: true,
        priority: priority,
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
    final name = _fileName(path);
    final dot = name.lastIndexOf('.');
    return dot == -1 ? name : name.substring(0, dot);
  }

  static String _fileName(String path) => path.split(RegExp(r'[/\\]')).last;

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

  static String _slug(String value, {required String uniqueSeed}) {
    final slug = value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (slug.isNotEmpty) return slug;
    var hash = 0x811c9dc5;
    for (final unit in uniqueSeed.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return 'dictionary-${hash.toRadixString(16).padLeft(8, '0')}';
  }

  List<LoadedDict> get _enabled =>
      _dicts.where((d) => d.info.isEnabled).toList();

  // -------------------------------------------------------------- handlers

  Response _index(Request req) => _json({
        'name': 'local-dict-backend',
        'endpoints': [
          'GET /api/health',
          'GET /api/lexicon/info',
          'GET /api/lexicon/search?q=&limit=',
          'GET /api/lexicon/lookup?word=',
          'GET /api/word-audio?word=&accent=',
          'GET /api/dictionaries',
          'POST /api/dictionaries/<id>/enabled',
          'POST /api/reload',
          'GET /api/search?q=&limit=',
          'GET /api/lookup?word=',
          'GET /api/audio?key=',
        ],
      });

  Response _notFound(Request req) =>
      _json({'error': 'not found', 'path': req.url.path}, status: 404);

  Response _health(Request req) => _json({
        'status': 'ok',
        'lexiconReady': _lexicon != null,
        'lexiconEntries': _lexiconEntryCount,
        'dictionaries': dictionaries.length,
        'enabled': _enabled.length,
        'totalEntries':
            dictionaries.fold<int>(0, (sum, d) => sum + d.info.entryCount),
        'uptimeSeconds': _startedAt.elapsed.inSeconds,
      });

  Response _lexiconInfo(Request req) => _json({
        'ready': _lexicon != null,
        'entryCount': _lexiconEntryCount,
        'name': CocaSqliteStore.libraryName,
      });

  Future<Response> _lexiconSearch(Request req) async {
    final store = _lexicon;
    if (store == null) {
      return _json({'error': 'lexicon not loaded'}, status: 503);
    }
    final query = (req.url.queryParameters['q'] ?? '').trim();
    final limit =
        int.tryParse(req.url.queryParameters['limit'] ?? '')?.clamp(1, 200) ?? 60;
    if (query.isEmpty) {
      return _json({'query': query, 'results': const []});
    }
    final hits = await store.search(query, limit: limit);
    return _json({
      'query': query,
      'results': [
        for (final r in hits)
          {
            'word': r.word,
            'matchType': r.matchType.name,
            'dictionaryId': r.dictionaryId,
            'dictionaryName': r.dictionaryName,
            if (r.briefDefinition != null) 'briefDefinition': r.briefDefinition,
            if (r.frequencyBadge != null) 'frequencyBadge': r.frequencyBadge,
          },
      ],
    });
  }

  Future<Response> _lexiconLookup(Request req) async {
    final store = _lexicon;
    if (store == null) {
      return _json({'error': 'lexicon not loaded'}, status: 503);
    }
    final word = (req.url.queryParameters['word'] ?? '').trim();
    if (word.isEmpty) {
      return _json({'error': 'missing ?word='}, status: 400);
    }
    final entry = await store.lookup(word);
    return _json({
      'found': entry != null,
      'query': word,
      'entry': entry?.toJson(),
    });
  }

  Future<Response> _wordAudio(Request req) async {
    final word = (req.url.queryParameters['word'] ?? '').trim();
    if (word.isEmpty) {
      return _json({'error': 'missing ?word='}, status: 400);
    }
    final accent = normalizeWordCacheAccent(req.url.queryParameters['accent'] ?? 'us');
    final cache = _wordAudioCache;
    if (cache != null) {
      final cachedPath = await cache.getPath(word, accent);
      if (cachedPath != null) {
        final bytes = await File(cachedPath).readAsBytes();
        return _bytes(bytes, req, 'audio/mpeg');
      }
    }
    final bytes = await fetchOnlineWordAudio(word, accent: accent);
    if (bytes == null || bytes.isEmpty) {
      return _json({'error': 'word audio unavailable', 'word': word}, status: 404);
    }
    if (cache != null) {
      await cache.put(word, accent, bytes);
    }
    return _bytes(bytes, req, 'audio/mpeg');
  }

  Map<String, dynamic> _publicDictionaryMap(DictionaryInfo info) {
    final map = info.toMap();
    map['mdx_path'] = _fileName(info.mdxPath);
    map['mdd_path'] = info.mddPath == null ? null : _fileName(info.mddPath!);
    map['css_path'] = info.cssPath == null ? null : _fileName(info.cssPath!);
    return map;
  }

  Response _listDictionaries(Request req) => _json({
        'dictionaries':
            dictionaries.map((d) => _publicDictionaryMap(d.info)).toList(),
      });

  bool _isAuthorizedAdmin(Request req) {
    final token = Platform.environment['DICT_ADMIN_TOKEN']?.trim() ?? '';
    if (token.isNotEmpty) {
      final auth = req.headers[HttpHeaders.authorizationHeader]?.trim() ?? '';
      return auth == 'Bearer $token';
    }
    final forwarded = req.headers['x-forwarded-for'] ?? req.headers['x-real-ip'];
    if (forwarded != null && forwarded.trim().isNotEmpty) return false;
    final info = req.context['shelf.io.connection_info'] as HttpConnectionInfo?;
    return info?.remoteAddress.isLoopback ?? false;
  }

  Future<String?> _readLimitedBody(Request req, {int maxBytes = 8192}) async {
    final contentLen = int.tryParse(req.headers[HttpHeaders.contentLengthHeader] ?? '');
    if (contentLen != null && contentLen > maxBytes) return null;
    final builder = BytesBuilder(copy: false);
    await for (final chunk in req.read()) {
      if (builder.length + chunk.length > maxBytes) return null;
      builder.add(chunk);
    }
    return utf8.decode(builder.takeBytes(), allowMalformed: false);
  }

  /// Re-scans the mounted volume so archives can be added or removed without
  /// restarting the container. Readers are re-opened; in-flight requests during
  /// the swap may fail transiently and are safe to retry.
  Future<Response> _reload(Request req) async {
    if (!_isAuthorizedAdmin(req)) {
      return _json({'error': 'forbidden'}, status: 403);
    }
    await scan(_roots);
    return _json({
      'status': 'ok',
      'dictionaries': _dicts.length,
      'enabled': _enabled.length,
      'totalEntries': _dicts.fold<int>(0, (sum, d) => sum + d.info.entryCount),
      'ids': _dicts.map((d) => d.info.id).toList(),
    });
  }

  Future<Response> _setEnabled(Request req, String id) async {
    if (!_isAuthorizedAdmin(req)) {
      return _json({'error': 'forbidden'}, status: 403);
    }
    String? body;
    try {
      body = await _readLimitedBody(req);
    } catch (_) {
      return _json({'error': 'invalid request body'}, status: 400);
    }
    if (body == null) {
      return Response(
        413,
        body: json.encode({'error': 'request body too large'}),
        headers: {
          HttpHeaders.contentTypeHeader: 'application/json; charset=utf-8',
          HttpHeaders.connectionHeader: 'close',
        },
      );
    }

    bool enabled = true;
    try {
      if (body.isNotEmpty) {
        final decoded = json.decode(body);
        if (decoded is! Map || decoded['enabled'] is! bool) {
          return _json({'error': 'invalid JSON body'}, status: 400);
        }
        enabled = decoded['enabled'] as bool;
      }
    } catch (_) {
      return _json({'error': 'invalid JSON body'}, status: 400);
    }

    return _serialized(() async {
      // Re-resolve index after awaiting the request body so a concurrent reload
      // cannot trick us into writing a closed handle back into `_dicts`.
      final index = _dicts.indexWhere((d) => d.info.id == id);
      if (index == -1) {
        return _json({'error': 'unknown dictionary', 'id': id}, status: 404);
      }

      if (enabled) {
        _disabled.remove(id);
      } else {
        _disabled.add(id);
      }

      final current = _dicts[index];
      _dicts[index] = LoadedDict(
        info: current.info.copyWith(isEnabled: enabled),
        mdx: current.mdx,
        mdd: current.mdd,
      );
      return _json({'id': id, 'isEnabled': enabled});
    });
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

    // 1. Exact matches.
    for (final dict in enabled) {
      if (dict.mdx.containsKey(lower)) {
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
        final remaining = limit - results.length;
        for (final word in dict.mdx.searchInfix(
          lower,
          limit: remaining,
          excludeLower: seen,
        )) {
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
        },
      );
    }

    if (total == 0) {
      return Response(416, headers: {
        HttpHeaders.contentRangeHeader: 'bytes */0',
      });
    }

    final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(rangeHeader.trim());
    if (match == null) return _json({'error': 'invalid range'}, status: 416);

    final startRaw = match.group(1) ?? '';
    final endRaw = match.group(2) ?? '';
    if (startRaw.isEmpty && endRaw.isEmpty) {
      return _json({'error': 'invalid range'}, status: 416);
    }
    int start;
    int end;

    if (startRaw.isEmpty) {
      // Suffix range: last N bytes.
      final suffix = int.tryParse(endRaw);
      if (suffix == null || suffix <= 0) {
        return _json({'error': 'invalid range'}, status: 416);
      }
      start = (total - suffix).clamp(0, total - 1);
      end = total - 1;
    } else {
      final parsedStart = int.tryParse(startRaw);
      final parsedEnd = endRaw.isEmpty ? total - 1 : int.tryParse(endRaw);
      if (parsedStart == null || parsedEnd == null) {
        return _json({'error': 'invalid range'}, status: 416);
      }
      start = parsedStart;
      end = parsedEnd;
    }

    if (start < 0 || start >= total || start > end) {
      return Response(416, headers: {
        HttpHeaders.contentRangeHeader: 'bytes */$total',
      });
    }
    end = end.clamp(start, total - 1);

    final slice = Uint8List.sublistView(data, start, end + 1);
    return Response(206, body: slice, headers: {
      HttpHeaders.contentTypeHeader: contentType,
      HttpHeaders.contentRangeHeader: 'bytes $start-$end/$total',
      HttpHeaders.contentLengthHeader: '${end - start + 1}',
      HttpHeaders.acceptRangesHeader: 'bytes',
    });
  }
}

Handler _corsMiddleware(Handler inner) {
  return (Request req) async {
    final cors = _corsHeadersFor(req);
    if (req.method == 'OPTIONS') {
      return Response.ok('', headers: cors);
    }
    final res = await inner(req);
    return cors.isEmpty ? res : res.change(headers: {...res.headers, ...cors});
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
