// Adapted from just_audio_media_kit 2.1.0 (Pato05), public domain.
// Original Unlicense: assets/licenses/just_audio_media_kit-UNLICENSE.txt.
// Adds a native DSP bridge, bounded memory caching and ordered load/seek/end
// state handling for prepared GlukWave Connect playback.
library;

import 'dart:async';
import 'package:ffi/ffi.dart';

import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:logging/logging.dart';
import 'package:media_kit/media_kit.dart';
import 'windows_dsp.dart';
import 'diagnostics.dart';
import 'windows_playback_state.dart';

/// An [AudioPlayerPlatform] which wraps `package:media_kit`'s [Player]
class WaveMpvPlayer extends AudioPlayerPlatform implements WindowsDspOutput {
  static void Function(String message)? diagnostic;
  static void Function()? onEffectFailure;
  static const kErrorCode = 1;
  @override
  String? get sourceUri => _currentMedia?.uri;
  @override
  Future<void> applyEqualizer(
    bool enabled,
    double preamp,
    List<double> bands,
  ) async {
    await ready();
    if (_player.platform is! NativePlayer) {
      throw StateError('Native audio backend unavailable');
    }
    _equalizerGain = windowsEqualizerGain(enabled, preamp);
    _dspEnabled = enabled;
    try {
      await writeWindowsEqualizer(
        _checkedProperty,
        enabled,
        preamp,
        bands,
        volume: _requestedVolume,
      );
    } catch (_) {
      _equalizerGain = 1;
      _dspEnabled = false;
      rethrow;
    }
  }

  double _requestedVolume = 1, _equalizerGain = 1;
  bool _dspEnabled = false;
  DateTime _effectRecoveryUntil = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> _checkedProperty(String key, String value) async {
    final native = _player.platform as NativePlayer;
    if (native.disposed) throw StateError('Native audio output disposed');
    final name = key.toNativeUtf8(), data = value.toNativeUtf8();
    try {
      final result = native.mpv.mpv_set_property_string(
        native.ctx,
        name.cast(),
        data.cast(),
      );
      if (result < 0) {
        final error = native.mpv
            .mpv_error_string(result)
            .cast<Utf8>()
            .toDartString();
        throw StateError('Native audio effect: $error');
      }
    } finally {
      calloc.free(name);
      calloc.free(data);
    }
  }

  /// `package:media_kit`'s [Player]
  late final Player _player;

  /// The subscriptions that have to be disposed
  late final List<StreamSubscription> _streamSubscriptions;

  final _readyCompleter = Completer<void>();

  /// Completes when the player is ready
  Future<void> ready() => _readyCompleter.future;

  static final _logger = Logger('MediaKitPlayer');

  final _eventController = StreamController<PlaybackEventMessage>.broadcast();
  final _dataController = StreamController<PlayerDataMessage>.broadcast();

  ProcessingStateMessage _processingState = ProcessingStateMessage.idle;
  Duration _bufferedPosition = Duration.zero;
  Duration _position = Duration.zero;
  Duration? _duration;
  bool _playing = false;
  bool _mediaOpened = false;
  Future<void> _intentWrites = Future.value();
  int _intentRevision = 0;

  Future<void> _syncPlaybackIntent(int generation) {
    final work = _intentWrites.catchError((_) {}).then((_) async {
      while (generation == _loadGeneration && _mediaOpened) {
        final revision = _intentRevision;
        if (_playing) {
          await _player.play();
        } else {
          await _player.pause();
        }
        if (revision == _intentRevision) return;
      }
    });
    _intentWrites = work;
    return work;
  }

  bool _seeking = false;
  int? _errorCode;
  String? _errorMessage;
  Completer<Duration?>? _loadCompleter;
  int _loadGeneration = 0;
  void _cancelLoad() {
    _loadGeneration++;
    if (_loadCompleter?.isCompleted == false) {
      _loadCompleter!.completeError(StateError('Audio load superseded'));
    }
  }

  /// The index that's currently playing
  int _currentIndex = 0;

  Media? get _currentMedia {
    var medias = _player.state.playlist.medias;
    if (medias.isEmpty) return null;
    return medias[_player.state.playlist.index];
  }

