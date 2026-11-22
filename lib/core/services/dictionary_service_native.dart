import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../database/dictionaries_dao.dart';
import '../frequency/frequency_service.dart';
import '../mdx/mdd_reader.dart';
import '../mdx/mdx_entry.dart';
import '../mdx/mdx_reader.dart';
import '../models/dictionary_info.dart';
import '../models/search_result.dart';

/// Whether an archive at [path] must be copied into app storage before being
/// registered as a dictionary.
///
/// Android's Storage Access Framework hands back a copy of each picked file
/// under `cacheDir/file_picker/<timestamp>/`: the OS may evict it, and it never
/// contains the sibling `.mdd`, so a dictionary imported from it would lose its
/// audio and eventually its text. Desktop paths are the user's own files, so
/// they are referenced in place — copying a multi-gigabyte `.mdd` would be
/// wasteful and slow.
@visibleForTesting
bool requiresDurableImport({
  required bool isAndroid,
  required String path,
  required String? appDictDir,
}) {
  if (!isAndroid) return false;
  if (appDictDir != null && p.isWithin(appDictDir, path)) return false;
  return true;
}

class _WorkerHandle {
  DictionaryInfo info;
  final MdxReader mdx;
  final MddReader? mdd;

  _WorkerHandle({required this.info, required this.mdx, this.mdd});

  void close() {
    mdx.close();
    mdd?.close();
  }
}

class _DictWorker {
  Isolate? _isolate;
  SendPort? _requests;
  ReceivePort? _replies;
  Completer<SendPort?>? _ready;
  Future<SendPort?>? _starting;
  int _nextId = 1;
  final Map<int, Completer<Object?>> _pending = {};

  Future<SendPort?> _ensureStarted() {
    final existing = _requests;
    if (existing != null) return Future<SendPort?>.value(existing);
    return _starting ??= _spawn().whenComplete(() {
      if (_requests == null) _starting = null;
    });
  }

  Future<SendPort?> _spawn() async {
    final ready = Completer<SendPort?>();
    _ready = ready;
    final replies = ReceivePort();
    _replies = replies;
    replies.listen(_onMessage);
    try {
      _isolate = await Isolate.spawn<SendPort>(
        _dictWorkerMain,
        replies.sendPort,
        onError: replies.sendPort,
        onExit: replies.sendPort,
      );
      final port = await ready.future.timeout(const Duration(seconds: 30));
      _requests = port;
      if (port == null) _teardown();
      return port;
    } catch (e) {
      debugPrint('Dictionary worker failed to start: $e');
      _teardown();
      return null;
    }
  }

  void _teardown() {
    _replies?.close();
    _replies = null;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _requests = null;
    _ready = null;
  }

  void _onMessage(dynamic message) {
    if (message is SendPort) {
      final r = _ready;
      _ready = null;
      if (r != null && !r.isCompleted) r.complete(message);
      return;
    }
    if (message == null || (message is List && message.length == 2 && message[0] is! int)) {
      final r = _ready;
      _ready = null;
      if (r != null && !r.isCompleted) r.complete(null);
      _requests = null;
      for (final c in _pending.values) {
        if (!c.isCompleted) c.complete(null);
      }
      _pending.clear();
      return;
    }
    if (message is List && message.length == 3) {
      final id = message[0] as int;
      final value = message[1];
      final error = message[2] as String?;
      final c = _pending.remove(id);
      if (c == null || c.isCompleted) return;
      if (error != null) {
        debugPrint('Dictionary worker error: $error');
      }
      c.complete(value);
    }
  }

  Future<T?> call<T>(String cmd, [Map<String, Object?> args = const {}]) async {
    final port = await _ensureStarted();
    if (port == null) return null;
    final id = _nextId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    port.send(<Object?>[id, cmd, args]);
    final res = await completer.future;
    return res as T?;
  }

  void dispose() {
    for (final c in _pending.values) {
      if (!c.isCompleted) c.complete(null);
    }
    _pending.clear();
    final port = _requests;
    _requests = null;
    final iso = _isolate;
    _isolate = null;
    _replies?.close();
    _replies = null;
    _starting = null;
    if (port != null) {
      port.send(null);
    } else {
      iso?.kill(priority: Isolate.immediate);
    }
  }
}

