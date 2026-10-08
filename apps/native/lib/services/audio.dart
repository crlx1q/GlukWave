import '../l10n/wave_localizations.dart';
import 'dart:async';
import 'dart:math';
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import '../core/api.dart';
import '../core/models.dart';
import '../core/equalizer.dart';
import 'cache.dart';

class WaveAudioHandler extends BaseAudioHandler {
  final WaveApi api;
  final MusicCache cache;
  // Native players send authorization headers directly. Android does not need an
  // insecure loopback proxy in release builds.
  late final AudioPlayer player;
  final AndroidEqualizer? _equalizer = Platform.isAndroid
      ? AndroidEqualizer()
      : null;
  final AndroidLoudnessEnhancer? _preamp = Platform.isAndroid
      ? AndroidLoudnessEnhancer()
      : null;
  WaveEqualizer _processing = const WaveEqualizer();
  double _volume = 1, _rate = 1;
  bool _roomSpeed = false;
  int _processingRevision = 0;
  Future<void> _processingWrites = Future.value();
  String equalizerStatus = Platform.isAndroid ? 'waiting' : 'unsupported';
  int hardwareBandCount = 0;
  double get volume => _volume;
  bool get equalizerSupported => _equalizer != null;
  List<WaveTrack> tracks = [];
  WaveTrack? current;
  AudioServiceRepeatMode repeat = AudioServiceRepeatMode.none;
  bool shuffle = false;
  bool autoCache = true;
  int _index = -1, _loadRevision = 0;
  bool _advancing = false;
  final _random = Random();
  final List<int> _history = [];
  Future<bool> Function(String command, Json payload)? onTransport;
  Future<bool> Function(WaveTrack track, AudioServiceRepeatMode repeat)?
  onEnded;
  void Function()? onProcessingChanged;
  Future<void> Function(double volume)? onVolumeChanged;
  void Function(String message)? onError;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  WaveAudioHandler(this.api, this.cache) {
    player = AudioPlayer(
      useProxyForRequestHeaders: false,
      audioPipeline: AudioPipeline(
        androidAudioEffects: [
          if (_equalizer != null) _equalizer,
          if (_preamp != null) _preamp,
        ],
      ),
    );
    _subscriptions.add(
      player.playbackEventStream.listen(
        (_) => _broadcast(),
        onError: (Object error, StackTrace trace) {
          onError?.call(wt('native.fb89a335f1', values: {'p0': (error)}));
          _broadcast();
        },
      ),
    );
    _subscriptions.add(
      player.durationStream.listen((duration) {
        if (mediaItem.value != null && duration != null) {
          mediaItem.add(mediaItem.value!.copyWith(duration: duration));
        }
      }),
    );
    _subscriptions.add(
      player.processingStateStream.listen((state) {
        if (state == ProcessingState.completed && !_advancing) {
          _advancing = true;
          unawaited(_completed().whenComplete(() => _advancing = false));
        }
      }),
    );
  }

  /// Android exposes hardware-defined bands. Interpolate the shared logarithmic
  /// curve at each real center frequency and obey the device gain limits.
  Future<void> applyProcessing(
    WaveEqualizer preference,
    double rate, {
    bool inRoom = false,
  }) async {
    final changed =
        preference.enabled != _processing.enabled ||
        preference.preamp != _processing.preamp ||
        !_sameBands(preference.bands, _processing.bands);
    _processing = preference;
    _rate = rate.clamp(.5, 2);
    _roomSpeed = inRoom;
    if (player.speed != (inRoom ? 1 : _rate)) {
      await player.setSpeed(inRoom ? 1 : _rate);
    }
    if (changed) await _configureEqualizer();
  }

  bool _sameBands(List<double> a, List<double> b) =>
      a.length == b.length &&
      List.generate(a.length, (i) => a[i] == b[i]).every((same) => same);

  Future<void> _configureEqualizer() {
    final revision = ++_processingRevision;
    final preference = _processing;
    // A native effect update can take several platform round trips. Serialize
    // those writes so an older slider value cannot finish after a newer one.
    final operation = _processingWrites.catchError((_) {}).then((_) async {
      if (revision != _processingRevision) return;
      await _writeEqualizer(preference, revision);
    });
    _processingWrites = operation;
    return operation;
  }