  WaveMpvPlayer(super.id, {Player? output}) {
    _player =
        output ??
        Player(
          configuration: PlayerConfiguration(
            pitch: JustAudioMediaKit.pitch,
            protocolWhitelist: JustAudioMediaKit.protocolWhitelist,
            title: JustAudioMediaKit.title,
            bufferSize: JustAudioMediaKit.bufferSize,
            logLevel: JustAudioMediaKit.mpvLogLevel,
            ready: () => _readyCompleter.complete(),
          ),
        );
    if (output != null) _readyCompleter.complete();

    if (JustAudioMediaKit.prefetchPlaylist) {
      setProperty(_player, 'prefetch-playlist', 'yes');
    }

    _streamSubscriptions = [
      _player.stream.duration.listen((duration) {
        if (_currentMedia?.extras?['overrideDuration'] != null) return;

        _updateDuration(duration);
        _updatePlaybackEvent();
      }),
      _player.stream.position.listen((position) {
        _position = position;
        final start = _currentMedia?.start;
        if (start != null) _position -= start;
        if (_position < Duration.zero) _position = Duration.zero;
        _updatePlaybackEvent();
      }),
      _player.stream.buffering.listen((isBuffering) {
        final start = _currentMedia?.start;
        if (!isBuffering && start != null && _bufferedPosition <= start) {
          // Not ready yet, will be triggered by _player.stream.buffer
          return;
        }
        if (_processingState == ProcessingStateMessage.loading) {
          if (!isBuffering && _mediaOpened) {
            _processingState = ProcessingStateMessage.ready;
            if (_loadCompleter?.isCompleted != true) {
              _loadCompleter?.complete(_duration);
            }
          }
        } else if (_processingState != ProcessingStateMessage.completed ||
            isBuffering) {
          _processingState = isBuffering
              ? ProcessingStateMessage.buffering
              : ProcessingStateMessage.ready;
          if (_duration == null) {
            _updateDuration(_player.state.duration);
          }
        }
        _errorCode = null;
        _errorMessage = null;
        _updatePlaybackEvent();
      }),
      _player.stream.buffer.listen((buffer) {
        _bufferedPosition = buffer;
        // Detect ready for clipping audio source
        final start = _currentMedia?.start;
        if (!_player.state.buffering &&
            _mediaOpened &&
            start != null &&
            _bufferedPosition > start) {
          _processingState = ProcessingStateMessage.ready;
          if (_loadCompleter?.isCompleted != true) {
            _loadCompleter?.complete(_duration);
          }
        }
        _updatePlaybackEvent();
      }),
      _player.stream.volume.listen((volume) {
        _dataController.add(
          PlayerDataMessage(
            volume: (volume / 100.0 / _equalizerGain).clamp(0, 1).toDouble(),
          ),
        );
      }),
      _player.stream.completed.listen((completed) {
        if (nativeCompletionIsCurrent(
              completed: completed,
              mediaOpened: _mediaOpened,
              playing: _playing,
              loading: _processingState == ProcessingStateMessage.loading,
              seeking: _seeking,
              position: _position,
              duration: _duration,
            ) &&
            // is at the end of the [Playlist]
            _currentIndex == _player.state.playlist.medias.length - 1 &&
            // is not looping (technically this shouldn't be fired if the player is looping)
            _player.state.playlistMode == PlaylistMode.none) {
          _processingState = ProcessingStateMessage.completed;
        }
        _errorCode = null;
        _errorMessage = null;

        _updatePlaybackEvent();
      }),
      _player.stream.error.listen((error) async {
        if (nonFatalMpvMessage(error)) return;
        final effectError =
            error.contains('filter') ||
            error.contains('lavfi') ||
            error.contains('aresample');
        if (effectError && DateTime.now().isBefore(_effectRecoveryUntil)) {
          return;
        }
        // libmpv can accept a filter property, then reject it asynchronously.
        // Clear the effect once before reporting the playback error. Clearing
        // the flag first prevents recovery errors from recursively retrying.
        if (_dspEnabled && effectError) {
          _dspEnabled = false;
          _equalizerGain = 1;
          _effectRecoveryUntil = DateTime.now().add(const Duration(seconds: 1));
          diagnostic?.call(
            'Native equalizer failed; restoring unfiltered audio',
          );
          onEffectFailure?.call();
          try {
            await writeWindowsEqualizer(
              _checkedProperty,
              false,
              0,
              const [],
              volume: _requestedVolume,
            );
            // The media remains usable after removing a failed effect. Do not
            // turn a filter graph error into a track failure/automatic skip.
            return;
          } catch (_) {}
        }
        if (_eventController.isClosed) return;
        final errorUri = RegExp(r'Failed to open (.*)\.').firstMatch(error)?[1];
        if (errorUri == null || errorUri == _currentMedia?.uri) {
          _processingState = ProcessingStateMessage.idle;
          _errorCode = kErrorCode;
          _errorMessage = 'Native audio source failed';
          _updatePlaybackEvent();
          // An open failure must settle load(), otherwise the caller (and a
          // remote Connect command) waits forever even after mpv reports idle.
          if (_loadCompleter?.isCompleted == false) {
            _loadCompleter!.completeError(
              StateError('Native audio source failed'),
            );
          }
        }
        _logger.severe('Native audio source failed');
      }),
      _player.stream.playlist.listen((playlist) {
        if (_currentIndex != playlist.index) {
          _bufferedPosition = _position = Duration.zero;
          _currentIndex = playlist.index;
        }
        _duration = _currentMedia?.extras?['overrideDuration'];
        _updatePlaybackEvent();
      }),
      _player.stream.playlistMode.listen((playlistMode) {
        _dataController.add(
          PlayerDataMessage(loopMode: _playlistModeToLoopMode(playlistMode)),
        );
      }),
      _player.stream.pitch.listen((pitch) {
        _dataController.add(PlayerDataMessage(pitch: pitch));
      }),
      _player.stream.rate.listen((rate) {
        _dataController.add(PlayerDataMessage(speed: rate));
      }),
      _player.stream.log.listen((event) {
        final message = scrubDiagnostic(
          'MPV [${event.level}] ${event.prefix}: ${event.text}',
        );
        if (['error', 'fatal', 'warn'].contains(event.level)) {
          diagnostic?.call(message);
        }
        // ignore: avoid_print
        print(message);
      }),
    ];
  }