void _dictWorkerMain(SendPort parent) {
  final requests = ReceivePort();
  final handles = <String, _WorkerHandle>{};
  final order = <String>[];
  parent.send(requests.sendPort);

  void closeAll() {
    for (final h in handles.values) {
      try {
        h.close();
      } catch (_) {}
    }
    handles.clear();
    order.clear();
  }

  requests.listen((message) async {
    if (message == null) {
      closeAll();
      requests.close();
      return;
    }
    final list = message as List<Object?>;
    final id = list[0] as int;
    final cmd = list[1] as String;
    final args = (list[2] as Map?)?.cast<String, Object?>() ?? const {};
    try {
      switch (cmd) {
        case 'load':
          final dictId = args['id'] as String;
          final dictName = args['name'] as String;
          final mdxPath = args['mdxPath'] as String;
          var mddPath = args['mddPath'] as String?;
          final cssPath = args['cssPath'] as String?;
          final priority = args['priority'] as int;
          final entryCount = args['entryCount'] as int;
          final createdAtMs = args['createdAtMs'] as int;
          final isEnabled = args['isEnabled'] as bool;

          if (!File(mdxPath).existsSync()) {
            parent.send(<Object?>[id, null, 'MDX file missing: $mdxPath']);
            return;
          }
          MdxReader? mdx;
          MddReader? mdd;
          try {
            mdx = await MdxReader.open(mdxPath);
            if (mddPath == null || !File(mddPath).existsSync()) {
              final sibling = p.join(
                p.dirname(mdxPath),
                '${p.basenameWithoutExtension(mdxPath)}.mdd',
              );
              mddPath = File(sibling).existsSync() ? sibling : null;
            }
            if (mddPath != null) {
              try {
                mdd = await MddReader.open(mddPath);
              } catch (e) {
                debugPrint('Failed to load MDD for $dictName: $e');
              }
            }
            handles.remove(dictId)?.close();
            if (!order.contains(dictId)) order.add(dictId);
            final info = DictionaryInfo(
              id: dictId,
              name: dictName,
              mdxPath: mdxPath,
              mddPath: mddPath,
              cssPath: cssPath,
              isEnabled: isEnabled,
              priority: priority,
              entryCount: mdx.numEntries,
              createdAt: DateTime.fromMillisecondsSinceEpoch(createdAtMs),
            );
            handles[dictId] = _WorkerHandle(info: info, mdx: mdx, mdd: mdd);
            parent.send(<Object?>[
              id,
              <String, Object?>{
                'entryCount': mdx.numEntries,
                'changedEntryCount': entryCount != mdx.numEntries,
                'mddPath': mddPath,
                'mddAvailable': mddPath != null && File(mddPath).existsSync(),
                'cssAvailable': cssPath != null && File(cssPath).existsSync(),
              },
              null,
            ]);
          } catch (e) {
            mdd?.close();
            mdx?.close();
            parent.send(<Object?>[id, null, '$e']);
          }
        case 'closeAll':
          closeAll();
          parent.send(<Object?>[id, true, null]);
        case 'closeExcept':
          final keepId = args['keepId'] as String?;
          final toRemove = [
            for (final k in handles.keys)
              if (k != keepId) k,
          ];
          for (final k in toRemove) {
            handles.remove(k)?.close();
            order.remove(k);
          }
          parent.send(<Object?>[id, true, null]);
        case 'search':
          final q = (args['query'] as String).trim().toLowerCase();
          final limit = args['limit'] as int;
          if (q.isEmpty || order.isEmpty) {
            parent.send(<Object?>[id, const <Map<String, Object?>>[], null]);
            return;
          }
          final hits = <Map<String, Object?>>[];
          final seen = <String>{};

          void addHit(_WorkerHandle dict, String word, int matchTypeIndex) {
            final lower = word.toLowerCase();
            if (seen.add(lower)) {
              hits.add(<String, Object?>{
                'word': word,
                'matchType': matchTypeIndex,
                'dictionaryId': dict.info.id,
                'dictionaryName': dict.info.name,
              });
            }
          }

          for (final k in order) {
            final d = handles[k];
            if (d != null && d.mdx.containsKey(q)) {
              addHit(d, q, SearchMatchType.exact.index);
            }
          }
          for (final k in order) {
            final d = handles[k];
            if (d == null) continue;
            for (final word in d.mdx.search(q, limit: limit, prefixOnly: true)) {
              addHit(d, word, SearchMatchType.prefix.index);
              if (hits.length >= limit) break;
            }
            if (hits.length >= limit) break;
          }
          if (hits.length < limit) {
            for (final k in order) {
              final d = handles[k];
              if (d == null) continue;
              for (final word in d.mdx.searchInfix(
                q,
                limit: limit - hits.length,
                excludeLower: seen,
              )) {
                addHit(d, word, SearchMatchType.substring.index);
                if (hits.length >= limit) break;
              }
              if (hits.length >= limit) break;
            }
          }
          parent.send(<Object?>[id, hits, null]);
        case 'lookup':
          final word = args['word'] as String;
          final preferDictId = args['preferDictId'] as String?;
          MdxEntry? parsed;
          String? dictName;

          if (preferDictId != null && handles.containsKey(preferDictId)) {
            final preferred = handles[preferDictId]!;
            final rawHtml = preferred.mdx.getEntry(word);
            if (rawHtml != null) {
              parsed = MdxEntry.parse(word, rawHtml);
              dictName = preferred.info.name;
            }
          }
          if (parsed == null) {
            for (final k in order) {
              final d = handles[k];
              if (d == null) continue;
              final rawHtml = d.mdx.getEntry(word);
              if (rawHtml != null) {
                parsed = MdxEntry.parse(word, rawHtml);
                dictName = d.info.name;
                break;
              }
            }
          }
          parent.send(<Object?>[
            id,
            parsed == null
                ? null
                : <String, Object?>{
                    'entry': parsed.toJson(),
                    'dictName': dictName,
                  },
            null,
          ]);
        case 'audio':
          final soundKey = args['soundKey'] as String;
          Uint8List? bytes;
          for (final k in order) {
            final mdd = handles[k]?.mdd;
            if (mdd != null) {
              bytes = mdd.getResource(soundKey);
              if (bytes != null) break;
            }
          }
          parent.send(<Object?>[
            id,
            bytes == null ? null : TransferableTypedData.fromList([bytes]),
            null,
          ]);
        default:
          parent.send(<Object?>[id, null, 'unknown command: $cmd']);
      }
    } catch (e) {
      parent.send(<Object?>[id, null, '$e']);
    }
  });
}

