import 'dart:typed_data';

/// A WAV file of 16-bit mono PCM [samples] (little-endian bytes), which the
/// server takes as audio evidence.
Uint8List wavFromPcm16(Uint8List samples, {int sampleRate = 16000}) {
  final header = ByteData(44)
    ..setUint32(0, 0x52494646) // "RIFF"
    ..setUint32(4, 36 + samples.length, Endian.little)
    ..setUint32(8, 0x57415645) // "WAVE"
    ..setUint32(12, 0x666d7420) // "fmt "
    ..setUint32(16, 16, Endian.little) // PCM format chunk size
    ..setUint16(20, 1, Endian.little) // PCM
    ..setUint16(22, 1, Endian.little) // mono
    ..setUint32(24, sampleRate, Endian.little)
    ..setUint32(28, sampleRate * 2, Endian.little) // bytes per second
    ..setUint16(32, 2, Endian.little) // bytes per frame
    ..setUint16(34, 16, Endian.little) // bits per sample
    ..setUint32(36, 0x64617461) // "data"
    ..setUint32(40, samples.length, Endian.little);
  return (BytesBuilder(copy: false)
        ..add(header.buffer.asUint8List())
        ..add(samples))
      .takeBytes();
}
