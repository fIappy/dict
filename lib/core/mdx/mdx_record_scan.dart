import 'dart:math' as math;
import 'dart:typed_data';

/// Whether [bytes] look like UTF-16LE rather than UTF-8.
///
/// MDict v2 headers are ASCII XML; in UTF-16LE that means a NUL in every second
/// byte. A BOM decides it outright.
bool looksUtf16Le(Uint8List bytes) {
  if (bytes.length < 4 || bytes.length.isOdd) return false;
  if (bytes[0] == 0xFF && bytes[1] == 0xFE) return true;
  final sample = math.min(bytes.length, 200);
  var zeros = 0;
  for (var i = 1; i < sample; i += 2) {
    if (bytes[i] == 0) zeros++;
  }
  return zeros > sample ~/ 4;
}

/// Offset of the record terminator in [bytes] at or after [from], or -1.
///
/// A UTF-16LE record ends with two NUL bytes on an even boundary; scanning for a
/// single NUL there would stop at the second byte of the first character.
int findRecordTerminator(
  Uint8List bytes,
  int from, {
  required bool utf16,
  bool align = true,
}) {
  if (utf16) {
    var i = from;
    if (align && i.isOdd) i++;
    for (; i + 1 < bytes.length; i += 2) {
      if (bytes[i] == 0 && bytes[i + 1] == 0) return i;
    }
    return -1;
  }
  for (var i = from; i < bytes.length; i++) {
    if (bytes[i] == 0) return i;
  }
  return -1;
}
