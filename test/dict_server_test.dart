import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import '../server/dict_server.dart';

Uint8List _encodeUtf16Le(String value) {
  final out = BytesBuilder(copy: false);
  for (final unit in value.codeUnits) {
    out.addByte(unit & 0xFF);
    out.addByte((unit >> 8) & 0xFF);
  }
  return out.toBytes();
}

Uint8List _u16Be(int value) =>
    Uint8List(2)..buffer.asByteData().setUint16(0, value, Endian.big);

Uint8List _u32Be(int value) =>
    Uint8List(4)..buffer.asByteData().setUint32(0, value, Endian.big);

Uint8List _u64Be(int value) =>
    Uint8List(8)..buffer.asByteData().setUint64(0, value, Endian.big);

Uint8List _buildSimpleMdict({
  required List<({int offset, String key})> keys,
  required Uint8List recordPayload,
}) {
  final out = BytesBuilder(copy: false);
  final headerBytes = _encodeUtf16Le('<Dictionary Encoding="UTF-16LE"/>');
  out.add(_u32Be(headerBytes.length));
  out.add(headerBytes);
  out.add(const [0, 0, 0, 0]);

  final kbPayload = BytesBuilder(copy: false);
  for (final entry in keys) {
    kbPayload.add(_u64Be(entry.offset));
    kbPayload.add(_encodeUtf16Le(entry.key));
    kbPayload.add(const [0, 0]);
  }
  final decompKb = kbPayload.toBytes();
  final wrappedKb = Uint8List.fromList([
    0, 0, 0, 0,
    0, 0, 0, 0,
    ...decompKb,
  ]);

  final kbMeta = BytesBuilder(copy: false)
    ..add(_u64Be(keys.length))
    ..add(_u16Be(keys.first.key.length))
    ..add(_encodeUtf16Le(keys.first.key))
    ..add(const [0, 0])
    ..add(_u16Be(keys.last.key.length))
    ..add(_encodeUtf16Le(keys.last.key))
    ..add(const [0, 0])
    ..add(_u64Be(wrappedKb.length))
    ..add(_u64Be(decompKb.length));
  final decompKbInfo = kbMeta.toBytes();
  final compKbInfo = Uint8List.fromList([
    2, 0, 0, 0,
    0, 0, 0, 0,
    ...zlib.encode(decompKbInfo),
  ]);

  out.add(_u64Be(1));
  out.add(_u64Be(keys.length));
  out.add(_u64Be(decompKbInfo.length));
  out.add(_u64Be(compKbInfo.length));
  out.add(_u64Be(decompKb.length));
  out.add(const [0, 0, 0, 0]);
  out.add(compKbInfo);
  out.add(wrappedKb);

  final wrappedRb = Uint8List.fromList([
    0, 0, 0, 0,
    0, 0, 0, 0,
    ...recordPayload,
  ]);
  final recInfo = BytesBuilder(copy: false)
    ..add(_u64Be(wrappedRb.length))
    ..add(_u64Be(recordPayload.length));
  final recInfoBytes = recInfo.toBytes();
  out.add(_u64Be(1));
  out.add(_u64Be(keys.length));
  out.add(_u64Be(recInfoBytes.length));
  out.add(_u64Be(recordPayload.length));
  out.add(recInfoBytes);
  out.add(wrappedRb);

  return out.toBytes();
}

