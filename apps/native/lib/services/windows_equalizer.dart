import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import '../core/equalizer.dart';
import 'windows_mpv_player.dart';
import 'windows_dsp.dart';

/// The stock plugin keeps its mpv player private. This platform adapter uses
/// the same pinned implementation with one explicit native DSP operation.
class WaveWindowsAudio extends JustAudioPlatform {
  final players = <String, WindowsDspOutput>{};
  static WaveWindowsAudio? active;
  static void register() {
    final platform = WaveWindowsAudio();
    active = platform;
    JustAudioPlatform.instance = platform;
  }

  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async {
    if (players.containsKey(request.id)) {
      throw StateError('Player already exists');
    }
    final player = WaveMpvPlayer(request.id);
    players[request.id] = player;
    await player.ready();
    return player;
  }

  Future<void> apply(WaveEqualizer value, String? sourceUri) async {
    // Match the music URI so the independent rain player stays untouched.
    final outputs = players.values
        .where((p) => sourceUri != null && p.sourceUri == sourceUri)
        .toList();
    if (outputs.isEmpty) throw StateError('Music output not initialized');
    await Future.wait(
      outputs.map(
        (p) => p.applyEqualizer(value.enabled, value.preamp, value.bands),
      ),
    );
  }

  @override
  Future<DisposePlayerResponse> disposePlayer(
    DisposePlayerRequest request,
  ) async {
    final player = players.remove(request.id);
    if (player != null) await player.release();
    return DisposePlayerResponse();
  }

  @override
  Future<DisposeAllPlayersResponse> disposeAllPlayers(
    DisposeAllPlayersRequest request,
  ) async {
    final outputs = players.values.toList();
    players.clear();
    await Future.wait(outputs.map((p) => p.release()));
    return DisposeAllPlayersResponse();
  }
}
