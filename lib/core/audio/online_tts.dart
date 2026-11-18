import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'edge_socket.dart';
import 'edge_token.dart';
import 'speech_engine.dart';

/// The free, key-less online voices the app can read a line with.
///
/// All of them take a sentence and answer MP3, and none needs an account: that
/// is the whole selection criterion. Two live abroad (Edge's neural read-aloud
/// and Google's translate voice), two answer from inside China (有道, 百度),
/// so a blocked route has somewhere to go. `SpeechEngine` is the switch the
/// settings panel shows; this file is only how a line gets fetched.
/// Signature of [OnlineTts.synthesize], injectable into the speech provider.
typedef OnlineSynthesizer = Future<Uint8List?> Function(
  SpeechEngine engine, {
  required String text,
  required String accent,
  double rate,
  http.Client? client,
});

class OnlineTts {
  OnlineTts._();

  /// The Edge build a client declares. The service ignores the number; only
  /// the `2-` prefix matters, because it says which token format to expect.
  static const String chromiumVersion = '155.0.4283.45';

  /// Where [engine] reads a line of [text] with [accent] from.
  ///
  /// Null for the two local engines and for the ones that cannot be expressed
  /// as a GET.
  static Uri? urlFor(
    SpeechEngine engine, {
    required String text,
    required String accent,
    double rate = 1.0,
  }) {
    switch (engine) {
      case SpeechEngine.baidu:
        return Uri.parse('https://fanyi.baidu.com/gettts'
            '?lan=en&spd=${baiduSpeed(rate)}&source=web'
            '&text=${Uri.encodeComponent(text)}');
      case SpeechEngine.google:
        return Uri.parse('https://translate.google.com/translate_tts'
            '?ie=UTF-8&client=tw-ob&tl=${accent == 'uk' ? 'en-GB' : 'en'}'
            '&q=${Uri.encodeComponent(text)}');
      case SpeechEngine.edge:
      case SpeechEngine.kokoro:
      case SpeechEngine.system:
        return null;
    }
  }

  /// 百度's speed knob: `spd` runs 1 (slowest) to 7 (fastest); 8 and up answer
  /// an empty body, and 3 is the service's own pace.
  static int baiduSpeed(double rate) =>
      (1 + (rate.clamp(0.5, 2.0) - 0.5) * 4).round().clamp(1, 7);