  void _updateDuration(Duration duration) {
    final start = _currentMedia?.start;
    final end = _currentMedia?.end;
    if (end != null) duration = end;
    if (start != null) duration -= start;
    _duration = duration;
  }

  PlaylistMode _loopModeToPlaylistMode(LoopModeMessage loopMode) {
    return switch (loopMode) {
      LoopModeMessage.off => PlaylistMode.none,
      LoopModeMessage.one => PlaylistMode.single,
      LoopModeMessage.all => PlaylistMode.loop,
    };
  }

  LoopModeMessage _playlistModeToLoopMode(PlaylistMode playlistMode) {
    return switch (playlistMode) {
      PlaylistMode.none => LoopModeMessage.off,
      PlaylistMode.single => LoopModeMessage.one,
      PlaylistMode.loop => LoopModeMessage.all,
    };
  }

  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream =>
      _eventController.stream;

  @override
  Stream<PlayerDataMessage> get playerDataMessageStream =>
      _dataController.stream;

  /// Updates the playback event
  void _updatePlaybackEvent() {
    _eventController.add(
      PlaybackEventMessage(
        processingState: _processingState,
        updateTime: DateTime.now(),
        updatePosition: _position,
        bufferedPosition: _bufferedPosition,
        duration: _duration,
        icyMetadata: null,
        currentIndex: _currentIndex,
        androidAudioSessionId: null,
        errorCode: _errorCode,
        errorMessage: _errorMessage,
      ),
    );
  }

