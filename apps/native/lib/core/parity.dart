import 'package:flutter/foundation.dart';
import 'api.dart';
import 'models.dart';

/// Account-scoped discovery and social state. Failed optional services never
/// replace the existing library or imply that an empty response was successful.
class WaveParity extends ChangeNotifier {
  final WaveApi api;
  WaveParity(this.api);
  Json taste = {}, recommendations = {}, friends = {};
  String? error;
  bool loading = false, _disposed = false;
  int _generation = 0;
  int _friendsGeneration = 0, _tasteGeneration = 0;
  Future<void> _tasteWrites = Future.value();
  Future<void> refreshFriends() async {
    final generation = ++_friendsGeneration,
        token = api.token,
        origin = api.server;
    final result = await _optional('/api/friends');
    if (_disposed ||
        generation != _friendsGeneration ||
        token != api.token ||
        origin != api.server) {
      return;
    }
    friends = result;
    notifyListeners();
  }

  Future<void> refreshTaste() async {
    final generation = ++_tasteGeneration,
        token = api.token,
        origin = api.server;
    final result = await _optional('/api/taste');
    if (_disposed ||
        generation != _tasteGeneration ||
        token != api.token ||
        origin != api.server) {
      return;
    }
    taste = result;
    notifyListeners();
  }

  Future<void> load({String mood = 'personal'}) async {
    final generation = ++_generation, token = api.token, origin = api.server;
    final friendsGeneration = ++_friendsGeneration,
        tasteGeneration = ++_tasteGeneration;
    loading = true;
    error = null;
    notifyListeners();
    final responses = await Future.wait([
      _optional('/api/taste'),
      _optional('/api/recommendations', query: {'mood': mood}),
      _optional('/api/friends'),
    ]);
    if (_disposed ||
        generation != _generation ||
        token != api.token ||
        origin != api.server) {
      return;
    }
    if (tasteGeneration == _tasteGeneration) taste = responses[0];
    recommendations = responses[1];
    if (friendsGeneration == _friendsGeneration) friends = responses[2];
    error = responses.map((r) => r['_error']).whereType<String>().firstOrNull;
    loading = false;
    notifyListeners();
  }

  Future<Json> _optional(String path, {Json? query}) async {
    try {
      return await api.call(path, query: query);
    } catch (e) {
      return {'_error': e.toString()};
    }
  }

  List<WaveTrack> get tracks =>
      objects(recommendations['tracks']).map(WaveTrack.new).toList();
  Json get preference => object(taste['taste']);
  Future<void> saveTaste(Json patch) {
    final token = api.token, origin = api.server;
    final operation = _tasteWrites.catchError((_) {}).then((_) async {
      if (_disposed || token != api.token || origin != api.server) return;
      try {
        final result = await api.call('/api/taste', method: 'PUT', data: patch);
        if (_disposed || token != api.token || origin != api.server) return;
        _tasteGeneration++;
        taste = result;
        error = null;
        notifyListeners();
      } catch (e) {
        if (!_disposed && token == api.token && origin == api.server) {
          error = e.toString();
          notifyListeners();
        }
        rethrow;
      }
    });
    _tasteWrites = operation;
    return operation;
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}

/// mpv's lavfi chain uses peaking filters at the same ten logarithmic centers
/// as Android/web. Numbers are finite and bounded before entering native DSP.
String windowsEqualizerFilter(bool enabled, double preamp, List<double> bands) {
  if (!enabled) return '';
  const frequencies = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000];
  double gain(double v) => v.isFinite ? v.clamp(-12, 12).toDouble() : 0;
  final stages = <String>[];
  for (var i = 0; i < frequencies.length; i++) {
    final value = i < bands.length ? gain(bands[i]) : 0.0;
    stages.add(
      'equalizer=f=${frequencies[i]}:t=o:w=1:g=${value.toStringAsFixed(2)}',
    );
  }
  // The pinned audio build includes equalizer, but strips volume/aresample.
  // Convert with mpv's native format filter so integer PCM is also supported.
  // Preamp is applied through mpv software volume at the output boundary.
  return 'format=format=floatp,lavfi=[${stages.join(',')}]';
}
