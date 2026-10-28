import 'dart:io';
import 'dart:typed_data';

/// Decryption for the "Encrypted=2" MDict builds.
///
/// MDict can ship a dictionary with its key-block index encrypted: the header
/// says `Encrypted="2"` and the block that describes the key blocks is a
/// stream cipher over what would otherwise be zlib data. Big dictionaries built
/// with MDict's registration option (LDOCE5++, 牛津高阶第 10 版 …) are all like
/// this, so a reader that ignores the flag opens none of them: it hands cipher
/// text to `zlib.decode` and gets `incorrect header check`.
///
/// The scheme, as implemented by the reference readers:
/// * key = RIPEMD-128 of the block's 4 checksum bytes plus `0x3695` (LE);
/// * body = "fast decrypt": swap the nibbles of each byte, then XOR it with the
///   previous **cipher** byte, the byte index, and the key.
class MdictCrypto {
  MdictCrypto._();

  /// Header `Encrypted` values: 1 = record blocks, 2 = key-block index.
  static const int keyInfoEncrypted = 0x02;

  /// Reads the `Encrypted` attribute off a header: `No` / `Yes` / a number.
  static int encryptionFlag(String header) {
    final match = RegExp(
      'Encrypted\\s*=\\s*["\']([^"\']*)["\']',
      caseSensitive: false,
    ).firstMatch(header);
    final raw = match?.group(1)?.trim().toLowerCase() ?? '';
    if (raw.isEmpty || raw == 'no' || raw == '0') return 0;
    if (raw == 'yes') return 1;
    return int.tryParse(raw) ?? 0;
  }

  /// The key-block index, decompressed — decrypted first when [encryption] has
  /// [keyInfoEncrypted] set.
  static Uint8List decodeKeyBlockInfo(Uint8List compressed, int encryption) {
    if (encryption & keyInfoEncrypted == 0) {
      return Uint8List.fromList(zlib.decode(compressed.sublist(8)));
    }
    final key = ripemd128(Uint8List.fromList([
      ...compressed.sublist(4, 8),
      0x95,
      0x36,
      0x00,
      0x00,
    ]));
    final body = fastDecrypt(
      Uint8List.fromList(compressed.sublist(8)),
      key,
    );
    return Uint8List.fromList(zlib.decode(body));
  }

  /// One key block or record block: 4-byte info word (compression + encryption),
  /// 4-byte checksum, then the payload.
  ///
  /// The per-block encryption key is the block's own checksum, so a dictionary
  /// needs no passcode for this part.
  static Uint8List decodeBlock(Uint8List raw) {
    final header = ByteData.sublistView(raw);
    final info = header.getUint32(0, Endian.little);
    final compression = info & 0xF;
    final encryption = (info >> 4) & 0xF;
    final encryptionSize = (info >> 8) & 0xFF;

    var payload = Uint8List.fromList(raw.sublist(8));
    if (encryption == 1) {
      final key = ripemd128(Uint8List.fromList(raw.sublist(4, 8)));
      final head = fastDecrypt(
        Uint8List.fromList(payload.sublist(0, encryptionSize)),
        key,
      );
      payload = Uint8List.fromList([...head, ...payload.sublist(encryptionSize)]);
    } else if (encryption != 0) {
      throw UnsupportedError(
        'MDict block encryption method $encryption is not supported',
      );
    }

    switch (compression) {
      case 0:
        return payload;
      case 2:
        return Uint8List.fromList(zlib.decode(payload));
      default:
        throw UnsupportedError(
          'MDict compression method $compression is not supported',
        );
    }
  }

  /// MDict's "fast decrypt": nibbles swapped, then XORed with the previous
  /// cipher byte, the position, and the key.
  static Uint8List fastDecrypt(Uint8List data, Uint8List key) {
    final out = Uint8List(data.length);
    var previous = 0x36;
    for (var i = 0; i < data.length; i++) {
      final byte = data[i];
      final swapped = ((byte >> 4) | (byte << 4)) & 0xFF;
      out[i] = swapped ^ previous ^ (i & 0xFF) ^ key[i % key.length];
      previous = byte;
    }
    return out;
  }

  /// Message-word order for the left line: identity, then the MD4-style
  /// shuffle, one row per round.
  static const List<int> _leftOrder = [
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
    7, 4, 13, 1, 10, 6, 15, 3, 12, 0, 9, 5, 2, 14, 11, 8,
    3, 10, 14, 4, 9, 15, 8, 1, 2, 7, 0, 6, 13, 11, 5, 12,
    1, 9, 11, 10, 0, 8, 12, 4, 13, 3, 7, 15, 14, 5, 6, 2,
  ];