class DictionaryService {
  static final DictionaryService _instance = DictionaryService._();
  factory DictionaryService() => _instance;
  DictionaryService._();

  final DictionariesDao _dao = DictionariesDao();
  final FrequencyService _frequencyService = FrequencyService();
  final _DictWorker _worker = _DictWorker();

  final List<DictionaryInfo> _activeMeta = [];
  final Map<String, bool> _resourceCache = {};
  bool _isInitialized = false;
  String? _lastLookupDictionaryName;

  bool get hasDictionaries => _activeMeta.isNotEmpty;
  String? get lastLookupDictionaryName => _lastLookupDictionaryName;

  Future<void> initialize() async {
    if (_isInitialized) return;
    unawaited(_frequencyService.init());

    // 1. Load the registered enabled dictionary. Only one may be on: a lookup
    //    has to have one answer and one voice, so a database that still carries
    //    several enabled rows (older builds allowed that) is collapsed to the
    //    first one before anything is opened.
    final registered = await _dao.getEnabled();
    final enabled = await _collapseToSingle(registered);

    if (enabled.isEmpty) {
      // Nothing registered yet: adopt every archive the probe folders hold.
      await autoImportDetectedDictionaries();
    } else {
      for (final info in enabled) {
        await _loadDictionaryHandle(info);
      }
    }

    _isInitialized = true;
  }

  /// Whether a resource path reported by the registry is usable in this build.
  bool resourceAvailable(String? path) {
    if (path == null || path.isEmpty) return false;
    return _resourceCache.putIfAbsent(path, () => File(path).existsSync());
  }

  /// Native targets can read local MDict archives from disk.
  bool get supportsLocalDictionaries => true;

  /// Native builds read archives directly; there is no remote hop to report.
  bool get isBackendConnected => true;

  /// Native builds have no remote backend address.
  String? get backendBaseUrl => null;

