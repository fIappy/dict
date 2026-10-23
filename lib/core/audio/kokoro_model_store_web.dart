import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'kokoro_model.dart';

/// Finds the Kokoro model for the browser build.
///
/// The model is served next to the app (`/tts-models/kokoro/…`). Existence is
/// checked with a HEAD request on the folder's file list, which is what decides
/// whether the engine can speak at all.
Future<KokoroModelFiles?> findKokoroModel() async {
  final folder = '$kokoroModelRoot/$kokoroModelFolder';
  final files = KokoroModelFiles(
    model: '$folder/$kokoroModelFile',
    voices: '$folder/$kokoroVoicesFile',
    tokens: '$folder/$kokoroTokensFile',
    dataDir: '$folder/$kokoroDataFolder',
    folder: folder,
  );
  return await _exists('$folder/$kokoroManifest') ? files : null;
}

Future<String> kokoroModelHint() async =>
    '未安装模型：把 Kokoro 模型放到站点的 /$kokoroModelRoot/$kokoroModelFolder/ 下'
    '（或运行 python tool/fetch_kokoro_model.py 后一并部署）';

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



Future<void> prepareKokoroModel(KokoroModelFiles files) async {
  final raw = globalContext['Module'] as JSObject?;
  if (raw == null) {
    throw StateError('sherpa-onnx wasm module is not loaded yet');
  }
  final module = _EmscriptenModule._(raw);

  final listing = await _text('${files.folder}/$kokoroManifest');
  if (listing == null) {
    throw StateError('${files.folder}/$kokoroManifest is missing');
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
      .where((line) => line.isNotEmpty && line != kokoroManifest)
      .toList();

  // Fetching ~400 files (~150 MB) one at a time would take longer than the
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

Future<String?> _text(String url) async {
  try {
    final response = await web.window.fetch(url.toJS).toDart;
    if (!response.ok) return null;
    return (await response.text().toDart).toDart;
  } catch (_) {
    return null;
  }
}
