import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_dict/core/mdx/mdx_record_scan.dart';

void main() {
  test('a UTF-16LE header is recognised instead of decoded as UTF-8', () {
    final header = Uint8List.fromList(
      utf8.encode('<Dictionary Encoding="UTF-16" Title="词典" />')
          .expand((b) => [b, 0])
          .toList(),
    );
    expect(looksUtf16Le(header), isTrue);

    // The same text as plain UTF-8 must keep taking the UTF-8 path.
    final ascii = Uint8List.fromList(utf8.encode('<Dictionary Encoding="UTF-8" />'));
    expect(looksUtf16Le(ascii), isFalse);

    // A BOM decides it outright, even before the density check.
    expect(
      looksUtf16Le(Uint8List.fromList([0xFF, 0xFE, 0x61, 0x00])),
      isTrue,
    );
  });

  test('a UTF-16LE record ends at two NUL bytes, not at the first one', () {
    // "ab" in UTF-16LE followed by the terminator and the next record.
    final block = Uint8List.fromList(
      [0x61, 0x00, 0x62, 0x00, 0x00, 0x00, 0x63, 0x00],
    );
    final term = findRecordTerminator(block, 0, utf16: true);
    expect(term, 4, reason: 'the first NUL is half of the letter "a"');
    expect(block.sublist(0, term), [0x61, 0x00, 0x62, 0x00]);

    // An odd start is aligned up: a UTF-16 record never begins mid-character.
    expect(findRecordTerminator(block, 1, utf16: true), 4);
    expect(findRecordTerminator(block, 4, utf16: true), 4);
  });

  test('a UTF-8 record still ends at the first NUL', () {
    final block = Uint8List.fromList(utf8.encode('hello\u0000world'));
    expect(findRecordTerminator(block, 0, utf16: false), 5);
  });
}
