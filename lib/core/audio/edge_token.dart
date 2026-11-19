/// The `Sec-MS-GEC` token Microsoft's Edge read-aloud endpoint signs requests
/// with (format 2, mandatory since October 2026).
///
/// It is a digest of `<ticks><trusted token>` — where ticks are 100 ns
/// intervals since 1601 rounded down to a five-minute window — rendered as
/// `<16 hex>-<64 hex>`: a modified 64-bit hash the service calls CS64, then a
/// SHA-256 whose initial state is itself derived from the clock string.
///
/// Ported from the reference implementation in `rany2/edge-tts` (`drm.py`),
/// which was reconstructed from a browser handshake. Kept apart from the
/// speaker so the arithmetic can be checked against the captured vectors
/// without a network.
library;

import 'dart:convert';

/// The public client token Edge itself sends. It names the product, not a user.
const String edgeTrustedToken = '6A5AA1D4EAFF4E9FB37E23D68491D6F4';

/// Seconds between the Windows epoch (1601) and the Unix one.
const int _windowsEpoch = 11644473600;

const int _u32 = 0xFFFFFFFF;

/// Rotate a 32-bit word right.
///
/// The reference implementation rotates by shifting a 64-bit `value * (2^32+1)`
/// right; that trick needs 64-bit integers, which dart2js does not have. This
/// is the same rotation expressed in 32-bit terms, so the browser computes the
/// token exactly like the desktop build.
int _rotr(int value, int count) {
  final v = value & _u32;
  return ((v >>> count) | (v << (32 - count))) & _u32;
}

int _rot16(int value) {
  final v = value & _u32;
  return ((v << 16) | (v >> 16)) & _u32;
}

const List<int> _sha256Initial = [
  0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A,
  0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19,
];

const List<int> _sha256State = [
  0xFD9FBEA2, 0x91243CE7, 0xBE499094, 0xCD2E1E0A,
  0x6C006F49, 0x04BD35AB, 0xFEB0A7E4, 0x03EFFBD2,
];

const List<int> _sha256Schedule = [
  0xEB24BF9E, 0x1558691F, 0xA0C09EE2, 0x0CFA32BA, 0xA622EE8C, 0xD1DD9491,
  0xC0DD25A0, 0xF9E70AB6, 0xF0C31573, 0x7058CE4E, 0x7188E606, 0x00E5AB33,
  0xD258B060, 0x72766564,
];

const List<int> _sha256RoundConstants = [
  0x428A2F98, 0x71374491, 0xB5C0FBCF, 0xE9B5DBA5, 0x3956C25B, 0x59F111F1,
  0x923F82A4, 0xAB1C5ED5, 0xD807AA98, 0x12835B01, 0x243185BE, 0x550C7DC3,
  0x72BE5D74, 0x80DEB1FE, 0x9BDC06A7, 0xC19BF174, 0xE49B69C1, 0xEFBE4786,
  0x0FC19DC6, 0x240CA1CC, 0x2DE92C6F, 0x4A7484AA, 0x5CB0A9DC, 0x76F988DA,
  0x983E5152, 0xA831C66D, 0xB00327C8, 0xBF597FC7, 0xC6E00BF3, 0xD5A79147,
  0x06CA6351, 0x14292967, 0x27B70A85, 0x2E1B2138, 0x4D2C6DFC, 0x53380D13,
  0x650A7354, 0x766A0ABB, 0x81C2C92E, 0x92722C85, 0xA2BFE8A1, 0xA81A664B,
  0xC24B8B70, 0xC76C51A3, 0xD192E819, 0xD6990624, 0xF40E3585, 0x106AA070,
  0x19A4C116, 0x1E376C08, 0x2748774C, 0x34B0BCB5, 0x391C0CB3, 0x4ED8AA4A,
  0x5B9CCA4F, 0x682E6FF3, 0x748F82EE, 0x78A5636F, 0x84C87814, 0x8CC70208,
  0x90BEFFFA, 0xA4506CEB, 0xBEF9A3F7, 0xC67178F2,
];

const int _sha256Adjustment = 0xC9DC06A7;
final List<int> _sha256BlockConstants = [
  ..._sha256RoundConstants.sublist(0, 14),
  _sha256Adjustment,
  ..._sha256RoundConstants.sublist(15),
];

const int _sigma0Adjustment = 0x059C0B80;
const int _sigma1Adjustment = 0x000B92C0;