  Future<void> _writeEqualizer(WaveEqualizer preference, int revision) async {
    final eq = _equalizer, enhancer = _preamp;
    if (eq == null || enhancer == null) return;
    try {
      await eq.setEnabled(preference.enabled);
      if (revision != _processingRevision) return;
      await enhancer.setEnabled(preference.enabled && preference.preamp > 0);
      if (revision != _processingRevision) return;
      await enhancer.setTargetGain(
        preference.enabled ? preference.preamp.clamp(0, 12) : 0,
      );
      if (revision != _processingRevision) return;
      await _setOutputVolume();
      if (revision != _processingRevision) return;
      if (current == null ||
          player.processingState == ProcessingState.idle ||
          player.processingState == ProcessingState.loading) {
        equalizerStatus = 'waiting';
        onProcessingChanged?.call();
        return;
      }
      final parameters = await eq.parameters.timeout(
        const Duration(seconds: 5),
      );
      if (revision != _processingRevision) return;
      hardwareBandCount = parameters.bands.length;
      for (final band in parameters.bands) {
        if (revision != _processingRevision) return;
        await band.setGain(
          preference
              .gainAt(band.centerFrequency)
              .clamp(parameters.minDecibels, parameters.maxDecibels),
        );
      }
      if (revision != _processingRevision) return;
      equalizerStatus = 'ready';
      // Restore negative preamp attenuation after a previous hardware failure.
      await _setOutputVolume();
    } catch (_) {
      if (revision != _processingRevision) return;
      equalizerStatus = 'failed';
      try {
        await eq.setEnabled(false);
        await enhancer.setEnabled(false);
        await player.setVolume(_volume);
      } catch (_) {}
    }
    onProcessingChanged?.call();
  }

  Future<void> _setOutputVolume() => player.setVolume(
    _volume *
        (_equalizer != null &&
                _processing.enabled &&
                equalizerStatus != 'failed'
            ? pow(10, _processing.preamp.clamp(-12, 0) / 20).toDouble()
            : 1),
  );

  /// A room revision supersedes an in-flight source lookup before it can start.
  void cancelPendingLoad() => _loadRevision++;

  Future<void> clear() async {
    cancelPendingLoad();
    await player.stop();
    current = null;
    tracks = [];
    _index = -1;
    cache.activeId = null;
    mediaItem.add(null);
    queue.add([]);
    _broadcast();
  }

