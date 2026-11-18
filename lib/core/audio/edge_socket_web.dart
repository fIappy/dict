import 'package:web_socket_channel/web_socket_channel.dart';

/// Opens the read-aloud socket. A browser sets its own handshake headers; the
/// service checks the token, not the client's identity.
Future<WebSocketChannel> connectEdgeVoice(Uri uri) async =>
    WebSocketChannel.connect(uri);