  @override
  Future<LoadResponse> load(LoadRequest request) async {
    _logger.finest('Loading native audio source');
    _cancelLoad();
    final generation = _loadGeneration;
    _mediaOpened = false;
    _loadCompleter = Completer();
    final loaded = _loadCompleter!.future.timeout(const Duration(seconds: 30));
    loaded.ignore(); // observe an error that may arrive while open() is awaited
    _currentIndex = request.initialIndex ?? 0;
    _bufferedPosition = Duration.zero;
    _position = Duration.zero;
    _duration = null;
    _processingState = ProcessingStateMessage.loading;
    _errorCode = null;
    _errorMessage = null;
    _updatePlaybackEvent();
    await ready();
    if (generation != _loadGeneration) {
      throw StateError('Audio load superseded');
    }
    if (_player.platform is NativePlayer) {
      // media_kit defaults to disk demux caching. Audio uses a bounded memory
      // cache so a missing/unwritable temporary directory cannot break handoff.
      await _checkedProperty('cache-on-disk', 'no');
      await _checkedProperty('demuxer-max-bytes', '16777216');
      await _checkedProperty('demuxer-max-back-bytes', '8388608');
    }

    if (request.audioSourceMessage is ConcatenatingAudioSourceMessage) {
      final audioSource =
          request.audioSourceMessage as ConcatenatingAudioSourceMessage;
      final playable = Playlist(
        audioSource.children.map(_convertAudioSourceIntoMediaKit).toList(),
        index: _currentIndex,
      );

      await Future.any([
        _player.open(playable, play: _playing),
        loaded.then<void>((_) => Completer<void>().future),
      ]);
    } else {
      final playable = _convertAudioSourceIntoMediaKit(
        request.audioSourceMessage,
      );
      await Future.any([
        _player.open(playable, play: _playing),
        loaded.then<void>((_) => Completer<void>().future),
      ]);
    }
    if (generation != _loadGeneration) {
      throw StateError('Audio load superseded');
    }
    _mediaOpened = true;
    // Buffering can finish during open(), before _mediaOpened becomes true.
    // The edge-triggered event alone cannot complete that load.
    if (!_player.state.buffering &&
        _player.state.duration > Duration.zero &&
        _loadCompleter?.isCompleted == false) {
      _processingState = ProcessingStateMessage.ready;
      _updateDuration(_player.state.duration);
      _loadCompleter!.complete(_duration);
    }

    _updatePlaybackEvent();
    final duration = await loaded;
    if (generation != _loadGeneration) {
      throw StateError('Audio load superseded');
    }
    if (request.initialPosition != null) {
      await seek(SeekRequest(position: request.initialPosition));
    }
    // just_audio may send play/pause while open or initial seek is pending.
    // Reconcile the latest intent only after the new media is actually open.
    if (generation != _loadGeneration) {
      throw StateError('Audio load superseded');
    }
    await _syncPlaybackIntent(generation);
    return LoadResponse(duration: duration);
  }

  @override
  Future<PlayResponse> play(PlayRequest request) async {
    _playing = true;
    _intentRevision++;
    if (_mediaOpened) {
      await _syncPlaybackIntent(_loadGeneration);
    }
    return PlayResponse();
  }

