import 'package:flutter_test/flutter_test.dart';
import 'package:local_dict/core/audio/edge_token.dart';

void main() {
  test('the token reproduces the captured handshake', () {
    // Vector captured from Edge 155 on the wire (2026-10-13, window starting
    // 10:40:00Z). The algorithm is only right if this matches byte for byte.
    final token =
        secMsGec(DateTime.fromMillisecondsSinceEpoch(1791888000 * 1000));
    expect(
      token,
      '492D7694A183A45E-56E821F95D4579C5B7C7E33DC7303FF379EC36D510213555'
      'BBBB9EB17EF15876',
    );
    expect(token, matches(RegExp(r'^[0-9A-F]{16}-[0-9A-F]{64}$')));
  });

  test('the token is stable inside a five-minute window and changes after', () {
    final base = DateTime.fromMillisecondsSinceEpoch(1791888000 * 1000);
    final later = base.add(const Duration(minutes: 4, seconds: 30));
    final next = base.add(const Duration(minutes: 5, seconds: 10));
    expect(secMsGec(later), secMsGec(base),
        reason: 'the window is five minutes wide');
    expect(secMsGec(next), isNot(secMsGec(base)));
  });
}
