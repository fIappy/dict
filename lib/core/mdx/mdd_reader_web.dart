import 'dart:typed_data';

/// Web stub for the MDict resource reader (`.mdd`).
///
/// Browsers cannot random-access local files, so bundled pronunciation
/// archives are unavailable. `DictionaryService` never opens one on web.
class MddKeyBlockMeta {
  final int count;
  final String firstKey;
  final String lastKey;
  final int compSize;
  final int decompSize;
  final int filePos;

  MddKeyBlockMeta({
    required this.count,
    required this.firstKey,
    required this.lastKey,
    required this.compSize,
    required this.decompSize,
    required this.filePos,
  });
}

class MddRecordBlockMeta {
  final int compSize;
  final int decompSize;
  final int filePos;
  final int decompAccumOffset;

  MddRecordBlockMeta({
    required this.compSize,
    required this.decompSize,
    required this.filePos,
    required this.decompAccumOffset,
  });
}

class MddReader {
  final String filePath;

  MddReader._({required this.filePath});

  static Future<MddReader> open(String path) async {
    throw UnsupportedError(
      'MDD 发音资源库依赖本地文件系统，网页版不可用。',
    );
  }

  Uint8List? getResource(String rawKey) => null;

  void close() {}
}