  /// Folders probed for archives: `DICT_DIR` (one or more folders separated by
  /// `;`, the same variable the backend reads), the working directory, and the
  /// executable's folder with its ancestors.
  @visibleForTesting
  static List<String> probeDirectories({
    required String cwd,
    required String exeDir,
    String? dictDirEnv,
    int ancestorLevels = 6,
  }) {
    final dirs = <String>[];
    void add(String candidate) {
      final trimmed = candidate.trim();
      if (trimmed.isEmpty) return;
      final absolute = p.normalize(p.absolute(trimmed));
      if (!dirs.contains(absolute)) dirs.add(absolute);
    }

    for (final dir in (dictDirEnv ?? '').split(';')) {
      add(dir);
    }
    add(cwd);
    var dir = p.normalize(p.absolute(exeDir));
    add(dir);
    for (var level = 0; level < ancestorLevels; level++) {
      final parent = p.dirname(dir);
      if (parent == dir) break; // Filesystem root holds no dictionaries to scan.
      add(parent);
      dir = parent;
    }
    return dirs;
  }

  /// Every `.mdx` archive the probe folders hold. Each folder is scanned one
  /// level deep in a background isolate so startup never blocks the UI thread.
  Future<List<String>> autoDetectMdxFiles() {
    final cwd = Directory.current.path;
    final exeDir = p.dirname(Platform.resolvedExecutable);
    final dictDirEnv = Platform.environment['DICT_DIR'];
    return Isolate.run(() => _scanProbeDirs(
          probeDirectories(cwd: cwd, exeDir: exeDir, dictDirEnv: dictDirEnv),
        ));
  }

  static List<String> _scanProbeDirs(List<String> dirs) {
    final found = <String>[];
    for (final dirPath in dirs) {
      final root = Directory(dirPath);
      if (!root.existsSync()) continue;
      for (final folder in <Directory>[
        root,
        ..._listSafely(root).whereType<Directory>(),
      ]) {
        for (final entity in _listSafely(folder)) {
          if (entity is! File) continue;
          if (!entity.path.toLowerCase().endsWith('.mdx')) continue;
          final absolute = p.normalize(entity.absolute.path);
          if (!found.contains(absolute)) found.add(absolute);
        }
      }
    }
    found.sort();
    return found;
  }

  static List<FileSystemEntity> _listSafely(Directory dir) {
    try {
      return dir.listSync();
    } on FileSystemException {
      return const []; // Unreadable folder (permissions, removed drive).
    }
  }

  /// Stable id for a detected archive, so re-scanning never registers the same
  /// dictionary twice — its path is its identity.
  @visibleForTesting
  static String autoDictionaryId(String mdxPath) {
    var hash = 0x811c9dc5;
    for (final byte in utf8.encode(p.normalize(p.absolute(mdxPath)).toLowerCase())) {
      hash = ((hash ^ byte) * 0x01000193) & 0xFFFFFFFF;
    }
    return 'dict_auto_${hash.toRadixString(16).padLeft(8, '0')}';
  }

  Future<List<DictionaryInfo>> _collapseToSingle(
    List<DictionaryInfo> enabled,
  ) async {
    if (enabled.length <= 1) return enabled;
    final kept = enabled.first;
    debugPrint(
      'Only one dictionary may be enabled; keeping ${kept.name}, '
      'turning off ${enabled.length - 1} other(s)',
    );
    await _dao.enableOnly(kept.id);
    return [kept];
  }

  /// Registers every detected archive that is not registered yet.
  Future<List<DictionaryInfo>> autoImportDetectedDictionaries() async {
    final known = {for (final info in await _dao.getAll()) info.mdxPath};
    final hasActive = (await _dao.getEnabled()).isNotEmpty;
    final registered = <DictionaryInfo>[];

    for (final mdxPath in await autoDetectMdxFiles()) {
      if (known.contains(mdxPath)) continue;
      final info = DictionaryInfo(
        id: autoDictionaryId(mdxPath),
        name: p.basenameWithoutExtension(mdxPath),
        mdxPath: mdxPath,
        mddPath: _sidecar(mdxPath, '.mdd'),
        cssPath: _sidecar(mdxPath, '.css') ?? _firstCssIn(p.dirname(mdxPath)),
        isEnabled: false,
        priority: _activeMeta.length + registered.length,
        createdAt: DateTime.now(),
      );
      await _dao.insert(info);
      registered.add(info);
    }

    if (registered.isNotEmpty && !hasActive) {
      await _dao.enableOnly(registered.first.id);
      final enabled = registered.first.copyWith(isEnabled: true);
      registered[0] = enabled;
      await _loadDictionaryHandle(enabled);
    }

    return registered;
  }

  static String? _sidecar(String mdxPath, String extension) {
    final candidate = '${p.withoutExtension(mdxPath)}$extension';
    return File(candidate).existsSync() ? candidate : null;
  }

