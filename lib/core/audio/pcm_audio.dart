import 'dart:typed_data';

/// PCM the number module assembles itself, and the WAV container it hands to the
/// player.
///
/// Two engines build a sentence's audio here instead of asking a platform voice
/// to say it: splicing the module's own recorded words into one clip, and the
/// bundled Piper voice, which returns raw float samples. Both end up as a single
/// WAV buffer played once — no seam between words, and the same bytes on every
/// platform, so one set of tests covers all of them.
///
/// Everything is 16-bit little-endian mono, the format `assets/audio/numbers`
/// ships and the only format the writer emits.
class PcmClip {
  final Int16List samples;
  final int sampleRate;

  const PcmClip(this.samples, this.sampleRate);

  int get sampleCount => samples.length;

  Duration get duration =>
      Duration(microseconds: samples.length * 1000000 ~/ sampleRate);

  bool get isEmpty => samples.isEmpty;

  /// [duration] of silence, for the pause a comma in a phone number stands for.
  factory PcmClip.silence(Duration duration, int sampleRate) {
    final count = duration.inMicroseconds * sampleRate ~/ 1000000;
    return PcmClip(Int16List(count < 0 ? 0 : count), sampleRate);
  }

  @override
  String toString() => 'PcmClip(${samples.length} samples @ $sampleRate Hz, $duration)';
}

/// Reads the PCM out of a WAV file.
///
/// Only what [encodeWav] writes is understood — PCM, one channel, 16 bit — which
/// is exactly what the module's own clips are; anything else throws, because a
/// silently mis-read clip would play as noise.
PcmClip decodeWav(Uint8List bytes) {
  final header = ByteData.sublistView(bytes);
  if (bytes.length < 12 ||
      _tag(bytes, 0) != 'RIFF' ||
      _tag(bytes, 8) != 'WAVE') {
    throw const FormatException('Not a WAV file');
  }

  int? sampleRate;
  int? channels;
  int? bitsPerSample;
  int? format;
  Int16List? samples;

  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final id = _tag(bytes, offset);
    final size = header.getUint32(offset + 4, Endian.little);
    final body = offset + 8;
    if (id == 'fmt ') {
      format = header.getUint16(body, Endian.little);
      channels = header.getUint16(body + 2, Endian.little);
      sampleRate = header.getUint32(body + 4, Endian.little);
      bitsPerSample = header.getUint16(body + 14, Endian.little);
    } else if (id == 'data') {
      final end = body + size > bytes.length ? bytes.length : body + size;
      final usable = (end - body) - ((end - body) % 2);
      samples = Int16List(usable ~/ 2);
      for (var i = 0; i < samples.length; i++) {
        samples[i] = header.getInt16(body + i * 2, Endian.little);
      }
    }
    // Chunks are word aligned.
    offset = body + size + (size.isOdd ? 1 : 0);
  }

  if (format != 1 || channels != 1 || bitsPerSample != 16) {
    throw FormatException(
      'Only 16-bit mono PCM is supported (format $format, $channels channels, '
      '$bitsPerSample bits)',
    );
  }
  if (sampleRate == null || samples == null) {
    throw const FormatException('WAV file has no fmt/data chunk');
  }
  return PcmClip(samples, sampleRate);
}

/// Wraps [samples] in the 44-byte WAV header the player understands.
Uint8List encodeWav(Int16List samples, {required int sampleRate}) {
  final dataBytes = samples.length * 2;
  final out = ByteData(44 + dataBytes);
  _writeTag(out, 0, 'RIFF');
  out.setUint32(4, 36 + dataBytes, Endian.little);
  _writeTag(out, 8, 'WAVE');
  _writeTag(out, 12, 'fmt ');
  out.setUint32(16, 16, Endian.little); // PCM header size
  out.setUint16(20, 1, Endian.little); // PCM
  out.setUint16(22, 1, Endian.little); // mono
  out.setUint32(24, sampleRate, Endian.little);
  out.setUint32(28, sampleRate * 2, Endian.little); // byte rate
  out.setUint16(32, 2, Endian.little); // block align
  out.setUint16(34, 16, Endian.little); // bits per sample
  _writeTag(out, 36, 'data');
  out.setUint32(40, dataBytes, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    out.setInt16(44 + i * 2, samples[i], Endian.little);
  }
  return out.buffer.asUint8List();
}

/// Concatenates [clips] into one buffer, inserting `gaps[i]` after `clips[i]`.
///
/// This is what removes the seam a word-by-word playback has: the words of a
/// number become one clip, so the player starts the sound once and the space
/// between words is silence this code put there on purpose. Clips must share one
/// sample rate (the module's clips are all 24 kHz); the first one's rate is used
/// for any silence added.
PcmClip joinClips(List<PcmClip> clips, {List<Duration> gaps = const []}) {
  if (clips.isEmpty) return PcmClip(Int16List(0), 24000);

  final sampleRate = clips.first.sampleRate;
  var total = 0;
  final silences = <int>[];
  for (var i = 0; i < clips.length; i++) {
    total += clips[i].sampleCount;
    final gap = i < gaps.length
        ? PcmClip.silence(gaps[i], sampleRate).sampleCount
        : 0;
    silences.add(gap);
    total += gap;
  }

  final out = Int16List(total);
  var offset = 0;
  for (var i = 0; i < clips.length; i++) {
    out.setAll(offset, clips[i].samples);
    offset += clips[i].sampleCount + silences[i]; // Silence stays zero.
  }
  return PcmClip(out, sampleRate);
}

/// Converts the float samples a speech model returns into PCM, clamping to the
/// 16-bit range rather than letting a loud sample wrap around.
PcmClip fromFloat32(List<double> samples, int sampleRate) {
  final out = Int16List(samples.length);
  for (var i = 0; i < samples.length; i++) {
    final value = (samples[i] * 32767).round();
    out[i] = value > 32767 ? 32767 : (value < -32768 ? -32768 : value);
  }
  return PcmClip(out, sampleRate);
}

String _tag(Uint8List bytes, int offset) => String.fromCharCodes(
      bytes.sublist(offset, offset + 4),
    );

void _writeTag(ByteData out, int offset, String tag) {
  for (var i = 0; i < 4; i++) {
    out.setUint8(offset + i, tag.codeUnitAt(i));
  }
}
