import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../core/api.dart';
import '../core/models.dart';
import '../core/wave_math.dart';

/// Measured envelopes are saved beside the real music cache, inside its
/// origin/account namespace. They remain usable offline without inventing data.
class WaveformStore extends ChangeNotifier {
  final WaveApi api;
  Directory? _directory;
  final _envelopes = <String, AudioEnvelope>{};
  final _requests = <String, Future<void>>{};
  int _generation = 0;
  bool _disposed = false;
  WaveformStore(this.api);
  AudioEnvelope envelopeFor(String? id) =>
      _envelopes[id] ?? const AudioEnvelope();
  void open(Directory directory) {
    _generation++;
    _directory = directory;
    _envelopes.clear();
    _requests.clear();
  }

  String _filename(String id) =>
      '${base64Url.encode(utf8.encode(id)).replaceAll('=', '')}.wave.json';
  Future<void> load(String id) async {
    if (_disposed || _directory == null || _envelopes.containsKey(id)) return;
    if (_requests.containsKey(id)) {
      await _requests[id];
      return;
    }
    final generation = _generation,
        token = api.token,
        origin = api.server,
        directory = _directory!;
    bool same() =>
        !_disposed &&
        generation == _generation &&
        token == api.token &&
        origin == api.server;
    final operation = () async {
      AudioEnvelope measured = const AudioEnvelope();
      final file = File(p.join(directory.path, _filename(id)));
      try {
        if (await file.exists()) {
          measured = AudioEnvelope.fromJson(
            object(jsonDecode(await file.readAsString())),
          );
        }
        if (!measured.available) {
          measured = AudioEnvelope.fromJson(
            await api.call('/api/tracks/${Uri.encodeComponent(id)}/waveform'),
          );
          if (measured.available && same()) {
            final temporary = File('${file.path}.tmp');
            await temporary.writeAsString(
              jsonEncode(measured.toJson()),
              flush: true,
            );
            if (!same()) {
              if (await temporary.exists()) await temporary.delete();
              return;
            }
            await temporary.rename(file.path);
          }
        }
      } catch (_) {
        /* The decorative field simply stays at rest when unavailable. */
      }
      if (!same()) return;
      _envelopes[id] = measured;
      notifyListeners();
    }();
    _requests[id] = operation;
    try {
      await operation;
    } finally {
      if (identical(_requests[id], operation)) _requests.remove(id);
    }
  }

  Future<void> clear() async {
    _generation++;
    _envelopes.clear();
    _requests.clear();
    final directory = _directory;
    if (directory != null && await directory.exists()) {
      for (final file in directory.listSync().whereType<File>()) {
        if (file.path.endsWith('.wave.json') ||
            file.path.endsWith('.wave.json.tmp')) {
          await file.delete();
        }
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
