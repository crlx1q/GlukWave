import 'package:flutter/foundation.dart';

import 'data.dart';
import 'models.dart';
import 'soundcloud.dart';
import 'synth.dart';

class AppState extends ChangeNotifier {
  AppState({SoundCloudService? soundCloudService})
      : _soundCloud = soundCloudService ?? const SoundCloudService();

  final SoundCloudService _soundCloud;
  final SynthController synth = SynthController();

  final List<Track> _tracks = List<Track>.from(demoTracks);
  int _currentIndex = 0;
  bool _isPlaying = false;
  bool _lofiMode = false;

  List<Track> get tracks => List<Track>.unmodifiable(_tracks);
  int get currentIndex => _currentIndex;
  Track get currentTrack => _tracks[_currentIndex];
  bool get isPlaying => _isPlaying;
  bool get lofiMode => _lofiMode;
  Uri? get currentSoundCloudUri => _soundCloud.resolveTrackUri(currentTrack);

  void selectTrack(int index) {
    if (index < 0 || index >= _tracks.length) return;
    _currentIndex = index;
    notifyListeners();
  }

  void togglePlay() {
    _isPlaying = !_isPlaying;
    if (_isPlaying) {
      synth.start();
    } else {
      synth.stop();
    }
    notifyListeners();
  }

  void nextTrack() {
    _currentIndex = (_currentIndex + 1) % _tracks.length;
    notifyListeners();
  }

  void previousTrack() {
    _currentIndex = (_currentIndex - 1) < 0 ? _tracks.length - 1 : _currentIndex - 1;
    notifyListeners();
  }

  void toggleLofiMode() {
    _lofiMode = !_lofiMode;
    synth.setLofi(_lofiMode);
    notifyListeners();
  }

  @override
  void dispose() {
    synth.dispose();
    super.dispose();
  }
}
