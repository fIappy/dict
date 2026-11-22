import 'dart:io';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'online_tts.dart';

final HttpClient _sharedClient = HttpClient()
  ..userAgent = edgeUserAgent
  ..connectionTimeout = const Duration(seconds: 6);

/// Opens the read-aloud socket with the handshake Edge itself sends.
///
/// `customClient` is not optional: `WebSocket.connect` sends its own user agent
/// (`Dart/3.13 (dart:io)`), and a `User-Agent` passed in `headers` is appended
/// to that one with a comma — a header the service answers with 403.
Future<WebSocketChannel> connectEdgeVoice(Uri uri) async {
  // Ownership of [socket] transfers immediately to IOWebSocketChannel below.
  // ignore: close_sinks
  final socket = await WebSocket.connect(
    uri.toString(),
    headers: edgeHandshakeHeaders,
    compression: CompressionOptions.compressionDefault,
    customClient: _sharedClient,
  ).timeout(const Duration(seconds: 6));
  return IOWebSocketChannel(socket);
}