  /// MP3 for [text], or null when the service did not answer with audio.
  ///
  /// One request per sentence, which is the unit the reader waits on; the
  /// caller prefetches the next ones while the current line sounds.
  static Future<Uint8List?> synthesize(
    SpeechEngine engine, {
    required String text,
    required String accent,
    double rate = 1.0,
    http.Client? client,
  }) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return Future<Uint8List?>.value(null);
    switch (engine) {
      case SpeechEngine.edge:
        return _edge(trimmed, accent: accent, rate: rate);
      case SpeechEngine.google:
        return _google(trimmed, accent: accent, client: client);
      case SpeechEngine.baidu:
        return _getWithRetry(
          urlFor(engine, text: trimmed, accent: accent, rate: rate)!,
          client: client,
        );
      case SpeechEngine.kokoro:
      case SpeechEngine.system:
        return Future<Uint8List?>.value(null);
    }
  }

  /// Whether [bytes] open like an audio stream rather than an error page.
  static bool looksLikeAudio(Uint8List bytes) {
    if (bytes.length < 512) return false;
    if (bytes.length > 3 &&
        bytes[0] == 0x49 &&
        bytes[1] == 0x44 &&
        bytes[2] == 0x33) {
      return true; // ID3
    }
    if (bytes[0] == 0xFF) return true; // MPEG frame sync
    if (bytes.length > 3 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46) {
      return true; // RIFF/WAV — some endpoints answer WAV
    }
    return false;
  }

  static Future<Uint8List?> _getWithRetry(
    Uri url, {
    http.Client? client,
    Map<String, String>? headers,
  }) async {
    final getter = client ?? http.Client();
    try {
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          final response = await getter
              .get(url, headers: headers)
              .timeout(const Duration(seconds: 5));
          if (response.statusCode == 200 && looksLikeAudio(response.bodyBytes)) {
            return response.bodyBytes;
          }
        } on Exception {
          // Retried once: these endpoints drop a connection now and then, and a
          // second try is cheaper than a silent line.
        }
        await Future<void>.delayed(const Duration(milliseconds: 220));
      }
      return null;
    } finally {
      if (client == null) getter.close();
    }
  }

  /// Google's endpoint caps a request near 200 characters; a longer sentence is
  /// fetched in pieces and joined — MP3 frames are self-delimiting, so the
  /// pieces play as one clip.
  static Future<Uint8List?> _google(
    String text, {
    required String accent,
    http.Client? client,
  }) async {
    const limit = 170;
    final pieces = <String>[];
    if (text.length <= limit) {
      pieces.add(text);
    } else {
      final buffer = StringBuffer();
      for (final word in text.split(' ')) {
        if (buffer.isNotEmpty && buffer.length + word.length + 1 > limit) {
          pieces.add(buffer.toString());
          buffer.clear();
        }
        if (buffer.isNotEmpty) buffer.write(' ');
        buffer.write(word);
      }
      if (buffer.isNotEmpty) pieces.add(buffer.toString());
    }
    final audio = BytesBuilder(copy: false);
    for (final piece in pieces) {
      final bytes = await _getWithRetry(
        urlFor(SpeechEngine.google, text: piece, accent: accent)!,
        client: client,
        headers: const {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'},
      );
      if (bytes == null) return null;
      audio.add(bytes);
    }
    return audio.takeBytes();
  }

  /// The Edge read-aloud websocket: config, one SSML request, binary MP3 back.
  static Future<Uint8List?> _edge(
    String text, {
    required String accent,
    required double rate,
  }) async {
    final requestId = _requestId();
    final voice = accent == 'uk' ? 'en-GB-SoniaNeural' : 'en-US-AriaNeural';
    final language = accent == 'uk' ? 'en-GB' : 'en-US';
    final percent = ((rate.clamp(0.5, 2.0) - 1.0) * 100).round();
    final uri = Uri.parse(
      'wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1'
      '?TrustedClientToken=$edgeTrustedToken'
      '&Sec-MS-GEC=${secMsGec()}'
      '&Sec-MS-GEC-Version=2-$chromiumVersion'
      '&ConnectionId=$requestId',
    );

    WebSocketChannel? channel;
    StreamSubscription<dynamic>? subscription;
    final done = Completer<void>();
    final audio = BytesBuilder(copy: false);
    try {
      channel = await connectEdgeVoice(uri);
      await channel.ready.timeout(const Duration(seconds: 6));
      subscription = channel.stream.listen(
        (frame) {
          if (frame is String) {
            if (frame.contains('Path:turn.end') && !done.isCompleted) {
              done.complete();
            }
            return;
          }
          if (frame is List<int>) {
            final bytes = Uint8List.fromList(frame);
            if (bytes.length < 2) return;
            final header = (bytes[0] << 8) | bytes[1];
            final start = 2 + header;
            if (start < bytes.length) audio.add(bytes.sublist(start));
          }
        },
        onDone: () {
          if (!done.isCompleted) done.complete();
        },
        onError: (Object _) {
          if (!done.isCompleted) done.complete();
        },
        cancelOnError: true,
      );

      channel.sink.add('X-Timestamp:${_timestamp()}\r\n'
          'Content-Type:application/json; charset=utf-8\r\n'
          'Path:speech.config\r\n\r\n'
          '{"context":{"synthesis":{"audio":{"metadataoptions":'
          '{"sentenceBoundaryEnabled":"false","wordBoundaryEnabled":"false"},'
          '"outputFormat":"audio-24khz-48kbitrate-mono-mp3"}}}}');

      channel.sink.add('X-RequestId:$requestId\r\n'
          'Content-Type:application/ssml+xml\r\n'
          'X-Timestamp:${_timestamp()}\r\n'
          'Path:ssml\r\n\r\n'
          "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' "
          "xml:lang='$language'><voice name='$voice'>"
          "<prosody pitch='+0Hz' rate='${percent >= 0 ? '+' : ''}$percent%' "
          "volume='+0%'>${_escapeXml(text)}</prosody></voice></speak>");

      await done.future.timeout(const Duration(seconds: 10));
      final bytes = audio.takeBytes();
      return looksLikeAudio(bytes) ? bytes : null;
    } on Exception {
      return null;
    } finally {
      await subscription?.cancel();
      await channel?.sink.close();
    }
  }

  static String _escapeXml(String text) => text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  /// `Wed Nov 18 2026 20:15:00 GMT+0000 (Coordinated Universal Time)`, the
  /// shape the read-aloud service expects in `X-Timestamp`.
  static String _timestamp([DateTime? now]) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug',
      'Sep', 'Oct', 'Nov', 'Dec'];
    final time = (now ?? DateTime.now()).toUtc();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${days[time.weekday - 1]} ${months[time.month - 1]} '
        '${two(time.day)} ${time.year} '
        '${two(time.hour)}:${two(time.minute)}:${two(time.second)} '
        'GMT+0000 (Coordinated Universal Time)';
  }

  static final Random _random = Random();
  static String _requestId() {
    final buffer = StringBuffer();
    for (var i = 0; i < 32; i++) {
      buffer.write(_random.nextInt(16).toRadixString(16));
    }
    return buffer.toString();
  }
}

/// The browser identity Edge's reader presents.
const String edgeUserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
    'AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/143.0.0.0 Safari/537.36 Edg/143.0.0.0';

/// The handshake headers Edge's reader sends beside that user agent.
const Map<String, String> edgeHandshakeHeaders = {
  'Pragma': 'no-cache',
  'Cache-Control': 'no-cache',
  'Origin': 'chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold',
  'Accept-Encoding': 'gzip, deflate, br',
  'Accept-Language': 'en-US,en;q=0.9',
};