const List<(int, int)> _cs64Coefficients = [
  (0xE82E91B1, 0xB32700D0),
  (0x44DE24C6, 0x88DFF51D),
  (0x3BEB65BC, 0x29514038),
  (0xC89C5933, 0xB328CBDF),
  (0x8D1EC211, 0xD405B4D5),
  (0x314EF5D5, 0x26E55F3C),
  (0xE92491B1, 0x607801C6),
  (0xF0A5B9D5, 0x82B2C1FB),
  (0x06064CF3, 0xFA51A3DA),
  (0xDA79FA60, 0x207CC464),
  (0xBED20560, 0x3C3C74F3),
  (0x89F9C9F8, 0xD2D14B61),
  (0x35FA38C6, 0xBB04A2C1),
  (0xCB49E3C6, 0xC5626167),
];

const int _cs64Factor = 0x82893933;
const int _cs64Adjustment0 = 0xF2F90B1A;
const int _cs64Adjustment1 = 0x0B1A0000;

int _sigma0(int value) =>
    ((value >> 7) ^ (value << 25) ^ (value >> 18) ^ (value << 14) ^ (value >> 3)) &
        _u32;

int _sigma1(int value) =>
    ((value >> 17) ^ (value << 15) ^ (value >> 19) ^ (value << 13) ^ (value >> 10)) &
        _u32;

List<int> _wordsLe4Even(List<int> data) {
  final padded = <int>[...data];
  while (padded.length % 4 != 0) {
    padded.add(0);
  }
  final words = <int>[];
  for (var i = 0; i < padded.length; i += 4) {
    words.add(padded[i] |
        (padded[i + 1] << 8) |
        (padded[i + 2] << 16) |
        (padded[i + 3] << 24));
  }
  if (words.length.isOdd) words.add(0);
  return words;
}

List<int> _sha256Rounds(List<int> state, List<int> words,
    {int firstRound = 0}) {
  var a = state[0], b = state[1], c = state[2], d = state[3];
  var e = state[4], f = state[5], g = state[6], h = state[7];
  final constants =
      firstRound == 14 ? _sha256BlockConstants : _sha256RoundConstants;
  final aligned = ((firstRound + 7) ~/ 8) * 8 < 64 ? ((firstRound + 7) ~/ 8) * 8 : 64;

  for (var index = firstRound; index < aligned; index++) {
    final t1 = (h +
            (_rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25)) +
            (g ^ (e & (f ^ g))) +
            constants[index] +
            words[index]) &
        _u32;
    final t2 = ((_rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22)) +
            ((a & b) | (c & (a | b)))) &
        _u32;
    // Python assigns a..h in one step: (t1+t2, a, b, c, d+t1, e, f, g).
    final nextA = (t1 + t2) & _u32;
    final oldA = a, oldB = b, oldC = c, oldD = d, oldE = e, oldF = f, oldG = g;
    a = nextA;
    b = oldA;
    c = oldB;
    d = oldC;
    e = (oldD + t1) & _u32;
    f = oldE;
    g = oldF;
    h = oldG;
  }

  for (var index = aligned; index < 64; index += 8) {
    var t1 = (h +
            (_rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25)) +
            (g ^ (e & (f ^ g))) +
            constants[index] +
            words[index]) &
        _u32;
    d = (d + t1) & _u32;
    h = (t1 +
            (_rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22)) +
            ((a & b) | (c & (a | b)))) &
        _u32;

    t1 = (g +
            (_rotr(d, 6) ^ _rotr(d, 11) ^ _rotr(d, 25)) +
            (f ^ (d & (e ^ f))) +
            constants[index + 1] +
            words[index + 1]) &
        _u32;
    c = (c + t1) & _u32;
    g = (t1 +
            (_rotr(h, 2) ^ _rotr(h, 13) ^ _rotr(h, 22)) +
            ((h & a) | (b & (h | a)))) &
        _u32;

    t1 = (f +
            (_rotr(c, 6) ^ _rotr(c, 11) ^ _rotr(c, 25)) +
            (e ^ (c & (d ^ e))) +
            constants[index + 2] +
            words[index + 2]) &
        _u32;
    b = (b + t1) & _u32;
    f = (t1 +
            (_rotr(g, 2) ^ _rotr(g, 13) ^ _rotr(g, 22)) +
            ((g & h) | (a & (g | h)))) &
        _u32;

    t1 = (e +
            (_rotr(b, 6) ^ _rotr(b, 11) ^ _rotr(b, 25)) +
            (d ^ (b & (c ^ d))) +
            constants[index + 3] +
            words[index + 3]) &
        _u32;
    a = (a + t1) & _u32;
    e = (t1 +
            (_rotr(f, 2) ^ _rotr(f, 13) ^ _rotr(f, 22)) +
            ((f & g) | (h & (f | g)))) &
        _u32;

    t1 = (d +
            (_rotr(a, 6) ^ _rotr(a, 11) ^ _rotr(a, 25)) +
            (c ^ (a & (b ^ c))) +
            constants[index + 4] +
            words[index + 4]) &
        _u32;
    h = (h + t1) & _u32;
    d = (t1 +
            (_rotr(e, 2) ^ _rotr(e, 13) ^ _rotr(e, 22)) +
            ((e & f) | (g & (e | f)))) &
        _u32;

    t1 = (c +
            (_rotr(h, 6) ^ _rotr(h, 11) ^ _rotr(h, 25)) +
            (b ^ (h & (a ^ b))) +
            constants[index + 5] +
            words[index + 5]) &
        _u32;
    g = (g + t1) & _u32;
    c = (t1 +
            (_rotr(d, 2) ^ _rotr(d, 13) ^ _rotr(d, 22)) +
            ((d & e) | (f & (d | e)))) &
        _u32;

    t1 = (b +
            (_rotr(g, 6) ^ _rotr(g, 11) ^ _rotr(g, 25)) +
            (a ^ (g & (h ^ a))) +
            constants[index + 6] +
            words[index + 6]) &
        _u32;
    f = (f + t1) & _u32;
    b = (t1 +
            (_rotr(c, 2) ^ _rotr(c, 13) ^ _rotr(c, 22)) +
            ((c & d) | (e & (c | d)))) &
        _u32;

    t1 = (a +
            (_rotr(f, 6) ^ _rotr(f, 11) ^ _rotr(f, 25)) +
            (h ^ (f & (g ^ h))) +
            constants[index + 7] +
            words[index + 7]) &
        _u32;
    e = (e + t1) & _u32;
    a = (t1 +
            (_rotr(b, 2) ^ _rotr(b, 13) ^ _rotr(b, 22)) +
            ((b & c) | (d & (b | c)))) &
        _u32;
  }
  return [a, b, c, d, e, f, g, h];
}

