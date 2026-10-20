import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'piper_model.dart';

/// `MainActivity`'s channel for the voices that ship inside the APK.
const MethodChannel _modelsChannel = MethodChannel('local_dict/bundled_models');

/// Finds the Piper models on this machine.
///
/// The folders probed are the same ones the dictionary scan uses, in the same
/// order, so there is one rule to remember: `TTS_MODEL_DIR` (one or more folders,
/// `;`-separated), then the working directory, then the program's folder and its
/// ancestors, then the app's own storage. The Android build reads them from its
/// external files directory, which is what `adb push` and any file manager can
/// reach without special permissions.
///
/// Android also carries the voices inside the APK: nothing found means they
/// have not been unpacked yet, so they are unpacked once and the search repeats.
Future<PiperModelFiles?> findPiperModel(String accent) async {
  var files = await _searchPiperModel(accent);
  if (files != null) return files;
  if (Platform.isAndroid && await installBundledPiperModels()) {
    files = await _searchPiperModel(accent);
  }
  return files;
}

Future<PiperModelFiles?> _searchPiperModel(String accent) async {
  for (final root in await _candidateRoots()) {
    final files = _modelIn(root, accent);
    if (files != null) return files;
  }
  return null;
}

/// Unpacks the voices bundled in the APK into app storage.
///
/// The APK carries `assets/piper.zip` (staged from `tts-models/piper.zip` at
/// build time), so a phone gets the neural voice from a plain install — no
/// computer, no download, no import step. The native side does the unpacking on
/// a background thread and answers true once the files are where it put them;
/// platforms without the bundle answer false and keep the old import route.
Future<bool> installBundledPiperModels() async {
  if (!Platform.isAndroid) return false;
  try {
    return await _modelsChannel.invokeMethod<bool>('install') ?? false;
  } on PlatformException catch (e) {
    debugPrint('Unpacking the bundled Piper models failed: $e');
    return false;
  } on MissingPluginException {
    return false;
  }
}

/// This platform can copy models in from a folder the user picks — and on
/// Android it must, because scoped storage hides any file another tool wrote
/// into the app's data directory.
bool get canImportPiperModels => true;

/// Android installs them from a `.zip` instead of a folder: the picker hands over
/// a readable copy of a *file*, while a picked folder only comes as a SAF tree
/// this app cannot open by path.
bool get piperImportUsesArchive => Platform.isAndroid;

/// Reads a file the picker returned (Android hands back a copy of it in the
/// app's cache, which is readable — a picked *folder* is not).
Future<List<int>> readPickedFile(String path) async => File(path).readAsBytes();

/// Installs the voices inside a `.zip` the user picked, returning the accents
/// that were installed.
///
/// Android needs the archive route: the file picker hands over a *copy* of the
/// files it is given, while a picked folder is only granted as a SAF tree that
/// this app cannot open as a path. One archive is also the only practical way to
/// move 350-odd files (the model plus espeak-ng data) in one go.
Future<List<String>> installPiperArchive(List<int> archiveBytes) async {
  final support = await getApplicationSupportDirectory();
  return installPiperArchiveIn(archiveBytes, p.join(support.path, piperModelRoot));
}

/// The archive half, without the app-storage lookup, so it can be tested.
Future<List<String>> installPiperArchiveIn(List<int> archiveBytes, String destination) async {
  final temp = Directory.systemTemp.createTempSync('piper_zip');
  try {
    final archive = ZipDecoder().decodeBytes(archiveBytes);
    for (final entry in archive) {
      final target = p.join(temp.path, entry.name);
      if (!p.isWithin(temp.path, target) && target != temp.path) {
        continue; // A path escaping the archive: refuse it.
      }
      if (entry.isFile) {
        final file = File(target)..createSync(recursive: true);
        file.writeAsBytesSync(entry.content as List<int>);
      } else {
        Directory(target).createSync(recursive: true);
      }
    }
    final installed = await copyPiperModels(source: temp.path, destination: destination);
    return installed;
  } finally {
    temp.deleteSync(recursive: true);
  }
}

/// Copies the Piper voice the user pointed at into app storage, returning the
/// accents that were installed.
Future<List<String>> importPiperModelsFrom(String sourceDir) async {
  final support = await getApplicationSupportDirectory();
  return copyPiperModels(
    source: sourceDir,
    destination: p.join(support.path, piperModelRoot),
  );
}

/// Nothing to do on a machine with a file system: the library opens the files
/// where they are. The browser build has to fetch them into the wasm first, which
/// is why both platforms answer the same call.
Future<void> preparePiperModel(PiperModelFiles files) async {}

/// A sentence the UI shows when nothing is installed.
Future<String> piperModelHint() async {
  if (Platform.isAndroid) {
    // The APK carries the voices and unpacks them on first launch. Reaching this
    // hint means that did not happen (an APK built without them, e.g. a debug
    // build made before `tts-models/` existed), so the archive is the way in.
    return '未安装模型：正式包自带模型，这里只用于更新'
        '——点「安装模型…」选 piper.zip';
  }
  final roots = await _candidateRoots();
  final where = roots.isEmpty ? piperModelRoot : roots.first;
  return '未安装模型：把 Piper 模型放到 $where${p.separator}$piperModelRoot'
      '${p.separator}$piperModelFolder${p.separator}<us|uk>${p.separator}'
      '（或运行 python tool/fetch_piper_models.py）';
}

