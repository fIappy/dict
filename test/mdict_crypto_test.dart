import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_dict/core/mdx/mdict_crypto.dart';

String hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  test('RIPEMD-128 matches the published test vectors', () {
    // The mode's reference vectors (Bosselaers), which is what MDict keys its
    // stream cipher with — a wrong hash would decrypt into zlib garbage.
    expect(hex(MdictCrypto.ripemd128(const [])), 'cdf26213a150dc3ecb610f18f6b38b46');
    expect(hex(MdictCrypto.ripemd128(utf8.encode('a'))),
        '86be7afa339d0fc7cfc785e72f578d33');
    expect(hex(MdictCrypto.ripemd128(utf8.encode('abc'))),
        'c14a12199c66e4ba84636b0f69144c77');
    expect(hex(MdictCrypto.ripemd128(utf8.encode('message digest'))),
        '9e327b3d6e523062afc1132d7df9d1b8');
  });

  test('RIPEMD-128 handles a multi-block message', () {
    // 80 bytes: two blocks, so the padding and the length field are exercised.
    final digest = MdictCrypto.ripemd128(utf8.encode('a' * 80));
    expect(digest, hasLength(16));
    expect(hex(MdictCrypto.ripemd128(utf8.encode('a' * 80))), hex(digest),
        reason: 'deterministic');
    expect(hex(MdictCrypto.ripemd128(utf8.encode('b' * 80))), isNot(hex(digest)));
  });

  /// The reference writer's counterpart, so the test has both directions.
  Uint8List fastEncrypt(Uint8List data, Uint8List key) {
    final out = Uint8List(data.length);
    var previous = 0x36;
    for (var i = 0; i < data.length; i++) {
      final t = data[i] ^ previous ^ (i & 0xFF) ^ key[i % key.length];
      out[i] = ((t << 4) | (t >> 4)) & 0xFF;
      previous = out[i];
    }
    return out;
  }

  test('fast decrypt inverts the writer with the same key', () {
    final key = MdictCrypto.ripemd128(utf8.encode('key'));
    final plain = Uint8List.fromList(List.generate(64, (i) => (i * 7) & 0xFF));
    final cipher = fastEncrypt(plain, key);
    expect(cipher, isNot(plain));
    expect(MdictCrypto.fastDecrypt(cipher, key), plain);
  });

  test('an encrypted key-block index decrypts back to its plain form', () {
    // What MDict writes when the dictionary is built with registration: the
    // 4-byte info word and the adler32 stay, the zlib body is stream-ciphered.
    final plain = utf8.encode('key-block index payload ' * 8);
    final body = zlib.encode(plain);
    final checksum = [0xba, 0x01, 0xe3, 0x49];
    final key = MdictCrypto.ripemd128([...checksum, 0x95, 0x36, 0x00, 0x00]);
    final encrypted = Uint8List.fromList([
      0x02, 0x00, 0x00, 0x00,
      ...checksum,
      ...fastEncrypt(Uint8List.fromList(body), key),
    ]);

    expect(MdictCrypto.decodeKeyBlockInfo(encrypted, 2), plain);
    // Without the flag the same bytes are not zlib: the reader must not guess.
    expect(() => MdictCrypto.decodeKeyBlockInfo(encrypted, 0), throwsA(isA<Exception>()));
  });

  test('the Encrypted attribute is read from the header', () {
    expect(MdictCrypto.encryptionFlag('<Dictionary Encrypted="No" />'), 0);
    expect(MdictCrypto.encryptionFlag('<Dictionary Encrypted="2" />'), 2);
    expect(MdictCrypto.encryptionFlag('<Dictionary Encrypted="1" />'), 1);
    expect(MdictCrypto.encryptionFlag('<Dictionary Encrypted="Yes" />'), 1);
    expect(MdictCrypto.encryptionFlag('<Dictionary Title="x" />'), 0);
  });
}
