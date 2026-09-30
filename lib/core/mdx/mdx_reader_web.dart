/// Web stub for the MDict (`.mdx`) reader.
///
/// `dart:io` random-access file reads are unavailable in the browser, so the
/// reader cannot be constructed here. `DictionaryService` never opens an
/// archive on web; this class exists only to keep the shared interfaces
/// compiling across platforms.
class MdxKeyBlockMeta {
  final int count;
  final String firstKey;
  final String lastKey;
  final int compSize;
  final int decompSize;
  final int filePos;

  MdxKeyBlockMeta({
    required this.count,
    required this.firstKey,
    required this.lastKey,
    required this.compSize,
    required this.decompSize,
    required this.filePos,
  });
}

class MdxRecordBlockMeta {
  final int compSize;
  final int decompSize;
  final int filePos;
  final int decompAccumOffset;

  MdxRecordBlockMeta({
    required this.compSize,
    required this.decompSize,
    required this.filePos,
    required this.decompAccumOffset,
  });
}

class MdxReader {
  final String filePath;
  final String headerText;
  final String encoding;
  final int numEntries;

  MdxReader._({
    required this.filePath,
    required this.headerText,
    required this.encoding,
    required this.numEntries,
  });

  static Future<MdxReader> open(String path) async {
    throw UnsupportedError(
      'MDX 词典解析依赖本地文件系统，网页版不可用。',
    );
  }

  List<String> get allKeys => const [];

  List<int> get allOffsets => const [];

  List<String> search(String query, {int limit = 50, bool prefixOnly = false}) {
    return const [];
  }

  String? getEntry(String word, {int depth = 0}) => null;

  void close() {}
}