/// Folders that may hold `tts-models/` (their own `piper/…` is accepted too).
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

  for (final storage in await _appStorage()) {
    add(storage);
  }
  return roots;
}

/// App-owned places a model may live: internal storage, and on Android the
/// external files directory (`Android/data/<package>/files`) that a computer can
/// write to over USB.
Future<List<String>> _appStorage() async {
  final dirs = <String>[];
  try {
    dirs.add((await getApplicationSupportDirectory()).path);
  } catch (_) {
    // No such folder on this platform.
  }
  if (Platform.isAndroid) {
    try {
      dirs.add((await getExternalStorageDirectory())!.path);
    } catch (_) {
      // External storage unavailable.
    }
  }
  return dirs;
}

/// The model files under [root], accepting either `root/piper/<accent>/…` or
/// `root/tts-models/piper/<accent>/…`.
PiperModelFiles? _modelIn(String root, String accent) {
  final accentFolder = piperAccentFolder(accent);
  for (final base in [
    root,
    p.join(root, piperModelRoot),
  ]) {
    final folder = p.join(base, piperModelFolder, accentFolder);
    final model = p.join(folder, piperModelFile);
    final tokens = p.join(folder, piperTokensFile);
    final dataDir = p.join(folder, piperDataFolder);
    if (File(model).existsSync() &&
        File(tokens).existsSync() &&
        Directory(dataDir).existsSync()) {
      return PiperModelFiles(
        model: model,
        tokens: tokens,
        dataDir: dataDir,
        folder: folder,
      );
    }
  }
  return null;
}

/// Copies a Piper voice from [source] into [destination], and returns the accents
/// that were installed.
///
/// Android needs this: scoped storage means the app cannot read a model that
/// another tool (or `adb push`) wrote into its data directory, so the files have
/// to be copied by the app itself from wherever the user points it — exactly how
/// dictionaries are imported.
///
/// Accepted layouts, so a folder picked from any of the places the models come
/// from works:
///
///     <source>/piper/<us|uk>/…        the layout this app uses
///     <source>/<us|uk>/…              the same, without the outer folder
///     <source>/…                      one voice's files directly
///
/// A voice is recognised by its `*.onnx` + `tokens.txt` + `espeak-ng-data/`; the
/// model is stored as `model.onnx` so every platform addresses the same names.
Future<List<String>> copyPiperModels({
  required String source,
  required String destination,
}) async {
  final installed = <String>[];

  for (final accent in accents) {
    final from = _voiceFolderIn(source, accent);
    if (from == null) continue;

    final to = p.join(destination, piperModelFolder, accent);
    final directory = Directory(to);
    if (directory.existsSync()) directory.deleteSync(recursive: true);
    directory.createSync(recursive: true);

    final written = <String>{piperTokensFile};
    for (final entry in Directory(from).listSync(recursive: true)) {
      if (entry is! File) continue;
      final relative = p.relative(entry.path, from: from);
      if (p.basename(relative) == piperManifest) continue;
      // The model keeps its own name inside the file; the app looks for the
      // canonical one, so it is renamed on the way in.
      final target = relative.endsWith('.onnx') ? piperModelFile : relative;
      final file = File(p.join(to, target));
      file.parent.createSync(recursive: true);
      entry.copySync(file.path);
      // The manifest is read by the browser build, which uses '/'.
      written.add(target.replaceAll(p.separator, '/'));
    }
    // The manifest is what the browser build fetches, so an imported voice ends
    // up shaped exactly like a fetched one.
    File(p.join(to, piperManifest))
        .writeAsStringSync('${(written.toList()..sort()).join('\n')}\n');
    installed.add(accent);
  }

  return installed;
}

/// The folder holding [accent]'s voice under [source], or null when there is none.
String? _voiceFolderIn(String source, String accent) {
  final candidates = [
    p.join(source, piperModelFolder, accent),
    p.join(source, accent),
    source,
  ];
  for (final candidate in candidates) {
    final directory = Directory(candidate);
    if (!directory.existsSync()) continue;
    final files = directory.listSync().whereType<File>().toList();
    final model = files.where((f) => f.path.endsWith('.onnx')).toList();
    final hasTokens = files.any((f) => p.basename(f.path) == piperTokensFile);
    final hasData = Directory(p.join(candidate, piperDataFolder)).existsSync();
    if (model.isEmpty || !hasTokens || !hasData) continue;
    // A folder holding one voice must really be this accent, judged by the
    // model's own name (`en_GB-…`), or the app would label it wrongly.
    if (candidate == source && !model.first.path.contains(accent == 'uk' ? 'en_GB' : 'en_US')) {
      continue;
    }
    return candidate;
  }
  return null;
}
