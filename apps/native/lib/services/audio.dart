import '../l10n/wave_localizations.dart';
import '../l10n/lan_strings.dart';
import '../l10n/home_widget_strings.dart';
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
import 'provider_player.dart';
import 'windows_equalizer.dart';

class WaveAudioHandler extends BaseAudioHandler {
  bool offlineOnly = false;
  bool prepareNext = true;
  final WaveApi api;
  final MusicCache cache;
  final Duration sourceLoadTimeout;
  final bool hardwareVolume;
  final bool verifyNativeProgress;
  // Native players send authorization headers directly. Android does not need an
  // insecure loopback proxy in release builds.
  late final AudioPlayer player;
  final ProviderPlayer provider = ProviderPlayer();
  PlaybackSnapshot? _remote;
  WaveTrack? _remoteTrack;
  List<WaveTrack> _remoteQueue = [];
  WaveTrack? _pendingTrack, _selectedTrack;
  void showPendingSelection(WaveTrack? track) {
    _selectedTrack = track;
    onLoadingChanged?.call();
  }

  bool _resolving = false;
  bool get trackLoading =>
      _selectedTrack != null ||
      !remote &&
          (_resolving ||
              player.playing &&
                  [
                    ProcessingState.loading,
                    ProcessingState.buffering,
                  ].contains(player.processingState));
  void Function()? onLoadingChanged;
  void _setResolving(bool value) {
    if (_resolving == value) return;
    _resolving = value;
    onLoadingChanged?.call();
    if (!_released) _broadcast();
  }

  WaveTrack? get viewCurrent =>
      _selectedTrack ??
      (_remote != null ? _remoteTrack : _pendingTrack ?? current);
  List<WaveTrack> get viewTracks => _remote != null ? _remoteQueue : tracks;
  bool get remote => _remote != null;
  int get loadRevision => _loadRevision;
  bool get sourceReady => current?.embedded == true
      ? provider.ready
      : player.processingState == ProcessingState.ready;
  bool get outputPlaying =>
      current?.embedded == true ? provider.playing : player.playing;
  Duration get outputPosition => current?.embedded == true
      ? Duration(milliseconds: (provider.position * 1000).round())
      : player.position;
  bool? get previewPlaying => _controlPreview['playing'] as bool?;
  bool get playing =>
      _controlPreview['playing'] as bool? ?? _remote?.playing ?? outputPlaying;
  Duration get position => _remote == null
      ? outputPosition
      : Duration(
          milliseconds:
              (_remote!.projectedPosition(
                        DateTime.now().millisecondsSinceEpoch,
                        duration: _remoteTrack?.duration,
                      ) *
                      1000)
                  .round(),
        );
  Duration? get duration => _remote != null
      ? Duration(milliseconds: ((_remoteTrack?.duration ?? 0) * 1000).round())
      : current?.embedded == true
      ? Duration(milliseconds: (provider.duration * 1000).round())
      : player.duration;
  late final StreamController<Duration> _positions =
      StreamController<Duration>.broadcast(
        onListen: _updatePositionTimer,
        onCancel: _updatePositionTimer,
      );
  Timer? _positionTimer;
  bool _visualUpdatesEnabled = true, _released = false;
  Stream<Duration> get positionStream =>
      _positions.stream.where((_) => _visualUpdatesEnabled && !_released);
  void setVisualUpdatesEnabled(bool enabled) {
    _visualUpdatesEnabled = enabled;
    _updatePositionTimer();
  }