  @override
  Future<PauseResponse> pause(PauseRequest request) async {
    _playing = false;
    _intentRevision++;
    if (_mediaOpened) {
      await _syncPlaybackIntent(_loadGeneration);
    }
    return PauseResponse();
  }

  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) {
    _requestedVolume = request.volume;
    return _player
        .setVolume(request.volume * 100.0 * _equalizerGain)
        .then((value) => SetVolumeResponse());
  }

  @override
  Future<SetSpeedResponse> setSpeed(SetSpeedRequest request) {
    return _player.setRate(request.speed).then((_) => SetSpeedResponse());
  }

  @override
  Future<SetPitchResponse> setPitch(SetPitchRequest request) =>
      _player.setPitch(request.pitch).then((_) => SetPitchResponse());

  @override
  Future<SetLoopModeResponse> setLoopMode(SetLoopModeRequest request) async {
    await _player.setPlaylistMode(_loopModeToPlaylistMode(request.loopMode));
    return SetLoopModeResponse();
  }

  @override
  Future<SetShuffleModeResponse> setShuffleMode(
    SetShuffleModeRequest request,
  ) async {
    bool shuffling = request.shuffleMode != ShuffleModeMessage.none;
    await _player.setShuffle(shuffling);

    _dataController.add(
      PlayerDataMessage(
        shuffleMode: shuffling
            ? ShuffleModeMessage.all
            : ShuffleModeMessage.none,
      ),
    );
    return SetShuffleModeResponse();
  }

  @override
  Future<SeekResponse> seek(SeekRequest request) async {
    _logger.finest('seek(${request.toMap()})');
    if (request.index != null) {
      await _player.jump(request.index!);
      if (!_playing) await _player.pause();
    }

    final position = request.position;
    if (position != null) {
      _seeking = true;
      _position = position;
      _processingState = ProcessingStateMessage.ready;
      final start = _currentMedia?.start;
      var nativePosition = position;
      if (start != null) nativePosition += start;
      try {
        await _player.seek(nativePosition);
      } finally {
        _seeking = false;
      }
    } else {
      _position = Duration.zero;
    }

    // reset position on seek
    _updatePlaybackEvent();
    return SeekResponse();
  }

  @override
  Future<ConcatenatingInsertAllResponse> concatenatingInsertAll(
    ConcatenatingInsertAllRequest request,
  ) async {
    // _logger.fine('concatenatingInsertAll(${request.toMap()})');
    for (final source in request.children) {
      await _player.add(_convertAudioSourceIntoMediaKit(source));

      final length = _player.state.playlist.medias.length;

      if (length == 0 || length == 1) continue;

      if (request.index < (length - 1) && request.index >= 0) {
        await _player.move(length, request.index);
      }
    }

    return ConcatenatingInsertAllResponse();
  }

  @override
  Future<ConcatenatingRemoveRangeResponse> concatenatingRemoveRange(
    ConcatenatingRemoveRangeRequest request,
  ) async {
    for (var i = request.startIndex; i < request.endIndex; i++) {
      await _player.remove(request.startIndex);
    }

    return ConcatenatingRemoveRangeResponse();
  }

  @override
  Future<ConcatenatingMoveResponse> concatenatingMove(
    ConcatenatingMoveRequest request,
  ) {
    return _player
        .move(
          request.currentIndex,
          // not sure why, but apparently there's an underlying difference between just_audio's move implementation
          // and media_kit, so let's fix it
          request.currentIndex > request.newIndex
              ? request.newIndex
              : request.newIndex + 1,
        )
        .then((_) => ConcatenatingMoveResponse());
  }

  /// Release the resources used by this player.
  @override
  Future<void> release() async {
    _logger.info('releasing player resources');
    _cancelLoad();
    _mediaOpened = false;
    await _player.dispose();
    // cancel all stream subscriptions
    await Future.wait(
      _streamSubscriptions.map((subscription) => subscription.cancel()),
    );
    _streamSubscriptions.clear();
    await _eventController.close();
    await _dataController.close();
  }

  /// Converts an [AudioSourceMessage] into a [Media] for playback
  Media _convertAudioSourceIntoMediaKit(AudioSourceMessage audioSource) {
    switch (audioSource) {
      case final UriAudioSourceMessage uriSource:
        return Media(uriSource.uri, httpHeaders: audioSource.headers);

      // removed because it doesn't seem to be actually working.
      // Related media-kit issue: https://github.com/media-kit/media-kit/issues/28
      // case final SilenceAudioSourceMessage silenceSource:
      //   // from https://github.com/bleonard252/just_audio_mpv/blob/main/lib/src/mpv_player.dart#L137
      //   return Media(
      //     'av://lavfi:anullsrc=d=${silenceSource.duration.inMilliseconds}ms',
      //     extras: {'overrideDuration': silenceSource.duration},
      //   );

      case final ClippingAudioSourceMessage clippingSource:
        return Media(
          clippingSource.child.uri,
          start: clippingSource.start,
          end: clippingSource.end,
        );

      default:
        throw UnsupportedError(
          '${audioSource.runtimeType} is currently not supported',
        );
    }
  }
}

Future<void> setProperty(Player player, String key, dynamic value) async {
  if (player.platform is! NativePlayer) return;
  await (player.platform as NativePlayer).setProperty(key, value);
}