void main() {
  group('DictServer security & robustness', () {
    late Directory tempDir;
    late DictServer dictServer;
    late HttpServer httpServer;
    late HttpClient client;
    late Uri baseUri;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('dict_server_audit_');
      final mdxPayload = _buildSimpleMdict(
        keys: [(offset: 0, key: 'hello')],
        recordPayload:
            Uint8List.fromList([..._encodeUtf16Le('greeting'), 0, 0]),
      );
      final mddPayload = _buildSimpleMdict(
        keys: [(offset: 0, key: r'\a.spx')],
        recordPayload: Uint8List.fromList([10, 20, 30, 40]),
      );

      File('${tempDir.path}${Platform.pathSeparator}测试词典一.mdx')
          .writeAsBytesSync(mdxPayload);
      File('${tempDir.path}${Platform.pathSeparator}测试词典一.mdd')
          .writeAsBytesSync(mddPayload);
      File('${tempDir.path}${Platform.pathSeparator}测试词典二.mdx')
          .writeAsBytesSync(mdxPayload);

      dictServer = DictServer();
      await dictServer.scan([tempDir.path]);
      httpServer = await shelf_io.serve(
        dictServer.router.call,
        InternetAddress.loopbackIPv4,
        0,
      );
      baseUri = Uri.parse('http://127.0.0.1:${httpServer.port}');
      client = HttpClient();
    });

    tearDown(() async {
      client.close(force: true);
      await httpServer.close(force: true);
      await dictServer.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    Future<(int status, Uint8List body)> sendRequest(
      String method,
      String pathAndQuery, {
      Map<String, String> headers = const {},
      List<int>? bodyBytes,
    }) async {
      final req = await client.openUrl(method, baseUri.resolve(pathAndQuery));
      headers.forEach(req.headers.set);
      if (bodyBytes != null) {
        req.contentLength = bodyBytes.length;
        req.add(bodyBytes);
      }
      final res = await req.close();
      final bytes = await res.fold<BytesBuilder>(
        BytesBuilder(copy: false),
        (b, chunk) => b..add(chunk),
      );
      return (res.statusCode, bytes.takeBytes());
    }

    test('slugs non-ASCII filenames uniquely and redacts filesystem paths',
        () async {
      final ids = dictServer.dictionaries.map((d) => d.info.id).toList();
      expect(ids.length, 2);
      expect(ids.toSet().length, 2);

      final (status, raw) = await sendRequest('GET', '/api/dictionaries');
      expect(status, 200);
      final decoded = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
      final items = decoded['dictionaries'] as List<dynamic>;
      expect(items.length, 2);
      for (final item in items.cast<Map<String, dynamic>>()) {
        final mdxPath = item['mdx_path'] as String;
        expect(mdxPath.contains('/'), isFalse);
        expect(mdxPath.contains('\\'), isFalse);
      }
    });

    test('gates forwarded admin endpoints and rejects oversized POST bodies',
        () async {
      final (forwardedStatus, _) = await sendRequest(
        'POST',
        '/api/reload',
        headers: const {'x-forwarded-for': '203.0.113.9'},
      );
      expect(forwardedStatus, 403);

      final (loopbackStatus, _) = await sendRequest('POST', '/api/reload');
      expect(loopbackStatus, 200);

      final firstId = dictServer.dictionaries.first.info.id;
      final (tooBigStatus, _) = await sendRequest(
        'POST',
        '/api/dictionaries/$firstId/enabled',
        bodyBytes: List<int>.filled(9000, 0x20),
      );
      expect(tooBigStatus, 413);

      final (toggleStatus, _) = await sendRequest(
        'POST',
        '/api/dictionaries/$firstId/enabled',
        bodyBytes: utf8.encode('{"enabled":false}'),
      );
      expect(toggleStatus, 200);
      expect(dictServer.dictionaries.first.info.isEnabled, isFalse);
    });

    test('handles valid and invalid Range headers cleanly on /api/audio',
        () async {
      final (fullStatus, fullBody) =
          await sendRequest('GET', '/api/audio?key=/a.spx');
      expect(fullStatus, 200);
      expect(fullBody, Uint8List.fromList([10, 20, 30, 40]));

      final (partialStatus, partialBody) = await sendRequest(
        'GET',
        '/api/audio?key=/a.spx',
        headers: const {'Range': 'bytes=0-1'},
      );
      expect(partialStatus, 206);
      expect(partialBody, Uint8List.fromList([10, 20]));

      final (badRangeStatus, _) = await sendRequest(
        'GET',
        '/api/audio?key=/a.spx',
        headers: const {'Range': 'bytes=abc-def'},
      );
      expect(badRangeStatus, 416);
    });

    test('serves /api/lexicon/info, /search, and /lookup from coca_learn.db',
        () async {
      final loaded =
          await dictServer.openLexicon('content/coca-ai/pack/coca_learn.db');
      expect(loaded, isTrue);

      final (infoStatus, infoRaw) =
          await sendRequest('GET', '/api/lexicon/info');
      expect(infoStatus, 200);
      final info = jsonDecode(utf8.decode(infoRaw)) as Map<String, dynamic>;
      expect(info['ready'], isTrue);
      expect(info['entryCount'], 53925);

      final (searchStatus, searchRaw) =
          await sendRequest('GET', '/api/lexicon/search?q=abandon&limit=10');
      expect(searchStatus, 200);
      final search = jsonDecode(utf8.decode(searchRaw)) as Map<String, dynamic>;
      final results = (search['results'] as List).cast<Map<String, dynamic>>();
      expect(results.first['word'], 'abandon');
      expect(results.first['frequencyBadge'], 'COCA #2275');

      final (lookupStatus, lookupRaw) =
          await sendRequest('GET', '/api/lexicon/lookup?word=behaviour');
      expect(lookupStatus, 200);
      final lookup = jsonDecode(utf8.decode(lookupRaw)) as Map<String, dynamic>;
      expect(lookup['found'], isTrue);
      final entry = lookup['entry'] as Map<String, dynamic>;
      expect(entry['word'], 'behavior');
      expect(entry['matchedFrom'], 'behaviour');

      await dictServer.close();
    });
  });
}