  void _updatePositionTimer() {
    if (_released) return;
    _positionTimer?.cancel();
    _positionTimer = null;
    if (!_positions.hasListener || !_visualUpdatesEnabled) return;
    scheduleMicrotask(() {
      if (!_released && _positions.hasListener && _visualUpdatesEnabled) {
        _positions.add(position);
      }
    });
    if (playing) {
      _positionTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (!_released && _visualUpdatesEnabled && _positions.hasListener) {
          _positions.add(position);
        }
      });
    }
  }

  Future<void> suspendLocalOutput() async {
    cancelPendingLoad();
    await player.pause();
    await provider.clear();
  }

  double get outputVolume => hardwareVolume ? 1 : _volume;
  void showRemote(
    PlaybackSnapshot state,
    WaveTrack? track,
    List<WaveTrack> queue,
  ) {
    _remote = PlaybackSnapshot(
      trackId: state.trackId,
      position: state.position,
      volume: state.volume,
      playing: state.playing,
      queue: state.queue,
      shuffle: state.shuffle,
      repeat: state.repeat,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      revision: state.revision,
    );
    applyPlaybackModes(state);
    _remoteTrack = track;
    _remoteQueue = queue;
    mediaItem.add(track == null ? null : item(track));
    this.queue.add(queue.map(item).toList());
    _broadcast();
  }

  void applyPlaybackModes(PlaybackSnapshot state) {
    if (state.shuffle != null) shuffle = state.shuffle!;
    if (state.repeat != null) {
      repeat = switch (state.repeat!) {
        'one' => AudioServiceRepeatMode.one,
        'all' => AudioServiceRepeatMode.all,
        _ => AudioServiceRepeatMode.none,
      };
    }
  }

  void replaceQueue(List<WaveTrack> items) {
    if (remote) {
      _remoteQueue = List.of(items);
    } else {
      tracks = List.of(items);
      _index = tracks.indexWhere((track) => track.id == current?.id);
      _history.clear();
    }
    queue.add(items.map(item).toList());
    _broadcast();
  }

  void clearRemote() {
    if (_remote == null) return;
    _remote = null;
    _remoteTrack = null;
    _remoteQueue = [];
    mediaItem.add(current == null ? null : item(current!));
    queue.add(tracks.map(item).toList());
    _broadcast();
  }

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
  String equalizerStatus = Platform.isAndroid || Platform.isWindows
      ? 'waiting'
      : 'unsupported';
  int hardwareBandCount = 0;
  void nativeProcessingFailed() {
    equalizerStatus = 'failed';
    onProcessingChanged?.call();
  }

  String? _nativeSource;
  double get volume => hardwareVolume && !remote
      ? 1
      : (_controlPreview['volume'] as num?)?.toDouble() ??
            _remote?.volume ??
            _volume;
  bool get equalizerSupported =>
      (_equalizer != null ||
          Platform.isWindows && WaveWindowsAudio.active != null) &&
      current?.embedded != true &&
      !remote;
  List<WaveTrack> tracks = [];
  WaveTrack? current;
  AudioServiceRepeatMode _repeat = AudioServiceRepeatMode.none;
  AudioServiceRepeatMode get repeat =>
      _controlPreview['repeat'] as AudioServiceRepeatMode? ?? _repeat;
  set repeat(AudioServiceRepeatMode value) => _repeat = value;
  bool _shuffle = false;
  bool get shuffle => _controlPreview['shuffle'] as bool? ?? _shuffle;
  set shuffle(bool value) => _shuffle = value;
  final Json _controlPreview = {};

  /// Presentation overlays survive authoritative snapshots until this gesture
  /// is acknowledged. Volume also changes the local output without persistence.
  Future<void> previewControl(
    String field,
    dynamic value, {
    bool localVolume = false,
  }) async {
    _controlPreview[field] = value;
    _broadcast();
    if (field == 'volume' && localVolume) {
      if (current?.embedded == true) {
        await provider.command('volume', {
          'volume': hardwareVolume ? 1 : value,
        });
      } else {
        await _setOutputVolume();
      }
    }
  }

  Future<void> clearControlPreview(
    String field, {
    bool localVolume = false,
  }) async {
    _controlPreview.remove(field);
    _broadcast();
    if (field == 'volume' && localVolume) await _setOutputVolume();
  }

  void acceptControl(String field, dynamic value) {
    if (field == 'shuffle') _shuffle = value == true;
    if (field == 'repeat') _repeat = value as AudioServiceRepeatMode;
    if (_remote != null && (field == 'playing' || field == 'volume')) {
      final state = _remote!, position = this.position.inMilliseconds / 1000;
      _remote = PlaybackSnapshot(
        trackId: state.trackId,
        position: position,
        volume: field == 'volume' ? number(value) : state.volume,
        playing: field == 'playing' ? value == true : state.playing,
        queue: state.queue,
        shuffle: state.shuffle,
        repeat: state.repeat,
        revision: state.revision,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
    }
  }

  void clearControlPreviews() {
    _controlPreview.clear();
    _broadcast();
  }

  bool autoCache = true;
  bool _intendedPlaying = false, _recoveringStream = false;
  String? _recoveredTrack;
  DateTime _recoveredAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _index = -1, _loadRevision = 0;
  Completer<void> _loadCancelled = Completer<void>();
  bool _advancing = false;
  final _random = Random();
  final List<int> _history = [];
  Future<bool> Function(String command, Json payload)? onTransport;
  Future<void> Function(String command, String scope)? onWidgetCommand;
  Future<void> Function()? onNotificationLike;
  bool Function(String trackId)? isNotificationTrackLiked;
  String Function()? notificationScope;
  String? _publishedLikeTrack, _publishedLikeScope;
  bool? _publishedLiked;

  bool _isLiked(String id) => isNotificationTrackLiked?.call(id) ?? false;
  String _likeAction(String id) =>
      'glukwave.like/${Uri.encodeComponent(notificationScope?.call() ?? '')}/${Uri.encodeComponent(id)}';

  bool _refreshLikeMetadata() {
    final track = viewCurrent, scope = notificationScope?.call() ?? '';
    final liked = track != null && _isLiked(track.id);
    if (_publishedLikeTrack == track?.id &&
        _publishedLikeScope == scope &&
        _publishedLiked == liked) {
      return false;
    }
    _publishedLikeTrack = track?.id;
    _publishedLikeScope = scope;
    _publishedLiked = liked;
    final currentItem = mediaItem.value;
    if (track != null && currentItem?.id == track.id) {
      mediaItem.add(
        currentItem!.copyWith(rating: Rating.newHeartRating(liked)),
      );
    }
    return true;
  }

  /// Library optimistic changes, rollback and account restore publish the same
  /// heart as the application without restarting audio or changing position.
  void refreshNotificationLike() {
    if (_released) return;
    if (_refreshLikeMetadata()) _broadcast();
  }

  String? widgetGrant;
  Future<bool> Function(WaveTrack track, AudioServiceRepeatMode repeat)?
  onEnded;
  void Function()? onProcessingChanged;
  Future<void> Function(double volume)? onVolumeChanged;
  void Function(String message)? onError;
  Future<bool> Function(WaveTrack track, Object error)? onSourceFailure;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  WaveAudioHandler(
    this.api,
    this.cache, {
    AudioPlayer? output,
    bool? hardwareVolume,
    bool? verifyNativeProgress,
    this.sourceLoadTimeout = const Duration(seconds: 30),
  }) : hardwareVolume =
           hardwareVolume ?? (Platform.isAndroid || Platform.isIOS),
       verifyNativeProgress =
           verifyNativeProgress ?? (Platform.isWindows && output == null) {
    provider.addListener(_broadcast);
    provider.onError = (message) => onError?.call(wt(message));
    provider.onEnded = () {
      if (!_advancing) {
        _advancing = true;
        unawaited(_completed().whenComplete(() => _advancing = false));
      }
    };
    player =
        output ??
        AudioPlayer(
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
          if (Platform.isWindows && _processing.enabled) {
            equalizerStatus = 'failed';
            onProcessingChanged?.call();
          }
          final failed = current;
          if (failed != null && !trackLoading && !_released) {
            unawaited(recoverSourceFailure(error));
          } else {
            onError?.call(wt('native.fb89a335f1', values: {'p0': (error)}));
          }
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
    if (Platform.isWindows && WaveWindowsAudio.active != null) {
      if (current == null ||
          current!.embedded ||
          player.processingState == ProcessingState.idle ||
          player.processingState == ProcessingState.loading) {
        equalizerStatus = 'waiting';
        onProcessingChanged?.call();
        return;
      }
      try {
        await WaveWindowsAudio.active!.apply(preference, _nativeSource);
        if (revision != _processingRevision) return;
        hardwareBandCount = 10;
        equalizerStatus = 'ready';
      } catch (_) {
        if (revision != _processingRevision) return;
        equalizerStatus = 'failed';
        try {
          await WaveWindowsAudio.active!.apply(
            const WaveEqualizer(),
            _nativeSource,
          );
        } catch (_) {}
      }
      onProcessingChanged?.call();
      return;
    }
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
        await player.setVolume(outputVolume);
      } catch (_) {}
    }
    onProcessingChanged?.call();
  }

  Future<void> _setOutputVolume() => player.setVolume(
    (hardwareVolume ? 1 : number(_controlPreview['volume'], _volume)) *
        (_equalizer != null &&
                _processing.enabled &&
                equalizerStatus != 'failed'
            ? pow(10, _processing.preamp.clamp(-12, 0) / 20).toDouble()
            : 1),
  );

  /// A room revision supersedes an in-flight source lookup before it can start.
  void cancelPendingLoad() {
    _loadRevision++;
    _pendingTrack = null;
    _setResolving(false);
    if (!_loadCancelled.isCompleted) _loadCancelled.complete();
    _loadCancelled = Completer<void>();
    provider.cancelPendingLoad();
  }

  Future<void> clear() async {
    cancelPendingLoad();
    clearRemote();
    await provider.clear();
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
    rating: Rating.newHeartRating(_isLiked(track.id)),
  );
  void _broadcast() {
    _updatePositionTimer();
    _refreshLikeMetadata();
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          playing ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
          if (!hardwareVolume) MediaControl.stop,
          if (hardwareVolume &&
              onNotificationLike != null &&
              viewCurrent != null)
            MediaControl.custom(
              androidIcon: _isLiked(viewCurrent!.id)
                  ? 'drawable/widget_heart_filled'
                  : 'drawable/widget_heart',
              label: homeWidgetText(
                _isLiked(viewCurrent!.id) ? 'unlike' : 'like',
              ),
              name: _likeAction(viewCurrent!.id),
              extras: {
                'trackId': viewCurrent!.id,
                'scope': notificationScope?.call() ?? '',
              },
            ),
        ],
        androidCompactActionIndices: const [0, 1, 2],
        systemActions: {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          if (onNotificationLike != null && viewCurrent != null)
            MediaAction.setRating,
        },
        processingState: remote
            ? AudioProcessingState.ready
            : _resolving
            ? AudioProcessingState.loading
            : current?.embedded == true
            ? provider.loading
                  ? AudioProcessingState.loading
                  : provider.ready
                  ? AudioProcessingState.ready
                  : AudioProcessingState.idle
            : switch (player.processingState) {
                ProcessingState.idle => AudioProcessingState.idle,
                ProcessingState.loading => AudioProcessingState.loading,
                ProcessingState.buffering => AudioProcessingState.buffering,
                ProcessingState.ready => AudioProcessingState.ready,
                ProcessingState.completed => AudioProcessingState.completed,
              },
        playing: playing,
        updatePosition: position,
        bufferedPosition: player.bufferedPosition,
        speed: player.speed,
        queueIndex: remote
            ? viewTracks.indexWhere((track) => track.id == viewCurrent?.id)
            : _index < 0
            ? null
            : _index,
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
    bool recover = true,
  }) async {
    _intendedPlaying = playing;
    api.diagnostics.record('Open track ${track.id}', code: 'SOURCE_OPEN');
    if (current?.id == track.id &&
        current?.playback['kind'] == 'audio' &&
        !trackLoading &&
        player.processingState != ProcessingState.idle &&
        player.processingState != ProcessingState.loading) {
      cancelPendingLoad();
      final revision = _loadRevision;
      replaceQueue(list ?? tracks);
      await player.seek(Duration(milliseconds: (position * 1000).round()));
      if (revision != _loadRevision || _released) return;
      if (playing) {
        await _startVerified(revision: revision);
      } else {
        await player.pause();
      }
      _broadcast();
      return;
    }
    cancelPendingLoad();
    final revision = _loadRevision;
    final previousTrack = current,
        previousTracks = tracks,
        previousIndex = _index;
    _pendingTrack = track;
    _setResolving(true);
    try {
      await player.pause();
      await provider.clear();
      if (revision != _loadRevision || _released) return;
      // The selected queue exists locally before a descriptor arrives. This
      // also lets a failed lookup advance the selected item, not the old song.
      clearRemote();
      final order = (list ?? tracks).where((item) => item.playable).toList();
      tracks = order.any((item) => item.id == track.id)
          ? order
          : [track, ...order];
      queue.add(tracks.map(item).toList());
      await _loadTrack(
        track,
        list: list,
        position: position,
        playing: playing,
        revision: revision,
      );
    } catch (error) {
      if (revision != _loadRevision || _released) return;
      if (recover && await onSourceFailure?.call(track, error) == true) return;
      if (mediaItem.value?.id != track.id) {
        current = previousTrack;
        tracks = previousTracks;
        _index = previousIndex;
        queue.add(tracks.map(item).toList());
      }
      rethrow;
    } finally {
      if (revision == _loadRevision) {
        _pendingTrack = null;
        _setResolving(false);
      }
    }
  }

  Future<void> _loadTrack(
    WaveTrack track, {
    List<WaveTrack>? list,
    required double position,
    required bool playing,
    required int revision,
    bool retryCached = true,
    bool renewStream = true,
    bool fresh = false,
  }) async {
    // A permitted cached download remains usable without a network lookup.
    final local = await cache.fileFor(track.id);
    if (revision != _loadRevision || _released) return;
    if (local == null && offlineOnly) throw WaveException(lanText('cache'));
    Json? resolvedPlayback;
    if (local != null) {
      track = WaveTrack({
        ...track.json,
        'playback': {...track.playback, 'kind': 'audio', 'offline': true},
      });
    } else {
      final effective = await api.resolvePlayback(track, fresh: fresh);
      if (revision != _loadRevision) return;
      track = effective;
      resolvedPlayback = effective.playback;
    }
    if (track.playback['kind'] != 'audio') {
      throw WaveException(wt('native.266e43ddb8'), 'AUDIO_UNAVAILABLE');
    }
    clearRemote();
    final available = (list ?? tracks)
        .map((item) => item.id == track.id ? track : item)
        .where((t) => t.playable)
        .toList();
    tracks = available.any((t) => t.id == track.id)
        ? available
        : [track, ...available];
    _index = tracks.indexWhere((t) => t.id == track.id);
    current = track;
    cache.activeId = track.id;
    queue.add(tracks.map(item).toList());
    mediaItem.add(item(track));
    await player.pause();
    if (revision != _loadRevision) return;
    await provider.clear();
    if (revision != _loadRevision) return;
    if (local != null) {
      _nativeSource = Uri.file(local.path).toString();
      try {
        await player.setFilePath(
          local.path,
          initialPosition: Duration(milliseconds: (position * 1000).round()),
        );
      } on PlayerException {
        // A binary file can still fail the native decoder. Evict only this
        // failed download and resolve once; cancellation/offline stay local.
        if (!retryCached ||
            offlineOnly ||
            revision != _loadRevision ||
            _released) {
          rethrow;
        }
        cache.activeId = null;
        await cache.remove(track.id);
        if (revision != _loadRevision || _released) return;
        return _loadTrack(
          track,
          list: list,
          position: position,
          playing: playing,
          revision: revision,
          retryCached: false,
          renewStream: false,
          fresh: true,
        );
      }
    } else {
      final playback =
          resolvedPlayback ??
          object(
            (await api.call('/api/tracks/${track.id}/playback'))['playback'],
          );
      if (revision != _loadRevision) return;
      final path = playback['url'] as String?;
      if (playback['kind'] != 'audio' || path == null) {
        throw WaveException(wt('native.c11b18779a'));
      }
      final uri = Uri.parse(api.url(path));
      _nativeSource = uri.toString();
      // Never pass a GlukWave bearer token to an external CDN.
      final headers = uri.origin == Uri.parse(api.server).origin
          ? api.headers
          : null;
      final initialPosition = Duration(milliseconds: (position * 1000).round());
      try {
        final load = playback['format'] == 'hls'
            ? player.setAudioSource(
                HlsAudioSource(uri, headers: headers),
                initialPosition: initialPosition,
              )
            : player.setUrl(
                uri.toString(),
                headers: headers,
                initialPosition: initialPosition,
              );
        await Future.any([
          load.timeout(sourceLoadTimeout),
          _loadCancelled.future.then<Duration?>((_) => null),
        ]);
      } catch (error) {
        if (revision != _loadRevision || _released) return;
        api.diagnostics.report(
          error,
          kind: 'playback',
          code: 'NATIVE_SOURCE_LOAD',
        );
        await player.stop();
        // A grant may disappear on a server restart. Resolve a new capability
        // once using this device's session; never reuse another device's URL.
        if (renewStream && !offlineOnly) {
          return _loadTrack(
            track,
            list: list,
            position: position,
            playing: playing,
            revision: revision,
            retryCached: retryCached,
            renewStream: false,
            fresh: true,
          );
        }
        throw WaveException(
          wt('native.streamUnavailable'),
          error is TimeoutException
              ? 'AUDIO_STREAM_TIMEOUT'
              : 'AUDIO_STREAM_UNAVAILABLE',
        );
      }
    }
    if (revision != _loadRevision) return;
    await player.setSpeed(_roomSpeed ? 1 : _rate);
    await _configureEqualizer();
    if (revision != _loadRevision) return;
    _broadcast();
    if (playing) {
      await _startVerified(revision: revision);
    }
    if (revision != _loadRevision) return;
    if (local == null &&
        autoCache &&
        track.offline &&
        track.playback['format'] != 'hls') {
      unawaited(
        cache.save(track).catchError((Object error) {
          onError?.call(wt('native.310a7a8960', values: {'p0': (error)}));
        }),
      );
    }
    if (playing &&
        prepareNext &&
        !offlineOnly &&
        _index >= 0 &&
        _index + 1 < tracks.length) {
      final next = tracks[_index + 1], account = api.token, origin = api.server;
      unawaited(
        () async {
          if (await cache.fileFor(next.id) != null) return;
          final prepared = await api.resolvePlayback(next);
          if (_released || account != api.token || origin != api.server) return;
          if (autoCache &&
              prepared.offline &&
              prepared.playback['format'] != 'hls') {
            await cache.save(prepared);
          }
        }().catchError((_) {}),
      );
    }
  }

  Future<void> _completed() async {
    try {
      final finished = current;
      if (finished != null && await onEnded?.call(finished, repeat) == true) {
        return;
      }
      if (current?.id != finished?.id || _released) return;
      if (repeat == AudioServiceRepeatMode.one &&
          current != null &&
          tracks.any((track) => track.id == current!.id)) {
        if (await _intercept('seek', {'position': 0})) return;
        await localCommand('seek', {'position': 0});
        await localCommand('play');
      } else {
        await skipToNext();
      }
    } catch (error) {
      onError?.call(error.toString());
    }
  }

  Future<void> recoverSourceFailure(Object error) async {
    final failed = current;
    if (failed == null || trackLoading || _released) return;
    await _recoverStream(failed, error);
  }

  Future<void> _recoverStream(WaveTrack failed, Object error) async {
    if (_recoveringStream ||
        _released ||
        offlineOnly ||
        failed.embedded ||
        error is PlayerInterruptedException) {
      return;
    }
    if (_recoveredTrack == failed.id &&
        DateTime.now().difference(_recoveredAt).inSeconds < 60) {
      onError?.call(wt('native.streamUnavailable'));
      return;
    }
    _recoveringStream = true;
    _recoveredTrack = failed.id;
    _recoveredAt = DateTime.now();
    final position = outputPosition.inMilliseconds / 1000,
        playing = _intendedPlaying;
    final account = api.token,
        origin = api.server,
        order = List<WaveTrack>.from(tracks);
    cancelPendingLoad();
    final revision = _loadRevision;
    _pendingTrack = failed;
    _setResolving(true);
    api.diagnostics.record(
      'Renew active stream at ${position.toStringAsFixed(1)}s',
      code: 'SOURCE_RENEW',
    );
    try {
      await player.stop();
      if (revision != _loadRevision ||
          account != api.token ||
          origin != api.server ||
          _released) {
        return;
      }
      await _loadTrack(
        failed,
        list: order,
        position: position,
        playing: playing,
        revision: revision,
        fresh: true,
        renewStream: false,
      );
    } catch (failure) {
      if (revision != _loadRevision || _released) return;
      api.diagnostics.report(
        failure,
        kind: 'playback',
        code: 'SOURCE_RENEW_FAILED',
      );
      if (await onSourceFailure?.call(failed, failure) != true) {
        onError?.call(
          failure is WaveException
              ? failure.message
              : wt('native.streamUnavailable'),
        );
      }
    } finally {
      _recoveringStream = false;
      if (revision == _loadRevision) {
        _pendingTrack = null;
        _setResolving(false);
      }
    }
  }

  Future<void> localCommand(String command, [Json data = const {}]) async {
    if (['play', 'pause', 'stop'].contains(command)) {
      _intendedPlaying = command == 'play';
    }
    if (command == 'pause' || command == 'stop') cancelPendingLoad();
    if (current?.embedded == true && !['next', 'previous'].contains(command)) {
      if (command == 'play' && !provider.ready && !provider.loading) {
        await provider.load(
          current!,
          position: provider.position,
          volume: outputVolume,
        );
        _broadcast();
        return;
      }
      if (command == 'volume') {
        _volume = hardwareVolume ? 1 : number(data['volume'], .8).clamp(0, 1);
        await onVolumeChanged?.call(_volume);
      }
      await provider.command(
        command,
        command == 'volume' ? {...data, 'volume': outputVolume} : data,
      );
      _broadcast();
      return;
    }
    switch (command) {
      case 'play':
        if (current == null) throw WaveException(wt('native.449b7110f6'));
        if (current?.playback['kind'] == 'audio' &&
            !sourceReady &&
            !trackLoading) {
          await playTrack(
            current!,
            list: tracks,
            position: outputPosition.inMilliseconds / 1000,
            recover: false,
          );
          break;
        }
        await _startVerified(revision: _loadRevision);
      case 'pause':
        await player.pause();
      case 'seek':
        await player.seek(
          Duration(milliseconds: (number(data['position']) * 1000).round()),
        );
      case 'volume':
        _volume = hardwareVolume ? 1 : number(data['volume'], .8).clamp(0, 1);
        await _setOutputVolume();
        await onVolumeChanged?.call(_volume);
      case 'next':
        await _skip(1);
      case 'previous':
        await _skip(-1);
      case 'shuffle':
        shuffle = data['enabled'] == true;
      case 'repeat':
        repeat = switch (data['repeat']) {
          'one' => AudioServiceRepeatMode.one,
          'all' => AudioServiceRepeatMode.all,
          _ => AudioServiceRepeatMode.none,
        };
      case 'queue':
        if (data['trackId'] != null && data['trackId'] != current?.id) {
          throw WaveException(wt('native.7e03f83d51'), 'PLAYBACK_CHANGED');
        }
        final items = <WaveTrack>[];
        for (final id in List<String>.from(data['queue'] ?? [])) {
          final existing = tracks.where((track) => track.id == id).firstOrNull;
          items.add(
            existing ??
                WaveTrack(
                  object(
                    (await api.call(
                      '/api/tracks/${Uri.encodeComponent(id)}',
                    ))['track'],
                  ),
                ),
          );
        }
        replaceQueue(items);
      case 'stop':
        await player.stop();
    }
    _broadcast();
  }

  Future<void> _startVerified({int? revision}) async {
    final startPosition = player.position;
    final advanced = Completer<void>();
    final positions = verifyNativeProgress
        ? player.positionStream.listen((position) {
            if (position > startPosition + const Duration(milliseconds: 20) &&
                !advanced.isCompleted) {
              advanced.complete();
            }
          })
        : null;
    final failure = Completer<void>();
    final ready = Completer<void>();
    final cancelled = _loadCancelled.future;
    final errors = player.playbackEventStream.listen(
      (_) {},
      onError: (Object error, StackTrace trace) {
        if (!failure.isCompleted) {
          failure.completeError(error, trace);
        }
      },
    );
    final states = player.playerStateStream.listen((state) {
      if (state.playing &&
          state.processingState == ProcessingState.ready &&
          !ready.isCompleted) {
        ready.complete();
      }
    });
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
        ready.future.then(
          (_) => Future<void>.delayed(const Duration(milliseconds: 180)),
        ),
        if (revision != null) cancelled,
      ]).timeout(const Duration(seconds: 8));
      if (revision != null && revision != _loadRevision) return;
      if (!player.playing || player.processingState != ProcessingState.ready) {
        throw WaveException(wt('native.2f44180776'));
      }
      if (verifyNativeProgress &&
          (player.duration == null ||
              player.duration! - startPosition > const Duration(seconds: 1)) &&
          player.position <= startPosition + const Duration(milliseconds: 20)) {
        // just_audio's playing flag is an intent. On desktop require decoded
        // clock progress before a handoff can silence the sending device.
        await Future.any<void>([
          advanced.future,
          failure.future,
          if (revision != null) cancelled,
        ]).timeout(const Duration(seconds: 3));
        if (revision != null && revision != _loadRevision) return;
      }
    } catch (error) {
      if (revision != null && revision != _loadRevision) return;
      await player.pause();
      rethrow;
    } finally {
      await positions?.cancel();
      if (!failure.isCompleted) {
        failure.complete();
      }
      await errors.cancel();
      await states.cancel();
    }
  }

  Future<void> _skip(int direction) async {
    if (trackLoading) return;
    if (tracks.isEmpty) {
      if (direction > 0) await localCommand('pause');
      return;
    }
    if (direction < 0 && outputPosition > const Duration(seconds: 3)) {
      await localCommand('seek', {'position': 0});
      return;
    }
    var next = _index + direction;
    if (direction > 0 && _index >= 0 && shuffle && tracks.length > 1) {
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
        await localCommand('pause');
        return;
      }
      next = 0;
    }
    await playTrack(tracks[next], list: tracks);
  }

  @override
  Future<dynamic> customAction(
    String name, [
    Map<String, dynamic>? extras,
  ]) async {
    if (name.startsWith('glukwave.like/')) {
      // Android System UI may omit CustomAction.extras. The action identity
      // itself binds the press to its song and account, including stale cards.
      if (viewCurrent != null && name == _likeAction(viewCurrent!.id)) {
        await onNotificationLike?.call();
      }
      return null;
    }
    if (name == 'glukwave.like') {
      if (extras?['trackId'] != null &&
          extras?['trackId'] == viewCurrent?.id &&
          (notificationScope == null ||
              extras?['scope'] == notificationScope?.call())) {
        await onNotificationLike?.call();
      }
      return null;
    }
    if (name == 'glukwave.widget') {
      final command = extras?['command'], scope = extras?['scope'];
      if (command is String &&
          scope is String &&
          widgetGrant != null &&
          extras?['grant'] == widgetGrant) {
        await onWidgetCommand?.call(command, scope);
      }
      return null;
    }
    return super.customAction(name, extras);
  }

  @override
  Future<void> setRating(Rating rating, [Map<String, dynamic>? extras]) async {
    final track = viewCurrent;
    if (track == null ||
        onNotificationLike == null ||
        !rating.isRated() ||
        rating.getRatingStyle() != RatingStyle.heart) {
      return;
    }
    if (extras?['trackId'] != null && extras?['trackId'] != track.id) return;
    if (extras?['scope'] != null &&
        extras?['scope'] != notificationScope?.call()) {
      return;
    }
    if (_isLiked(track.id) != rating.hasHeart()) {
      await onNotificationLike!.call();
    }
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
    if (trackLoading) return;
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
    if (index < 0 || index >= viewTracks.length) return;
    final track = viewTracks[index];
    if (!await _intercept('track', {
      'trackId': track.id,
      'queue': viewTracks.map((t) => t.id).toList(),
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
    final data = {
      'repeat': repeatMode == AudioServiceRepeatMode.one
          ? 'one'
          : repeatMode == AudioServiceRepeatMode.all
          ? 'all'
          : 'off',
    };
    if (!await _intercept('repeat', data)) await localCommand('repeat', data);
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    final data = {'enabled': shuffleMode != AudioServiceShuffleMode.none};
    if (!await _intercept('shuffle', data)) await localCommand('shuffle', data);
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
    cancelPendingLoad();
    _released = true;
    _positionTimer?.cancel();
    // A suspended UI subscription must not delay disposal of actual players.
    unawaited(_positions.close());
    _processingRevision++;
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    await player.dispose();
    provider.removeListener(_broadcast);
    await provider.clear();
    provider.dispose();
  }
}
