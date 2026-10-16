import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'piper_model.dart';

/// Finds the Piper models for the browser build.
///
/// The models are served next to the app (`/tts-models/piper/<accent>/…`), which
/// the deployment guide covers. Existence is checked with a HEAD request on the
/// folder's file list, which is what decides whether the engine can speak at all.
Future<PiperModelFiles?> findPiperModel(String accent) async {
  final folder = '$piperModelRoot/$piperModelFolder/${piperAccentFolder(accent)}';
  final files = PiperModelFiles(
    model: '$folder/$piperModelFile',
    tokens: '$folder/$piperTokensFile',
    dataDir: '$folder/$piperDataFolder',
    folder: folder,
  );
  return await _exists('$folder/$piperManifest') ? files : null;
}

Future<String> piperModelHint() async =>
    '未安装模型：把 Piper 模型放到站点的 /$piperModelRoot/$piperModelFolder/<us|uk>/ 下'
    '（或运行 python tool/fetch_piper_models.py 后一并部署）';

/// The Emscripten module object, as far as this file needs it: the two file
/// system helpers its file system is written through.
extension type _EmscriptenModule._(JSObject _) implements JSObject {
  @JS('FS_createPath')
  external void createPath(
    JSString parent,
    JSString path,
    JSBoolean canRead,
    JSBoolean canWrite,
  );

  @JS('FS_createDataFile')
  external void createDataFile(
    JSString parent,
    JSString name,
    JSUint8Array data,
    JSBoolean canRead,
    JSBoolean canWrite,
    JSBoolean canOwn,
  );
}

/// The browser cannot read a folder: the models are served by the site, so there
/// is nothing to import.
bool get canImportPiperModels => false;

bool get piperImportUsesArchive => false;

Future<List<String>> importPiperModelsFrom(String sourceDir) async => const [];

Future<List<String>> installPiperArchive(List<int> archiveBytes) async => const [];

Future<List<int>> readPickedFile(String path) async => const [];

Future<List<String>> installPiperArchiveIn(List<int> bytes, String destination) async => const [];

/// Hands the model to the WebAssembly module.
///
/// The library inside the wasm reads its files from Emscripten's *own* file
/// system — a plain HTTP path means nothing to it, which is why a model that is
/// perfectly reachable by `fetch` still reports "does not exist". Every file of
/// the folder is therefore fetched here and written into that file system, at the
/// same relative paths the configuration refers to. One fetch per file (~16 MB
/// for a voice) happens the first time the engine is used; the browser's cache
/// serves the rest.
Future<void> preparePiperModel(PiperModelFiles files) async {
  final raw = globalContext['Module'] as JSObject?;
  if (raw == null) {
    throw StateError('sherpa-onnx wasm module is not loaded yet');
  }
  final module = _EmscriptenModule._(raw);

  final listing = await _text('${files.folder}/$piperManifest');
  if (listing == null) {
    throw StateError('${files.folder}/$piperManifest is missing');
  }

  final created = <String>{};
  void path(String directory) {
    // `FS_createPath` creates every missing level, so each directory is asked for
    // once and the file system is never traversed twice for the same path.
    final parts = directory.split('/');
    for (var i = 1; i <= parts.length; i++) {
      final parent = parts.take(i - 1).join('/');
      final name = parts[i - 1];
      if (name.isEmpty || !created.add('$parent/$name')) continue;
      module.createPath(
        (parent.isEmpty ? '/' : parent).toJS,
        name.toJS,
        true.toJS,
        true.toJS,
      );
    }
  }

  path(files.folder);

  final entries = listing
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty && line != piperManifest)
      .toList();

  // Fetching 350-odd small files one at a time would take longer than the
  // synthesis it enables, so they go in batches.
  const batch = 8;
  for (var start = 0; start < entries.length; start += batch) {
    final slice = entries.sublist(
      start,
      (start + batch) > entries.length ? entries.length : start + batch,
    );
    final fetched = await Future.wait(slice.map((rel) => _bytes('${files.folder}/$rel')));
    for (var i = 0; i < slice.length; i++) {
      final bytes = fetched[i];
      final rel = slice[i];
      if (bytes == null) throw StateError('${files.folder}/$rel could not be read');
      final cut = rel.lastIndexOf('/');
      final directory = cut == -1 ? files.folder : '${files.folder}/${rel.substring(0, cut)}';
      final name = cut == -1 ? rel : rel.substring(cut + 1);
      if (directory != files.folder) path(directory);
      module.createDataFile(
        directory.toJS,
        name.toJS,
        bytes.toJS,
        true.toJS,
        true.toJS,
        true.toJS,
      );
    }
  }
}

Future<bool> _exists(String url) async {
  try {
    final response = await web.window.fetch(url.toJS, web.RequestInit(method: 'HEAD')).toDart;
    return response.ok;
  } catch (_) {
    // Offline or blocked: treat as "not installed" and keep using another engine.
    return false;
  }
}

Future<String?> _text(String url) async {
  try {
    final response = await web.window.fetch(url.toJS).toDart;
    if (!response.ok) return null;
    return (await response.text().toDart).toDart;
  } catch (_) {
    return null;
  }
}

Future<Uint8List?> _bytes(String url) async {
  try {
    final response = await web.window.fetch(url.toJS).toDart;
    if (!response.ok) return null;
    final buffer = await response.arrayBuffer().toDart;
    return buffer.toDart.asUint8List();
  } catch (_) {
    return null;
  }
}
