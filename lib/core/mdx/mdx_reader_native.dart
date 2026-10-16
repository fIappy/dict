import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
  final RandomAccessFile _raf;
  final String headerText;
  final String encoding;
  final int numEntries;
  final List<MdxKeyBlockMeta> _keyBlocks = [];
  final List<MdxRecordBlockMeta> _recordBlocks = [];

  // In-memory key index for sub-millisecond prefix & substring search
  List<String> _keys = [];
  List<int> _offsets = [];
  // Lowercased headword -> index of its *first* key, so the duplicate group
  // that follows it in the sorted key list can be walked without a second map.
  Map<String, int> _exactIndex = {};
  List<int> get allOffsets => _offsets;

  // Simple LRU cache for decompressed record blocks
  final Map<int, Uint8List> _recordBlockCache = {};
  final List<int> _recordBlockLru = [];
  static const int _maxCacheBlocks = 16;

  MdxReader._(
    this._raf, {
    required this.filePath,
    required this.headerText,
    required this.encoding,
    required this.numEntries,
  });

  static Future<MdxReader> open(String path) async {
    final file = File(path);
    if (!file.existsSync()) {
      throw FileSystemException('MDX file not found', path);
    }
    final raf = file.openSync();
    try {
      final hlen = ByteData.sublistView(raf.readSync(4)).getUint32(0, Endian.big);
      final hbytes = raf.readSync(hlen);
      raf.readSync(4); // checksum

      String header;
      try {
        header = utf8.decode(hbytes);
      } catch (_) {
        header = _decodeUtf16Le(hbytes);
      }

      String enc = 'UTF-8';
      final encMatch = RegExp('Encoding=["\']([^"\']+)["\']', caseSensitive: false).firstMatch(header);
      if (encMatch != null) {
        final val = encMatch.group(1)!.toUpperCase();
        if (val.contains('UTF-16') || val.contains('UTF16')) {
          enc = 'UTF-16LE';
        }
      }

      final kinfoBuf = ByteData.sublistView(raf.readSync(40));
      final numKeyBlocks = kinfoBuf.getUint64(0, Endian.big);
      final entriesCount = kinfoBuf.getUint64(8, Endian.big);
      final compKbInfoSize = kinfoBuf.getUint64(24, Endian.big);
      kinfoBuf.getUint64(32, Endian.big); // keyBlockSize
      raf.readSync(4); // checksum

      final compKbInfo = raf.readSync(compKbInfoSize);
      final decompKbInfo = Uint8List.fromList(zlib.decode(compKbInfo.sublist(8)));
      final bd = ByteData.sublistView(decompKbInfo);

      final reader = MdxReader._(
        raf,
        filePath: path,
        headerText: header,
        encoding: enc,
        numEntries: entriesCount,
      );

      int pos = 0;
      int curKbPos = raf.positionSync();
      final isUtf16 = enc == 'UTF-16LE';

      for (int i = 0; i < numKeyBlocks; i++) {
        final count = bd.getUint64(pos, Endian.big); pos += 8;
        final k1Len = bd.getUint16(pos, Endian.big); pos += 2;
        String k1;
        if (isUtf16) {
          k1 = _decodeUtf16Le(decompKbInfo.sublist(pos, pos + k1Len * 2));
          pos += k1Len * 2 + 2;
        } else {
          k1 = utf8.decode(decompKbInfo.sublist(pos, pos + k1Len), allowMalformed: true);
          pos += k1Len + 1;
        }

        final k2Len = bd.getUint16(pos, Endian.big); pos += 2;
        String k2;
        if (isUtf16) {
          k2 = _decodeUtf16Le(decompKbInfo.sublist(pos, pos + k2Len * 2));
          pos += k2Len * 2 + 2;
        } else {
          k2 = utf8.decode(decompKbInfo.sublist(pos, pos + k2Len), allowMalformed: true);
          pos += k2Len + 1;
        }

        final compSize = bd.getUint64(pos, Endian.big); pos += 8;
        final decompSize = bd.getUint64(pos, Endian.big); pos += 8;

        reader._keyBlocks.add(MdxKeyBlockMeta(
          count: count,
          firstKey: k1,
          lastKey: k2,
          compSize: compSize,
          decompSize: decompSize,
          filePos: curKbPos,
        ));
        curKbPos += compSize;
      }

      // Record block headers
      raf.setPositionSync(curKbPos);
      final rinfoBuf = ByteData.sublistView(raf.readSync(32));
      final numRecordBlocks = rinfoBuf.getUint64(0, Endian.big);
      final recInfoSize = rinfoBuf.getUint64(16, Endian.big);

      final recInfoBytes = raf.readSync(recInfoSize);
      final rbd = ByteData.sublistView(recInfoBytes);
      int rpos = 0;
      int curRbPos = raf.positionSync();
      int accumDecomp = 0;

      for (int i = 0; i < numRecordBlocks; i++) {
        final compSize = rbd.getUint64(rpos, Endian.big); rpos += 8;
        final decompSize = rbd.getUint64(rpos, Endian.big); rpos += 8;
        reader._recordBlocks.add(MdxRecordBlockMeta(
          compSize: compSize,
          decompSize: decompSize,
          filePos: curRbPos,
          decompAccumOffset: accumDecomp,
        ));
        curRbPos += compSize;
        accumDecomp += decompSize;
      }

      // Load keys in memory for fast lookup
      reader._loadAllKeys();

      return reader;
    } catch (e) {
      raf.closeSync();
      rethrow;
    }
  }

  void _loadAllKeys() {
    final keys = <String>[];
    final offsets = <int>[];
    final exact = <String, int>{};
    final isUtf16 = encoding == 'UTF-16LE';

    for (final kb in _keyBlocks) {
      _raf.setPositionSync(kb.filePos);
      final raw = _raf.readSync(kb.compSize);
      final decomp = Uint8List.fromList(zlib.decode(raw.sublist(8)));
      final dbd = ByteData.sublistView(decomp);

      int kp = 0;
      for (int i = 0; i < kb.count; i++) {
        final off = dbd.getUint64(kp, Endian.big);
        kp += 8;

        String key;
        if (isUtf16) {
          int term = -1;
          for (int p = kp; p < decomp.length - 1; p += 2) {
            if (decomp[p] == 0 && decomp[p + 1] == 0) {
              term = p;
              break;
            }
          }
          if (term == -1) term = decomp.length;
          key = _decodeUtf16Le(decomp.sublist(kp, term));
          kp = term + 2;
        } else {
          int term = decomp.indexOf(0, kp);
          if (term == -1) term = decomp.length;
          key = utf8.decode(decomp.sublist(kp, term), allowMalformed: true);
          kp = term + 1;
        }

        keys.add(key);
        offsets.add(off);
        final lower = key.toLowerCase();
        exact.putIfAbsent(lower, () => keys.length - 1);
      }
    }

    _keys = keys;
    _offsets = offsets;
    _exactIndex = exact;
  }

  List<String> get allKeys => _keys;

  /// Find words matching prefix or partial query
  List<String> search(String query, {int limit = 50, bool prefixOnly = false}) {
    if (query.trim().isEmpty) return const [];
    final q = query.trim().toLowerCase();
    final results = <String>[];
    final seen = <String>{};

    // 1. Exact match first
    final exactIndex = _exactIndex[q];
    if (exactIndex != null) {
      final exactWord = _keys[exactIndex];
      if (exactWord.isNotEmpty) {
        results.add(exactWord);
        seen.add(exactWord.toLowerCase());
      }
    }

    // 2. Binary search for prefix matches
    int low = 0, high = _keys.length - 1;
    int firstMatch = -1;
    while (low <= high) {
      int mid = (low + high) ~/ 2;
      int cmp = _keys[mid].toLowerCase().compareTo(q);
      if (cmp >= 0) {
        if (_keys[mid].toLowerCase().startsWith(q)) {
          firstMatch = mid;
        }
        high = mid - 1;
      } else {
        low = mid + 1;
      }
    }

    if (firstMatch != -1) {
      for (int i = firstMatch; i < _keys.length && results.length < limit; i++) {
        final k = _keys[i];
        final lower = k.toLowerCase();
        if (lower.startsWith(q)) {
          if (!seen.contains(lower)) {
            results.add(k);
            seen.add(lower);
          }
        } else {
          break;
        }
      }
    }

    // 3. Substring (infix) partial matching if not prefixOnly and limit not reached
    if (!prefixOnly && results.length < limit) {
      for (final k in _keys) {
        final lower = k.toLowerCase();
        if (!seen.contains(lower) && lower.contains(q)) {
          results.add(k);
          seen.add(lower);
          if (results.length >= limit) break;
        }
      }
    }

    return results;
  }

  /// Get entry HTML for a given word, resolving @@@LINK redirects.
  ///
  /// A headword may own several records: the SIO series stores the Forvo audio
  /// bar, the English section, the Chinese reverse lookup and the phrase
  /// section as separate records under the same key, and reference clients
  /// render them one after another. Every matching record is therefore joined
  /// in archive order; single-record archives are unaffected.
  String? getEntry(String word) {
    final records = getEntries(word);
    return records.isEmpty ? null : records.join('\n');
  }

  /// Every record stored under [word] (case-insensitive), in archive order.
  /// A record that redirects contributes its target's records instead.
  List<String> getEntries(String word, {int depth = 0}) {
    if (depth > 5) return const []; // Circular redirects end here.
    final out = <String>[];
    for (final index in _keyIndexesFor(word.trim().toLowerCase())) {
      final raw = _readRawRecord(_offsets[index]);
      if (raw == null) continue;

      final trimmed = raw.trim();
      if (trimmed.startsWith('@@@LINK=')) {
        out.addAll(getEntries(
          trimmed.substring('@@@LINK='.length).trim(),
          depth: depth + 1,
        ));
      } else {
        out.add(raw);
      }
    }
    return out;
  }

  /// Indices of every key equal to [lower], which are contiguous because the
  /// key list is sorted case-insensitively by the archive writer.
  List<int> _keyIndexesFor(String lower) {
    final first = _exactIndex[lower];
    if (first == null) return const [];
    final out = <int>[first];
    for (int i = first + 1; i < _keys.length && _keys[i].toLowerCase() == lower; i++) {
      out.add(i);
    }
    return out;
  }

  Uint8List _getRecordBlock(int blockIndex) {
    if (_recordBlockCache.containsKey(blockIndex)) {
      _recordBlockLru.remove(blockIndex);
      _recordBlockLru.add(blockIndex);
      return _recordBlockCache[blockIndex]!;
    }

    final rb = _recordBlocks[blockIndex];
    _raf.setPositionSync(rb.filePos);
    final compData = _raf.readSync(rb.compSize);
    final decomp = Uint8List.fromList(zlib.decode(compData.sublist(8)));

    if (_recordBlockCache.length >= _maxCacheBlocks) {
      final oldest = _recordBlockLru.removeAt(0);
      _recordBlockCache.remove(oldest);
    }
    _recordBlockCache[blockIndex] = decomp;
    _recordBlockLru.add(blockIndex);

    return decomp;
  }

  String? _readRawRecord(int offset) {
    // Binary search record block
    int low = 0, high = _recordBlocks.length - 1;
    int targetRbIdx = -1;
    while (low <= high) {
      int mid = (low + high) ~/ 2;
      final rb = _recordBlocks[mid];
      if (offset >= rb.decompAccumOffset &&
          offset < rb.decompAccumOffset + rb.decompSize) {
        targetRbIdx = mid;
        break;
      } else if (offset < rb.decompAccumOffset) {
        high = mid - 1;
      } else {
        low = mid + 1;
      }
    }

    if (targetRbIdx == -1) return null;

    final targetRb = _recordBlocks[targetRbIdx];
    final decompRb = _getRecordBlock(targetRbIdx);
    final inBlockOffset = offset - targetRb.decompAccumOffset;

    // Search for null terminator in decompRb
    int nullIdx = -1;
    for (int i = inBlockOffset; i < decompRb.length; i++) {
      if (decompRb[i] == 0) {
        nullIdx = i;
        break;
      }
    }

    if (nullIdx != -1) {
      final slice = decompRb.sublist(inBlockOffset, nullIdx);
      return encoding == 'UTF-16LE'
          ? _decodeUtf16Le(slice)
          : utf8.decode(slice, allowMalformed: true);
    }

    // Spans across record block boundary
    final builder = BytesBuilder();
    builder.add(decompRb.sublist(inBlockOffset));

    int nextIdx = targetRbIdx + 1;
    while (nextIdx < _recordBlocks.length) {
      final nextDecomp = _getRecordBlock(nextIdx);
      int term = -1;
      for (int i = 0; i < nextDecomp.length; i++) {
        if (nextDecomp[i] == 0) {
          term = i;
          break;
        }
      }
      if (term != -1) {
        builder.add(nextDecomp.sublist(0, term));
        break;
      } else {
        builder.add(nextDecomp);
        nextIdx++;
      }
    }

    final bytes = builder.toBytes();
    return encoding == 'UTF-16LE'
        ? _decodeUtf16Le(bytes)
        : utf8.decode(bytes, allowMalformed: true);
  }

  void close() {
    _recordBlockCache.clear();
    _recordBlockLru.clear();
    _raf.closeSync();
  }

  static String _decodeUtf16Le(List<int> bytes) {
    final buffer = StringBuffer();
    for (int i = 0; i < bytes.length - 1; i += 2) {
      final code = bytes[i] | (bytes[i + 1] << 8);
      buffer.writeCharCode(code);
    }
    return buffer.toString();
  }
}
