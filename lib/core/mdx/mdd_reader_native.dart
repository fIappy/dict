import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'mdict_crypto.dart';

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
  final RandomAccessFile _raf;
  final List<MddKeyBlockMeta> _keyBlocks = [];
  final List<MddRecordBlockMeta> _recordBlocks = [];

  // LRU cache for decompressed record blocks
  final Map<int, Uint8List> _recordBlockCache = {};
  final List<int> _recordBlockLru = [];
  static const int _maxCacheBlocks = 16;

  MddReader._(
    this._raf, {
    required this.filePath,
  });
  static Future<MddReader> open(String path) async {
    final file = File(path);
    if (!file.existsSync()) {
      throw FileSystemException('MDD file not found', path);
    }
    final raf = file.openSync();
    try {
      final reader = MddReader._(raf, filePath: path);
      reader._init();
      return reader;
    } catch (e) {
      raf.closeSync();
      rethrow;
    }
  }

  void _init() {
    final hlen = ByteData.sublistView(_raf.readSync(4)).getUint32(0, Endian.big);
    final headerBytes = _raf.readSync(hlen);
    _raf.readSync(4); // checksum
    String header;
    try {
      header = utf8.decode(headerBytes);
    } catch (_) {
      // Older MDD files (LDOCE5++ …) write the header as UTF-16LE.
      header = _utf16LeDecode(headerBytes);
    }
    // The audio archive is encrypted the same way the text one is.
    final encryption = MdictCrypto.encryptionFlag(header);

    final kinfoBuf = ByteData.sublistView(_raf.readSync(40));
    final numKeyBlocks = kinfoBuf.getUint64(0, Endian.big);
    _raf.readSync(4); // checksum
    final compKbInfoSize = kinfoBuf.getUint64(24, Endian.big);
    kinfoBuf.getUint64(32, Endian.big); // keyBlockSize

    final compKbInfo = Uint8List.fromList(_raf.readSync(compKbInfoSize));
    final decompKbInfo = MdictCrypto.decodeKeyBlockInfo(compKbInfo, encryption);
    final bd = ByteData.sublistView(decompKbInfo);

    int pos = 0;
    int curKbPos = _raf.positionSync();
    for (int i = 0; i < numKeyBlocks; i++) {
      final count = bd.getUint64(pos, Endian.big); pos += 8;
      final k1Len = bd.getUint16(pos, Endian.big); pos += 2;
      final k1 = _utf16LeDecode(decompKbInfo.sublist(pos, pos + k1Len * 2)); pos += k1Len * 2 + 2;
      final k2Len = bd.getUint16(pos, Endian.big); pos += 2;
      final k2 = _utf16LeDecode(decompKbInfo.sublist(pos, pos + k2Len * 2)); pos += k2Len * 2 + 2;
      final compSize = bd.getUint64(pos, Endian.big); pos += 8;
      final decompSize = bd.getUint64(pos, Endian.big); pos += 8;

      _keyBlocks.add(MddKeyBlockMeta(
        count: count,
        firstKey: k1,
        lastKey: k2,
        compSize: compSize,
        decompSize: decompSize,
        filePos: curKbPos,
      ));
      curKbPos += compSize;
    }

    // Record blocks
    _raf.setPositionSync(curKbPos);
    final rinfoBuf = ByteData.sublistView(_raf.readSync(32));
    final numRecordBlocks = rinfoBuf.getUint64(0, Endian.big);
    final recInfoSize = rinfoBuf.getUint64(16, Endian.big);

    final recInfoBytes = _raf.readSync(recInfoSize);
    final rbd = ByteData.sublistView(recInfoBytes);
    int rpos = 0;
    int curRbPos = _raf.positionSync();
    int accumDecomp = 0;

    for (int i = 0; i < numRecordBlocks; i++) {
      final compSize = rbd.getUint64(rpos, Endian.big); rpos += 8;
      final decompSize = rbd.getUint64(rpos, Endian.big); rpos += 8;
      _recordBlocks.add(MddRecordBlockMeta(
        compSize: compSize,
        decompSize: decompSize,
        filePos: curRbPos,
        decompAccumOffset: accumDecomp,
      ));
      curRbPos += compSize;
      accumDecomp += decompSize;
    }
  }

  Uint8List? getResource(String rawKey) {
    var key = rawKey.replaceAll('/', '\\');
    if (!key.startsWith('\\')) key = '\\$key';
    final target = key.toLowerCase();

    // 1. Binary search target key block
    int low = 0, high = _keyBlocks.length - 1;
    MddKeyBlockMeta? targetBlock;
    while (low <= high) {
      int mid = (low + high) ~/ 2;
      final kb = _keyBlocks[mid];
      if (target.compareTo(kb.firstKey.toLowerCase()) < 0) {
        high = mid - 1;
      } else if (target.compareTo(kb.lastKey.toLowerCase()) > 0) {
        low = mid + 1;
      } else {
        targetBlock = kb;
        break;
      }
    }

    if (targetBlock == null) return null;

    // 2. Read target key block
    _raf.setPositionSync(targetBlock.filePos);
    final kbData = Uint8List.fromList(_raf.readSync(targetBlock.compSize));
    final decompKb = MdictCrypto.decodeBlock(kbData);

    int kp = 0;
    int? foundOffset;
    int? nextOffset;
    for (int i = 0; i < targetBlock.count; i++) {
      final off = ByteData.sublistView(decompKb).getUint64(kp, Endian.big);
      kp += 8;
      int term = -1;
      for (int p = kp; p < decompKb.length - 1; p += 2) {
        if (decompKb[p] == 0 && decompKb[p + 1] == 0) {
          term = p;
          break;
        }
      }
      if (term == -1) term = decompKb.length;
      final k = _utf16LeDecode(decompKb.sublist(kp, term));
      kp = term + 2;

      if (foundOffset != null) {
        nextOffset = off;
        break;
      }
      if (k.toLowerCase() == target) {
        foundOffset = off;
      }
    }

    if (foundOffset == null) return null;

    // 3. Find record block
    int rlow = 0, rhigh = _recordBlocks.length - 1;
    int targetRbIdx = -1;
    while (rlow <= rhigh) {
      int mid = (rlow + rhigh) ~/ 2;
      final rb = _recordBlocks[mid];
      if (foundOffset >= rb.decompAccumOffset &&
          foundOffset < rb.decompAccumOffset + rb.decompSize) {
        targetRbIdx = mid;
        break;
      } else if (foundOffset < rb.decompAccumOffset) {
        rhigh = mid - 1;
      } else {
        rlow = mid + 1;
      }
    }

    if (targetRbIdx == -1) return null;

    final targetRb = _recordBlocks[targetRbIdx];
    final decompRb = _getRecordBlock(targetRbIdx);
    final inBlockOffset = foundOffset - targetRb.decompAccumOffset;

    int length;
    if (nextOffset != null && nextOffset > foundOffset) {
      length = nextOffset - foundOffset;
    } else {
      length = decompRb.length - inBlockOffset;
    }

    if (inBlockOffset + length <= decompRb.length) {
      return Uint8List.fromList(decompRb.sublist(inBlockOffset, inBlockOffset + length));
    } else {
      // Spans across record block
      final result = BytesBuilder();
      result.add(decompRb.sublist(inBlockOffset));
      int remaining = length - (decompRb.length - inBlockOffset);
      int nextRbIdx = targetRbIdx + 1;
      while (remaining > 0 && nextRbIdx < _recordBlocks.length) {
        final ndecomp = _getRecordBlock(nextRbIdx);
        final take = remaining < ndecomp.length ? remaining : ndecomp.length;
        result.add(ndecomp.sublist(0, take));
        remaining -= take;
        nextRbIdx++;
      }
      return result.toBytes();
    }
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
    final decomp = MdictCrypto.decodeBlock(compData);

    if (_recordBlockCache.length >= _maxCacheBlocks) {
      final oldest = _recordBlockLru.removeAt(0);
      _recordBlockCache.remove(oldest);
    }
    _recordBlockCache[blockIndex] = decomp;
    _recordBlockLru.add(blockIndex);

    return decomp;
  }

  void close() {
    _recordBlockCache.clear();
    _recordBlockLru.clear();
    _raf.closeSync();
  }

  static String _utf16LeDecode(List<int> bytes) {
    final buffer = StringBuffer();
    for (int i = 0; i < bytes.length - 1; i += 2) {
      final code = bytes[i] | (bytes[i + 1] << 8);
      buffer.writeCharCode(code);
    }
    return buffer.toString();
  }
}