  Future<void> initializeSession() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    _subscriptions.add(
      session.becomingNoisyEventStream.listen(
        (_) => unawaited(localCommand('pause')),
      ),
    );
    _subscriptions.add(
      session.interruptionEventStream.listen((event) {
        if (event.begin) unawaited(localCommand('pause'));
      }),
    );
  }

  MediaItem item(WaveTrack track) => MediaItem(
    id: track.id,
    title: track.title,
    artist: track.artist,
    album: track.album,
    duration: Duration(milliseconds: (track.duration * 1000).round()),
    artUri: track.artwork.isNotEmpty ? Uri.parse(api.url(track.artwork)) : null,
  );
  void _broadcast() {
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          player.playing ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.stop,
        ],
        androidCompactActionIndices: const [0, 1, 2],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        processingState: switch (player.processingState) {
          ProcessingState.idle => AudioProcessingState.idle,
          ProcessingState.loading => AudioProcessingState.loading,
          ProcessingState.buffering => AudioProcessingState.buffering,
          ProcessingState.ready => AudioProcessingState.ready,
          ProcessingState.completed => AudioProcessingState.completed,
        },
        playing: player.playing,
        updatePosition: player.position,
        bufferedPosition: player.bufferedPosition,
        speed: player.speed,
        queueIndex: _index < 0 ? null : _index,
        repeatMode: repeat,
        shuffleMode: shuffle
            ? AudioServiceShuffleMode.all
            : AudioServiceShuffleMode.none,
      ),
    );
  }

  Future<bool> _intercept(String command, [Json data = const {}]) async =>
      await onTransport?.call(command, data) ?? false;
  Future<void> playTrack(
    WaveTrack track, {
    List<WaveTrack>? list,
    double position = 0,
    bool playing = true,
  }) async {
    if (!track.playable) {
      throw WaveException(wt('native.266e43ddb8'));
    }
    final revision = ++_loadRevision;
    final available = (list ?? tracks).where((t) => t.playable).toList();
    tracks = available.any((t) => t.id == track.id)
        ? available
        : [track, ...available];
    _index = tracks.indexWhere((t) => t.id == track.id);
    current = track;
    cache.activeId = track.id;
    queue.add(tracks.map(item).toList());
    mediaItem.add(item(track));
    await player.pause();
    final local = await cache.fileFor(track.id);
    if (revision != _loadRevision) return;
    if (local != null) {
      await player.setFilePath(
        local.path,
        initialPosition: Duration(milliseconds: (position * 1000).round()),
      );
    } else {
      final playback = object(
        (await api.call('/api/tracks/${track.id}/playback'))['playback'],
      );
      if (revision != _loadRevision) return;
      final path = playback['url'] as String?;
      if (playback['kind'] != 'audio' || path == null) {
        throw WaveException(wt('native.c11b18779a'));
      }
      final uri = Uri.parse(api.url(path));
      // Never pass a GlukWave bearer token to an external CDN.
      await player.setUrl(
        uri.toString(),
        headers: uri.origin == Uri.parse(api.server).origin
            ? api.headers
            : null,
        initialPosition: Duration(milliseconds: (position * 1000).round()),
      );
    }
    if (revision != _loadRevision) return;
    await player.setSpeed(_roomSpeed ? 1 : _rate);
    await _configureEqualizer();
    if (revision != _loadRevision) return;
    _broadcast();
    if (playing) {
      await _startVerified();
    }
    if (local == null && autoCache && track.offline) {
      unawaited(
        cache.save(track).catchError((Object error) {
          onError?.call(wt('native.310a7a8960', values: {'p0': (error)}));
        }),
      );
    }
  }

  Future<void> _completed() async {
    try {
      final finished = current;
      if (finished != null && await onEnded?.call(finished, repeat) == true) {
        return;
      }
      if (repeat == AudioServiceRepeatMode.one && current != null) {
        if (await _intercept('seek', {'position': 0})) return;
        await player.seek(Duration.zero);
        await _startVerified();
      } else {
        await skipToNext();
      }
    } catch (error) {
      onError?.call(error.toString());
    }
  }

  Future<void> localCommand(String command, [Json data = const {}]) async {
    switch (command) {
      case 'play':
        if (current == null) throw WaveException(wt('native.449b7110f6'));
        await _startVerified();
      case 'pause':
        await player.pause();
      case 'seek':
        await player.seek(
          Duration(milliseconds: (number(data['position']) * 1000).round()),
        );
      case 'volume':
        _volume = number(data['volume'], .8).clamp(0, 1);
        await _setOutputVolume();
        await onVolumeChanged?.call(_volume);
      case 'next':
        await _skip(1);
      case 'previous':
        await _skip(-1);
      case 'stop':
        await player.stop();
    }
    _broadcast();
  }

  Future<void> _startVerified() async {
    final failure = Completer<void>();
    final errors = player.playbackEventStream.listen(
      (_) {},
      onError: (Object error, StackTrace trace) {
        if (!failure.isCompleted) {
          failure.completeError(error, trace);
        }
      },
    );
    final ready = player.playerStateStream.firstWhere(
      (state) =>
          state.playing && state.processingState == ProcessingState.ready,
    );
    // just_audio.play() completes at the end of the track on Android. Observe
    // ready/playing and early native errors instead of awaiting that future.
    unawaited(
      player.play().catchError((Object error, StackTrace trace) {
        if (!failure.isCompleted) {
          failure.completeError(error, trace);
        }
      }),
    );
    try {
      await Future.any<void>([
        failure.future,
        ready.then(
          (_) => Future<void>.delayed(const Duration(milliseconds: 180)),
        ),
      ]).timeout(const Duration(seconds: 8));
      if (!player.playing || player.processingState != ProcessingState.ready) {
        throw WaveException(wt('native.2f44180776'));
      }
    } catch (error) {
      await player.pause();
      rethrow;
    } finally {
      if (!failure.isCompleted) {
        failure.complete();
      }
      await errors.cancel();
    }
  }

  Future<void> _skip(int direction) async {
    if (tracks.isEmpty) return;
    if (direction < 0 && player.position > const Duration(seconds: 3)) {
      await player.seek(Duration.zero);
      return;
    }
    var next = _index + direction;
    if (direction > 0 && shuffle && tracks.length > 1) {
      _history.add(_index);
      do {
        next = _random.nextInt(tracks.length);
      } while (next == _index);
    } else if (direction < 0 && shuffle && _history.isNotEmpty) {
      next = _history.removeLast();
    }
    if (next < 0) next = 0;
    if (next >= tracks.length) {
      if (repeat != AudioServiceRepeatMode.all) {
        await player.pause();
        return;
      }
      next = 0;
    }
    await playTrack(tracks[next], list: tracks);
  }

  @override
  Future<void> play() async {
    if (!await _intercept('play')) await localCommand('play');
  }

  @override
  Future<void> pause() async {
    if (!await _intercept('pause')) await localCommand('pause');
  }

  @override
  Future<void> seek(Duration position) async {
    final data = {'position': position.inMilliseconds / 1000};
    if (!await _intercept('seek', data)) await localCommand('seek', data);
  }

  @override
  Future<void> skipToNext() async {
    if (!await _intercept('next')) await localCommand('next');
  }

  @override
  Future<void> skipToPrevious() async {
    if (!await _intercept('previous')) await localCommand('previous');
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= tracks.length) return;
    final track = tracks[index];
    if (!await _intercept('track', {
      'trackId': track.id,
      'queue': tracks.map((t) => t.id).toList(),
    })) {
      await playTrack(track);
    }
  }

  @override
  Future<void> stop() async {
    if (!await _intercept('pause')) await localCommand('stop');
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    repeat = repeatMode;
    _broadcast();
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    shuffle = shuffleMode != AudioServiceShuffleMode.none;
    _broadcast();
  }

  @override
  Future<void> addQueueItem(MediaItem mediaItem) async {
    if (tracks.any((t) => t.id == mediaItem.id)) return;
    final track = WaveTrack(
      object((await api.call('/api/tracks/${mediaItem.id}'))['track']),
    );
    if (track.playable) {
      tracks.add(track);
      queue.add(tracks.map(item).toList());
    }
  }

  Future<void> release() async {
    _processingRevision++;
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    await player.dispose();
  }
}