void _expandSha256Schedule(List<int> words, [int firstWord = 16]) {
  for (var index = firstWord; index < 64; index++) {
    final x = words[index - 2];
    final y = words[index - 15];
    final sigma1 = (x >> 17) ^ (x << 15) ^ (x >> 19) ^ (x << 13) ^ (x >> 10);
    final sigma0 = (y >> 7) ^ (y << 25) ^ (y >> 18) ^ (y << 14) ^ (y >> 3);
    words.add((sigma1 + words[index - 7] + sigma0 + words[index - 16]) & _u32);
  }
}

List<int> _sha256Init(List<int> data) {
  final words = List<int>.filled(14, 0, growable: true);
  words.add((data[0] << 16) | (data[1] << 8) | data[2]);
  words.add((data[3] << 24) | (data[4] << 16) | (data[5] << 8) | data[6]);
  for (var index = 16; index < 30; index++) {
    var value = _sha256Schedule[index - 16];
    if (index - 2 >= 14) {
      value += (index == 16
          ? _sigma1(words[index - 2]) ^ _sigma1Adjustment
          : _sigma1(words[index - 2])) &
          _u32;
    }
    if (index - 7 >= 14) value += words[index - 7];
    if (index - 15 >= 14) {
      value += (index == 29
          ? _sigma0(words[index - 15]) ^ _sigma0Adjustment
          : _sigma0(words[index - 15])) &
          _u32;
    }
    words.add(value & _u32);
  }
  words.add((_sigma1(words[28]) +
          words[23] +
          _sigma0(words[15]) +
          words[14] +
          _sha256Adjustment -
          _sha256RoundConstants[14]) &
      _u32);
  _expandSha256Schedule(words, 31);
  final working = _sha256Rounds(_sha256State, words, firstRound: 14);
  return [
    for (var i = 0; i < 8; i++) (_sha256Initial[i] + working[i]) & _u32,
  ];
}

