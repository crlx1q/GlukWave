import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// The HTML's local filtered-noise rain, rendered as real PCM rather than a
/// network track. It has its own player and mixes with the music player.
Uint8List rainPcm({int sampleRate = 22050, int seconds = 8}) {
  final count = sampleRate * seconds;
  final random = math.Random(36);
  final noise = List<double>.generate(
    count,
    (_) => random.nextDouble() * .04 - .02,
  );
  final bytes = Uint8List(44 + count * 2), header = ByteData.sublistView(bytes);
  void label(int at, String text) =>
      bytes.setRange(at, at + text.length, text.codeUnits);
  label(0, 'RIFF');
  header.setUint32(4, bytes.length - 8, Endian.little);
  label(8, 'WAVE');
  label(12, 'fmt ');
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little);
  header.setUint16(22, 1, Endian.little);
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, sampleRate * 2, Endian.little);
  header.setUint16(32, 2, Endian.little);
  header.setUint16(34, 16, Endian.little);
  label(36, 'data');
  header.setUint32(40, count * 2, Endian.little);
  var brown = 0.0, filtered = 0.0;
  // Settle the filter with the same periodic input before saving its cycle.
  // This avoids a discontinuity when the loop repeats.
  for (var pass = 0; pass < 3; pass++) {
    for (var i = 0; i < count; i++) {
      brown = (brown + noise[i]) / 1.02;
      filtered += (brown * 3.5 - filtered) * .28;
      if (pass == 2) {
        header.setInt16(
          44 + i * 2,
          (filtered.clamp(-1, 1) * 32767).round(),
          Endian.little,
        );
      }
    }
  }
  return bytes;
}

class RainAmbience {
  AudioPlayer? _player;
  AudioPlayer get player => _player ??= AudioPlayer();
  Future<void>? _prepared;
  int _revision = 0;
  bool _disposed = false;
  Future<void> _prepare() async {
    final file = File(
      p.join((await getTemporaryDirectory()).path, 'glukwave-rain-v1.wav'),
    );
    if (!await file.exists()) await file.writeAsBytes(rainPcm(), flush: true);
    if (_disposed) return;
    await player.setFilePath(file.path);
    await player.setLoopMode(LoopMode.one);
  }

  Future<void> setLevel(double level) async {
    final revision = ++_revision;
    if (_disposed) return;
    if (level <= 0) {
      await _player?.pause();
      return;
    }
    try {
      await (_prepared ??= _prepare());
    } catch (_) {
      _prepared = null;
      rethrow;
    }
    if (_disposed || revision != _revision) return;
    await player.setVolume(level.clamp(0, 1) * .6);
    unawaited(player.play().catchError((Object _) {}));
  }

  Future<void> dispose() async {
    _disposed = true;
    _revision++;
    await _player?.dispose();
  }
}
