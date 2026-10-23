import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'kokoro_model.dart';

/// `MainActivity`'s channel for the model that ships inside the APK.
const MethodChannel _modelsChannel = MethodChannel('local_dict/bundled_models');

/// Finds the Kokoro model on this machine.
///
/// The folders probed are the ones the dictionary scan uses: `TTS_MODEL_DIR`
/// (one or more folders, `;`-separated), then the working directory, then the
/// program's folder and its ancestors, then the app's own storage.
///
/// Android also carries the model inside the APK: nothing found means it has not
/// been unpacked yet, so it is unpacked once and the search repeats.
Future<KokoroModelFiles?> findKokoroModel() async {
  var files = await _search();
  if (files != null) return files;
  if (Platform.isAndroid && await _installBundled()) {
    files = await _search();
  }
  return files;
}

Future<KokoroModelFiles?> _search() async {
  for (final root in await _candidateRoots()) {
    final files = _modelIn(root);
    if (files != null) return files;
  }
  return null;
}

Future<bool> _installBundled() async {
  try {
    return await _modelsChannel.invokeMethod<bool>('install') ?? false;
  } on PlatformException catch (e) {
    debugPrint('Unpacking the bundled Kokoro model failed: $e');
    return false;
  } on MissingPluginException {
    return false;
  }
}

/// Nothing to do on a machine with a file system: the library opens the files
/// where they are. The browser build fetches them into its wasm first, which is
/// why both platforms answer the same call.
Future<void> prepareKokoroModel(KokoroModelFiles files) async {}

/// What the UI says when nothing is installed.
Future<String> kokoroModelHint() async {
  final roots = await _candidateRoots();
  final where = roots.isEmpty ? kokoroModelRoot : roots.first;
  return '未安装 Kokoro 模型：放到 $where${p.separator}$kokoroModelRoot'
      '${p.separator}$kokoroModelFolder${p.separator}'
      '（或运行 python tool/fetch_kokoro_model.py）';
}

Future<List<String>> _candidateRoots() async {
  final roots = <String>[];
  void add(String? path) {
    if (path == null) return;
    final trimmed = path.trim();
    if (trimmed.isEmpty) return;
    final absolute = p.normalize(p.absolute(trimmed));
    if (!roots.contains(absolute)) roots.add(absolute);
  }

  for (final dir in (Platform.environment['TTS_MODEL_DIR'] ?? '').split(';')) {
    add(dir);
  }
  add(Directory.current.path);

  var dir = p.normalize(p.absolute(p.dirname(Platform.resolvedExecutable)));
  add(dir);
  for (var level = 0; level < 6; level++) {
    final parent = p.dirname(dir);
    if (parent == dir) break;
    add(parent);
    dir = parent;
  }

  try {
    add((await getApplicationSupportDirectory()).path);
  } catch (e) {
    debugPrint('no application support directory: $e');
  }
  if (Platform.isAndroid) {
    try {
      add((await getExternalStorageDirectory())!.path);
    } catch (_) {
      // External storage unavailable.
    }
  }
  return roots;
}

/// The model files under [root], accepting either `root/kokoro/…` or
/// `root/tts-models/kokoro/…`.
KokoroModelFiles? _modelIn(String root) {
  for (final base in [root, p.join(root, kokoroModelRoot)]) {
    final folder = p.join(base, kokoroModelFolder);
    final model = p.join(folder, kokoroModelFile);
    final voices = p.join(folder, kokoroVoicesFile);
    final tokens = p.join(folder, kokoroTokensFile);
    final dataDir = p.join(folder, kokoroDataFolder);
    if (File(model).existsSync() &&
        File(voices).existsSync() &&
        File(tokens).existsSync() &&
        Directory(dataDir).existsSync()) {
      return KokoroModelFiles(
        model: model,
        voices: voices,
        tokens: tokens,
        dataDir: dataDir,
        folder: folder,
      );
    }
  }
  return null;
}