  static String? _firstCssIn(String dir) {
    final candidates = _listSafely(Directory(dir))
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.css'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    return candidates.isEmpty ? null : candidates.first.absolute.path;
  }

  Future<DictionaryInfo?> _loadDictionaryHandle(DictionaryInfo info) async {
    try {
      final res = await _worker.call<Map<Object?, Object?>>('load', {
        'id': info.id,
        'name': info.name,
        'mdxPath': info.mdxPath,
        'mddPath': info.mddPath,
        'cssPath': info.cssPath,
        'priority': info.priority,
        'entryCount': info.entryCount,
        'createdAtMs': info.createdAt.millisecondsSinceEpoch,
        'isEnabled': info.isEnabled,
      });
      if (res == null) return null;

      var resolvedInfo = info;
      final mddPath = res['mddPath'] as String?;
      final entryCount = res['entryCount'] as int;
      final changedEntryCount = res['changedEntryCount'] as bool;

      if (mddPath != null && mddPath != resolvedInfo.mddPath) {
        resolvedInfo = resolvedInfo.copyWith(mddPath: mddPath);
        await _dao.update(resolvedInfo);
      } else if (changedEntryCount) {
        resolvedInfo = resolvedInfo.copyWith(entryCount: entryCount);
        await _dao.update(resolvedInfo);
      }
      if (resolvedInfo.entryCount != entryCount) {
        resolvedInfo = resolvedInfo.copyWith(entryCount: entryCount);
        await _dao.update(resolvedInfo);
      }

      if (mddPath != null) {
        _resourceCache[mddPath] = res['mddAvailable'] as bool? ?? false;
      }
      if (resolvedInfo.cssPath != null) {
        _resourceCache[resolvedInfo.cssPath!] =
            res['cssAvailable'] as bool? ?? false;
      }

      _activeMeta.removeWhere((d) => d.id == resolvedInfo.id);
      _activeMeta.add(resolvedInfo);
      return resolvedInfo;
    } catch (e) {
      debugPrint('Error loading dictionary ${info.name}: $e');
      return null;
    }
  }

  /// Import a new dictionary from local path
  Future<DictionaryInfo> importDictionary({
    required String mdxPath,
    String? mddPath,
    String? cssPath,
    String? customName,
  }) async {
    final mdxFile = File(mdxPath);
    if (!mdxFile.existsSync()) {
      throw FileSystemException('MDX file not found', mdxPath);
    }

    final baseName = p.basenameWithoutExtension(mdxPath);
    final name = customName ?? baseName;
    final dir = p.dirname(mdxPath);

    final autoMdd = mddPath ?? p.join(dir, '$baseName.mdd');
    final autoCss = cssPath ?? p.join(dir, '$baseName.css');

    final stored = await _adoptIntoAppStorage(
      mdxPath: mdxPath,
      mddPath: File(autoMdd).existsSync() ? autoMdd : null,
      cssPath: File(autoCss).existsSync() ? autoCss : null,
      baseName: baseName,
    );

    final info = DictionaryInfo(
      id: 'dict_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      mdxPath: stored.mdx,
      mddPath: stored.mdd,
      cssPath: stored.css,
      isEnabled: true,
      priority: _activeMeta.length,
      createdAt: DateTime.now(),
    );

    try {
      await _dao.insert(info);
      await _dao.enableOnly(info.id);
      final loaded = await _loadDictionaryHandle(info);
      if (loaded == null) {
        throw Exception('Failed to load imported dictionary');
      }
      await _worker.call<bool>('closeExcept', {'keepId': loaded.id});
      _activeMeta
        ..clear()
        ..add(loaded);
      return loaded;
    } catch (_) {
      await _dao.delete(info.id);
      await _removeOwnedCopies([stored.mdx, stored.mdd, stored.css]);
      rethrow;
    }
  }

  Future<void> _removeOwnedCopies(List<String?> paths) async {
    final ownedDir = await _appStorageDictDir();
    if (ownedDir == null) return;
    for (final path in paths) {
      if (path == null || !p.isWithin(ownedDir, path)) continue;
      try {
        final f = File(path);
        if (f.existsSync()) f.deleteSync();
      } catch (e) {
        debugPrint('Could not remove $path: $e');
      }
    }
  }