List<int> _sha256Digest(List<int> data) {
  final length = 57 + data.length;
  final pad = (55 - length) % 64;
  final padded = <int>[...data.sublist(7), 0x80, ...List<int>.filled(pad, 0)];
  final bits = length * 8;
  for (var shift = 56; shift >= 0; shift -= 8) {
    padded.add((bits >> shift) & 0xFF);
  }
  var state = _sha256Init(data.sublist(0, 7));
  for (var offset = 0; offset < padded.length; offset += 64) {
    final words = <int>[
      for (var i = 0; i < 16; i++)
        (padded[offset + i * 4] << 24) |
            (padded[offset + i * 4 + 1] << 16) |
            (padded[offset + i * 4 + 2] << 8) |
            padded[offset + i * 4 + 3],
    ];
    _expandSha256Schedule(words);
    final working = _sha256Rounds(state, words);
    state = [for (var i = 0; i < 8; i++) (state[i] + working[i]) & _u32];
  }
  final out = <int>[];
  for (final word in state) {
    out
      ..add((word >> 24) & 0xFF)
      ..add((word >> 16) & 0xFF)
      ..add((word >> 8) & 0xFF)
      ..add(word & 0xFF);
  }
  return out;
}

(int, int) _cs64Digest(List<int> data, List<int> digest) {
  var keyA = digest[0] | (digest[1] << 8) | (digest[2] << 16) | (digest[3] << 24);
  var keyB = digest[4] | (digest[5] << 8) | (digest[6] << 16) | (digest[7] << 24);
  keyA |= 1;
  keyB |= 1;
  final factors = [
    (keyA * _cs64Factor) & _u32,
    (keyB * _cs64Factor) & _u32,
  ];
  final terms = <int>[];
  final offsets = <int>[];
  for (var index = 0; index < _cs64Coefficients.length; index++) {
    final (coefficient, offset) = _cs64Coefficients[index];
    terms.add((coefficient * factors[index % 2]) & _u32);
    offsets.add(offset);
  }
  final words = _wordsLe4Even([0, ...data]);
  for (var index = 0; index < words.length; index++) {
    final word = words[index];
    var term = word * (index.isEven ? keyA : keyB);
    var offset = _rot16(word) * (index.isEven ? 0xEF0569FB : 0xC31713DB);
    if (index == 0) {
      term += _cs64Adjustment0 * factors[0];
      offset += _cs64Adjustment1;
    }
    terms.add(term & _u32);
    offsets.add(offset & _u32);
  }

  var swapAcc = 0;
  var swapLast = 0;
  var state = 0;
  var acc = 0;
  for (var index = 0; index < terms.length; index += 2) {
    final x = terms[index];
    final y = terms[index + 1];
    var t = _rot16((offsets[index] + x) & _u32);
    var q = (t * 0x76F50F34) & _u32;
    swapAcc += (_rot16(q) * 0xC3EFEA97 + q) & _u32;
    t = _rot16((offsets[index + 1] + y) & _u32);
    q = (t * 0x1881CE3C) & _u32;
    swapLast = (_rot16(q) * 0x35BD1EC9 + q) & _u32;
    swapAcc = (swapAcc + swapLast) & _u32;

    state = (state * keyA + x) & _u32;
    state = (_rot16(state) * 0xCF98B111) & _u32;
    state = (_rot16(state) * 0x87085B9F) & _u32;
    state = (_rot16(state) * 0x12CEB96D) & _u32;
    state = (_rot16(state) * 0x257E1D83) & _u32;
    acc += state;
    var t2 = (state * keyB + y) & _u32;
    t2 = (_rot16(t2) * 0xA27416F5) & _u32;
    t2 = (_rot16(t2) * 0xD38396FF) & _u32;
    state = (_rot16((_rot16(t2) * 0x7C932B89) & _u32) * 0xBFA49F69) & _u32;
    acc = (acc + state) & _u32;
  }
  return (swapLast ^ state, swapAcc ^ acc);
}

String _hexLe(int value) => [
      value & 0xFF,
      (value >> 8) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 24) & 0xFF,
    ].map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();

String _hexOfBytes(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();

/// The token for [now] (defaults to the current time).
String secMsGec([DateTime? now]) {
  final seconds = (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
  var ticks = seconds + _windowsEpoch;
  ticks -= ticks % 300;
  // 100-nanosecond intervals since 1601, written the way the service signs it.
  final stored = ticks * 10000000;
  final data = ascii.encode('$stored$edgeTrustedToken');
  final digest = _sha256Digest(data);
  final (cs64a, cs64b) = _cs64Digest(data, digest);
  // The pair goes out little-endian, the same way the reference packs it.
  return '${_hexLe(cs64a)}${_hexLe(cs64b)}-${_hexOfBytes(digest)}';
}