  static const List<int> _rightOrder1 = [
    5, 14, 7, 0, 9, 2, 11, 4, 13, 6, 15, 8, 1, 10, 3, 12,
  ];
  static const List<int> _rightOrder2 = [
    6, 11, 3, 7, 0, 13, 5, 10, 14, 15, 8, 12, 4, 9, 1, 2,
  ];
  static const List<int> _rightOrder3 = [
    15, 5, 1, 3, 7, 14, 6, 9, 11, 8, 12, 2, 10, 0, 4, 13,
  ];
  static const List<int> _rightOrder4 = [
    8, 6, 4, 1, 3, 11, 15, 0, 5, 12, 2, 13, 9, 7, 10, 14,
  ];

  static const List<int> _leftShift = [
    11, 14, 15, 12, 5, 8, 7, 9, 11, 13, 14, 15, 6, 7, 9, 8,
    7, 6, 8, 13, 11, 9, 7, 15, 7, 12, 15, 9, 11, 7, 13, 12,
    11, 13, 6, 7, 14, 9, 13, 15, 14, 8, 13, 6, 5, 12, 7, 5,
    11, 12, 14, 15, 14, 15, 9, 8, 9, 14, 5, 6, 8, 6, 5, 12,
  ];

  static const List<int> _rightShift = [
    8, 9, 9, 11, 13, 15, 15, 5, 7, 7, 8, 11, 14, 14, 12, 6,
    9, 13, 15, 7, 12, 8, 9, 11, 7, 7, 12, 7, 6, 15, 13, 11,
    9, 7, 15, 11, 8, 6, 6, 14, 12, 13, 5, 14, 13, 13, 7, 5,
    15, 5, 8, 11, 14, 14, 6, 14, 6, 9, 12, 9, 12, 5, 15, 8,
  ];

  static const List<int> _leftConstant = [
    0x00000000, 0x5A827999, 0x6ED9EBA1, 0x8F1BBCDC,
  ];
  static const List<int> _rightConstant = [
    0x50A28BE6, 0x5C4DD124, 0x6D703EF3, 0x00000000,
  ];

  static const int _mask = 0xFFFFFFFF;

  static int _f(int round, int x, int y, int z) {
    switch (round) {
      case 0:
        return x ^ y ^ z;
      case 1:
        return (x & y) | (~x & z);
      case 2:
        return (x | ~y) ^ z;
      default:
        return (x & z) | (y & ~z);
    }
  }

  static int _rotate(int value, int bits) =>
      ((value << bits) | (value >> (32 - bits))) & _mask;

  /// RIPEMD-128, used by MDict to key the stream cipher above.
  static Uint8List ripemd128(List<int> message) {
    final padded = <int>[...message, 0x80];
    while (padded.length % 64 != 56) {
      padded.add(0);
    }
    final length = ByteData(8)..setUint64(0, message.length * 8, Endian.little);
    padded.addAll(length.buffer.asUint8List());
    final bytes = Uint8List.fromList(padded);

    var h0 = 0x67452301, h1 = 0xEFCDAB89, h2 = 0x98BADCFE, h3 = 0x10325476;

    for (var offset = 0; offset < bytes.length; offset += 64) {
      final words = ByteData.sublistView(bytes, offset, offset + 64);
      final x = [for (var i = 0; i < 16; i++) words.getUint32(i * 4, Endian.little)];

      var al = h0, bl = h1, cl = h2, dl = h3;
      var ar = h0, br = h1, cr = h2, dr = h3;

      // RIPEMD-128 steps a four-word state, rotating which word is updated:
      // A, D, C, B, A, … — no fifth register (that is RIPEMD-160).
      for (var j = 0; j < 64; j++) {
        final round = j ~/ 16;
        final index = j % 16;
        final rightIndex = switch (round) {
          0 => _rightOrder1[index],
          1 => _rightOrder2[index],
          2 => _rightOrder3[index],
          _ => _rightOrder4[index],
        };

        al = _rotate(
          (al + _f(round, bl, cl, dl) + x[_leftOrder[j]] + _leftConstant[round]) &
              _mask,
          _leftShift[j],
        );
        final rotateLeft = dl;
        dl = cl;
        cl = bl;
        bl = al;
        al = rotateLeft;

        ar = _rotate(
          (ar + _f(3 - round, br, cr, dr) + x[rightIndex] + _rightConstant[round]) &
              _mask,
          _rightShift[j],
        );
        final rotateRight = dr;
        dr = cr;
        cr = br;
        br = ar;
        ar = rotateRight;
      }

      final t = (h1 + cl + dr) & _mask;
      h1 = (h2 + dl + ar) & _mask;
      h2 = (h3 + al + br) & _mask;
      h3 = (h0 + bl + cr) & _mask;
      h0 = t;
    }

    final out = ByteData(16)
      ..setUint32(0, h0, Endian.little)
      ..setUint32(4, h1, Endian.little)
      ..setUint32(8, h2, Endian.little)
      ..setUint32(12, h3, Endian.little);
    return out.buffer.asUint8List();
  }
}