  Future<({String mdx, String? mdd, String? css})> _adoptIntoAppStorage({
    required String mdxPath,
    required String? mddPath,
    required String? cssPath,
    required String baseName,
  }) async {
    final dictDir = await _appStorageDictDir();
    if (!requiresDurableImport(
      isAndroid: Platform.isAndroid,
      path: mdxPath,
      appDictDir: dictDir,
    )) {
      return (mdx: mdxPath, mdd: mddPath, css: cssPath);
    }

    final dir = Directory(dictDir!);
    if (!dir.existsSync()) dir.createSync(recursive: true);

    Future<String> copyIn(String source, String extension) async {
      final target = p.join(dir.path, '$baseName$extension');
      final src = File(source);
      if (src.absolute.path == File(target).absolute.path) return target;
      await src.copy(target);
      return target;
    }

    return (
      mdx: await copyIn(mdxPath, '.mdx'),
      mdd: mddPath == null ? null : await copyIn(mddPath, '.mdd'),
      css: cssPath == null ? null : await copyIn(cssPath, '.css'),
    );
  }

  Future<String?> _appStorageDictDir() async {
    if (!Platform.isAndroid) return null;
    final root = await getApplicationSupportDirectory();
    return p.join(root.path, 'local_dict', 'dicts');
  }

  Future<void> reloadDictionaries() async {
    _activeMeta.clear();
    _resourceCache.clear();
    await _worker.call<bool>('closeAll');
    final enabled = await _dao.getEnabled();
    for (final info in enabled) {
      await _loadDictionaryHandle(info);
    }
  }

  Future<void> toggleDictionary(String id, bool isEnabled) async {
    if (isEnabled) {
      await _dao.enableOnly(id);
    } else {
      await _dao.toggleEnabled(id, false);
    }
    await reloadDictionaries();
  }

  Future<void> deleteDictionary(String id) async {
    final info = await _dao.getById(id);
    await _dao.delete(id);

    final ownedDir = await _appStorageDictDir();
    if (info != null && ownedDir != null) {
      for (final path in [info.mdxPath, info.mddPath, info.cssPath]) {
        if (path == null || !p.isWithin(ownedDir, path)) continue;
        try {
          final f = File(path);
          if (f.existsSync()) f.deleteSync();
        } catch (e) {
          debugPrint('Could not remove $path: $e');
        }
      }
    }

    await reloadDictionaries();
  }

  /// Multi-dictionary search with ranked matching (exact -> prefix -> substring)
  Future<List<SearchResult>> search(String query, {int limit = 50}) async {
    if (query.trim().isEmpty || _activeMeta.isEmpty) return const [];
    await _frequencyService.init();
    final rawHits = await _worker.call<List<Object?>>('search', {
      'query': query,
      'limit': limit,
    });
    if (rawHits == null || rawHits.isEmpty) return const [];

    final results = <SearchResult>[];
    for (final item in rawHits) {
      final map = (item as Map).cast<String, Object?>();
      final word = map['word'] as String;
      final matchType = SearchMatchType.values[map['matchType'] as int];
      final freq = _frequencyService.getFrequency(word.toLowerCase());
      results.add(SearchResult(
        word: word,
        matchType: matchType,
        dictionaryId: map['dictionaryId'] as String,
        dictionaryName: map['dictionaryName'] as String,
        briefDefinition: freq?.briefZh,
        frequencyBadge: freq?.rank != null ? freq!.frequencyLabel : null,
      ));
    }
    return results;
  }

  /// Lookup a word entry across loaded dictionaries
  Future<MdxEntry?> lookup(String word, {String? preferDictId}) async {
    if (_activeMeta.isEmpty) return null;
    final res = await _worker.call<Map<Object?, Object?>>('lookup', {
      'word': word,
      'preferDictId': preferDictId,
    });
    if (res == null) return null;
    _lastLookupDictionaryName = res['dictName'] as String?;
    final entryMap = (res['entry'] as Map).cast<String, dynamic>();
    return MdxEntry.fromJson(entryMap);
  }

  /// Retrieve pronunciation audio data (MP3/WAV) from associated MDD
  Future<Uint8List?> getAudioBytes(String soundKey) async {
    if (_activeMeta.isEmpty) return null;
    final raw = await _worker.call<Object?>('audio', {'soundKey': soundKey});
    return switch (raw) {
      TransferableTypedData t => t.materialize().asUint8List(),
      Uint8List b => b,
      _ => null,
    };
  }

  void dispose() {
    _activeMeta.clear();
    _resourceCache.clear();
    _worker.dispose();
  }
}
