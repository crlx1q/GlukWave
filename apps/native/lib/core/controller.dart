import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import 'api.dart';
import 'playback_recovery.dart';
import 'qr_login.dart';
import 'models.dart';
import 'library_mutations.dart';
import 'discord.dart';
import 'appearance.dart';
import '../services/appearance_store.dart';
import '../services/audio.dart';
import '../services/volume_store.dart';
import '../services/cache.dart';
import '../services/energy.dart';
import '../services/background_connect.dart';
import '../services/desktop.dart';
import '../services/push.dart';
import '../services/waveform.dart';
import '../services/home_widgets.dart';
import '../l10n/home_widget_strings.dart';
import '../services/lan_transport.dart';
import '../l10n/lan_strings.dart';
import '../l10n/wave_localizations.dart';
import '../l10n/parity_strings.dart';

class WaveController extends ChangeNotifier {
  final EnergyPolicy energy = EnergyPolicy();
  final BackgroundConnectBridge backgroundConnect = BackgroundConnectBridge();
  bool backgroundConnectEnabled = true;
  Future<void> setBackgroundConnect(bool enabled) async {
    backgroundConnectEnabled = enabled;
    await preferences.setBool('backgroundConnect', enabled);
    await _syncBackgroundConnect(explicit: true);
    if (!_disposed) notifyListeners();
  }

  Future<void> _syncBackgroundConnect({bool explicit = false}) async {
    if (!backgroundConnect.supported || _disposed) return;
    final enabled = loggedIn && backgroundConnectEnabled;
    try {
      final available = await backgroundConnect.update(
        enabled,
        explicit: explicit,
      );
      if (enabled && !available && !_disposed) {
        backgroundConnectEnabled = false;
        await preferences.setBool('backgroundConnect', false);
        notifyListeners();
      }
    } catch (error) {
      api.diagnostics.report(
        error,
        kind: 'background',
        code: 'CONNECT_BACKGROUND',
      );
    }
  }

  String get energyMode => energy.mode;
  bool get energySaving => energy.saving;
  Future<void> setEnergyMode(String mode) => energy.setMode(mode);
  void setVisualForeground(bool foreground) {
    energy.foreground(foreground);
    audio.setVisualUpdatesEnabled(foreground);
  }

  List<WaveTrack> get savedTracks => cache.savedTracks;
  bool refreshing = false, _offlinePlayback = false;
  bool get localSavedPlayback => _offlinePlayback;
  Future<void> _metadataWrites = Future.value();
  final Map<String, Future<void>> _downloads = {};
  Future<void> _downloadTail = Future.value();
  String waveMode = 'personal', waveMood = 'personal';
  bool waveActive = false;
  int _waveVersion = 0, _stateSequence = 0;
  Future<bool>? _waveTail;
  bool _confirmingControl = false;
  String? _confirmingScope;
  final WaveApi api;
  final MusicCache cache;
  final WaveAudioHandler audio;
  final bool startMinimized;
  HomeWidgetBridge? homeWidgets;
  bool _homeWidgetsPaused = false, _homeArtworkBusy = false;
  String? _homeArtworkKey, _homeArtworkPath;
  DateTime _homeArtworkAttempt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _widgetCommandBusy = false;
  late final WaveformStore waveforms;
  final FlutterSecureStorage secure = const FlutterSecureStorage();
  late SharedPreferences preferences;
  AppearanceStore? appearanceStore;
  WaveCustomization get customization =>
      appearanceStore?.current ?? const WaveCustomization();
  String? _automaticLanguage;
  int _localeRequest = 0;
  String _previousLanguage = 'auto';
  bool _disposed = false;
  bool _desktopReady = false;
  String get osLanguage => supportedLanguage(
    WidgetsBinding.instance.platformDispatcher.locale.languageCode,
  );
  String get resolvedLanguage => customization.language == 'auto'
      ? _automaticLanguage ?? osLanguage
      : supportedLanguage(customization.language);
  void _applyLanguage() {
    final changed = api.language != resolvedLanguage;
    api.language = resolvedLanguage;
    WaveStrings.current = WaveStrings(resolvedLanguage);
    if (changed && socket?.connected == true) {
      socket!.emit('locale:change', {'language': resolvedLanguage});
    }
    if (changed && _desktopReady) {
      unawaited(desktop.localize().catchError((_) {}));
    }
  }

  /// Optional country metadata cannot replace a manual choice or another
  /// account/server's selection, even if its request finishes much later.
  Future<void> resolveAutomaticLanguage() async {
    final request = ++_localeRequest;
    final session = api.token, origin = api.server;
    if (customization.language != 'auto') return;
    try {
      final data = await api.localeMetadata(osLanguage);
      if (_disposed ||
          request != _localeRequest ||
          session != api.token ||
          origin != api.server ||
          customization.language != 'auto') {
        return;
      }
      final language = data['language'];
      if (language is! String || !languageNames.containsKey(language)) return;
      _automaticLanguage = language;
      await preferences.setString('autoLanguage:$origin', language);
      if (_disposed ||
          request != _localeRequest ||
          session != api.token ||
          origin != api.server ||
          customization.language != 'auto') {
        return;
      }
      _applyLanguage();
      notifyListeners();
    } catch (_) {
      // Cached metadata or the OS locale still works without a connection.
    }
  }

  Future<void> systemLocaleChanged() async {
    if (customization.language != 'auto' || _disposed) return;
    _localeRequest++;
    _automaticLanguage = null;
    _applyLanguage();
    notifyListeners();
    await resolveAutomaticLanguage();
  }

  late DesktopShell desktop;
  late WavePush push;
  DiscordConnection? discordConnection;
  bool discordLoading = false, discordChanging = false;
  String? discordError;
  int _discordGeneration = 0;
  io.Socket? socket;
  Timer? _heartbeat;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  WaveUser? user;
  Json config = {},
      settings = {
        'autoCache': true,
        'cacheLimitMB': 1024,
        'lyrics': true,
        'discordPresence': true,
        'reducedMotion': false,
      };
  List<WaveTrack> tracks = [], results = [];
  List<Json> artistResults = [], playlistResults = [];
  List<String> likedIds = [];
  List<Json> playlists = [],
      history = [],
      integrations = [],
      rooms = [],
      publicRooms = [],
      moderationRooms = [],
      devices = [],
      sessions = [],
      messages = [];
  int? nextPublicRoomOffset, nextModerationRoomOffset;
  bool roomDirectoryLoading = false;
  int _roomDirectoryViews = 0;
  Timer? _roomDirectoryTimer;
  Future<void>? _roomDirectoryFlight;
  String? currentSessionId, sessionsError;
  bool sessionsLoading = false, sessionsSupported = true;
  int _sessionsGeneration = 0;
  int _devicesGeneration = 0;
  Future<void>? _devicesFlight;
  String? _devicesFlightScope;
  bool _devicesDirty = false;
  final Set<String> pendingDeviceActions = {}, pendingSessionActions = {};
  bool connectChanging = false;
  Future<void>? _roomAdoption;
  String? _adoptingRoomId;
  String? _pendingOAuth;
  Future<void>? _logoutPending;
  Json? room;
  bool _roomOutputActive = true;
  int _roomGeneration = 0, _roomSyncGeneration = 0;
  bool loading = true, online = false, connected = false;
  int _selectionRevision = 0;
  bool transportPending = false;
  String? transferPending;
  Future<void>? _transferFlight;
  bool get trackLoading => transportPending || audio.trackLoading;
  bool get canSeek => canControl && !trackLoading;
  double? uploadProgress;
  String? error, notice, suggestion;
  int noticeRevision = 0,
      _searchRevision = 0,
      _roomRevision = -1,
      _clockOffset = 0;
  String deviceId = '';
  final String surfaceId = const Uuid().v4();
  Json connect = {};
  LanTransport? _lan;
  String? _lanOutputId, lanInvite, lanError;
  Json _lanState = {};
  Future<void> _lanSerial = Future.value();
  bool _lanReporting = false, _lanMutating = false;
  bool get lanEnabled => _lan != null;
  bool get lanHosting => _lan?.hosting == true;
  bool get lanActive =>
      _lan?.connected == true ||
      (_lan?.peers.any((p) => p['online'] == true) ?? false);
  String? get lanHostName => _lan?.hostName;
  List<Json> get lanPeers =>
      _lan?.peers
          .map((peer) => {...peer, 'isActive': peer['id'] == _lanOutputId})
          .toList() ??
      [];
  bool _localOutputActive = false;
  bool _provisionalOutput = false;
  int _accountGeneration = 0;
  int _deviceCommandGeneration = 0;
  int _accountRevision = -1;
  bool? _connectSupported;
  bool get independentListening => connect['independent'] == true;
  String? get activeDeviceId => _offlinePlayback
      ? deviceId
      : lanEnabled
      ? _lanOutputId
      : connect['activeDeviceId'] as String?;
  String? get activeSurfaceId =>
      _offlinePlayback ? surfaceId : connect['activeSurfaceId'] as String?;
  bool get controllingRemote => lanEnabled
      ? _lanOutputId != deviceId
      : !_offlinePlayback &&
            !_provisionalOutput &&
            !independentListening &&
            activeDeviceId != null &&
            (activeDeviceId != deviceId ||
                activeSurfaceId != null && activeSurfaceId != surfaceId);
  bool get outputHere => lanEnabled
      ? _lanOutputId == deviceId
      : _offlinePlayback ||
            _provisionalOutput ||
            independentListening ||
            activeDeviceId == deviceId &&
                (activeSurfaceId == null || activeSurfaceId == surfaceId) ||
            _connectSupported != true && _roomOutputActive;
  String? get activeRoomId => connect['roomId'] as String?;
  String get outputLabel => activeDeviceId == null
      ? wt('connect.noOutput')
      : wt('connect.playingOn', values: {'name': activeDeviceName});
  String get activeDeviceName => _offlinePlayback
      ? deviceName
      : lanEnabled
      ? (_lanOutputId == deviceId
            ? deviceName
            : lanPeers
                      .where((p) => p['id'] == _lanOutputId)
                      .map((p) => p['name']?.toString() ?? '')
                      .firstOrNull ??
                  wt('connect.otherDevice'))
      : devices
                .where(
                  (d) =>
                      d['deviceId'] == activeDeviceId ||
                      d['id'] == activeDeviceId,
                )
                .map((d) => d['name']?.toString() ?? '')
                .where((name) => name.isNotEmpty)
                .firstOrNull ??
            (connect['activeDeviceName'] as String?) ??
            (activeDeviceId == deviceId ? deviceName : null) ??
            wt('connect.otherDevice');
  String get deviceKind => Platform.isWindows
      ? 'windows'
      : Platform.isIOS
      ? 'ios'
      : 'android';
  String get deviceName =>
      'GlukWave · ${Platform.isWindows
          ? 'Windows'
          : Platform.isIOS
          ? 'iOS'
          : 'Android'}';
  bool get loggedIn => user != null;
  bool get canControl =>
      room == null ||
      user?.admin == true ||
      (user != null &&
          (room!['ownerId'] == user!.id ||
              room!['type'] != 'jam' &&
                  objects(room!['members']).any(
                    (member) =>
                        member['userId'] == user!.id &&
                        member['canControl'] == true &&
                        member['administrative'] != true,
                  )));
  bool get jamListener =>
      room?['type'] == 'jam' &&
      room?['ownerId'] != user?.id &&
      user?.admin != true;
  bool get canTogglePlayback => canControl || jamListener;
  bool get canManageRoom =>
      room != null && (user?.admin == true || room!['ownerId'] == user?.id);
  String get controlScope =>
      '$namespace:${room?['id']}:$activeDeviceId:$activeSurfaceId:$independentListening:${lanEnabled ? _lanOutputId : ''}';
  final Map<String, int> _controlRevisions = {};
  final Json _confirmedControls = {};
  Future<void> _controlWrites = Future.value();
  String? _previewScope;
  void _ensureControlScope() {
    if (_previewScope == controlScope) return;
    _previewScope = controlScope;
    _controlRevisions.clear();
    _confirmedControls.clear();
    _controlWrites = Future.value();
    audio.clearControlPreviews();
  }

  dynamic _controlValue(String field) => switch (field) {
    'volume' => audio.volume,
    'playing' => audio.playing,
    'shuffle' => audio.shuffle,
    _ => audio.repeat,
  };
  void previewVolume(double value) {
    _ensureControlScope();
    _confirmedControls.putIfAbsent('volume', () => audio.volume);
    unawaited(
      audio.previewControl(
        'volume',
        value.clamp(0, 1),
        localVolume: outputHere,
      ),
    );
    notifyListeners();
  }

  VoidCallback get cancelVolumeEdit {
    final scope = controlScope;
    return () => cancelVolumePreview(scope: scope);
  }

  void cancelVolumePreview({String? scope}) {
    if (_disposed || scope != null && scope != controlScope) return;
    _ensureControlScope();
    unawaited(audio.clearControlPreview('volume', localVolume: outputHere));
    _confirmedControls.remove('volume');
    notifyListeners();
  }

  String get namespace => const Uuid().v5(
    Namespace.url.value,
    '${api.server}:${user?.id ?? 'guest'}',
  );
  String get appUrl => config['appUrl'] as String? ?? api.server;
  bool get captchaEnabled =>
      (object(config['auth'])['turnstileSiteKey'] as String? ?? '').isNotEmpty;
  WaveController(
    this.api,
    this.cache,
    this.audio, {
    this.startMinimized = false,
  }) {
    _applyLanguage();
    waveforms = WaveformStore(api)..addListener(notifyListeners);
    desktop = DesktopShell(audio);
    push = WavePush(api);
    cache.addListener(notifyListeners);
    energy.addListener(_energyChanged);
    desktop.addListener(notifyListeners);
    audio.onError = (message) {
      api.diagnostics.report(message, kind: 'playback');
      tell(message);
    };
    audio.onProcessingChanged = notifyListeners;
    audio.onSourceFailure = _recoverFailedTrack;
    audio.onEnded = (track, repeat) async {
      if (_offlinePlayback) return false;
      if (lanEnabled) {
        if (outputHere) {
          if (repeat == AudioServiceRepeatMode.one &&
              audio.viewTracks.any((queued) => queued.id == track.id)) {
            await transport('seek', {'position': 0});
            await transport('play');
          } else {
            await transport('next');
          }
        }
        return true;
      }
      final active = room;
      if (active == null) {
        if (repeat == AudioServiceRepeatMode.none && await _refillWaveTail()) {
          await audio.localCommand('next');
          return true;
        }
        return false;
      }
      if (canControl &&
          _roomOutputActive &&
          outputHere &&
          object(active['state'])['trackId'] == track.id) {
        if (repeat == AudioServiceRepeatMode.none) await _refillWaveTail();
        await emitAck('room:command', {
          'roomId': active['id'],
          'command': 'ended',
          'trackId': track.id,
          'expectedRevision': _roomRevision,
          'repeat': repeat == AudioServiceRepeatMode.one
              ? 'one'
              : repeat == AudioServiceRepeatMode.all
              ? 'all'
              : 'off',
        });
      }
      return true;
    };
    audio.onTransport = (command, data) async {
      if (transportPending && ['pause', 'stop'].contains(command)) {
        await transport(command, data);
        return true;
      }
      if (lanEnabled) {
        await transport(command, data);
        return true;
      }
      if (command == 'next') {
        await transport(command, data);
        return true;
      }
      if (room == null &&
          !controllingRemote &&
          !(command == 'play' &&
              !independentListening &&
              _connectSupported == true &&
              activeDeviceId == null)) {
        return false;
      }
      await transport(command, data);
      return true;
    };
    audio.onNotificationLike = () async {
      final scope = namespace;
      final current = audio.viewCurrent;
      if (!_disposed && loggedIn && current != null && scope == namespace) {
        await like(current);
      }
    };
    audio.onLoadingChanged = () {
      notifyListeners();
      _report();
    };
    _subscriptions.add(
      audio.playbackState.listen((state) {
        if (state.playing && !audio.trackLoading && outputHere && waveActive) {
          unawaited(_refillWaveTail(early: true).catchError((_) => false));
        }
        notifyListeners();
        _report();
        unawaited(desktop.updateTitle());
      }),
    );
    _subscriptions.add(
      audio.mediaItem.listen((item) {
        notifyListeners();
        if (item != null && !lanEnabled) {
          unawaited(
            waveforms.load(item.id, offline: _offlinePlayback || !online),
          );
        }
        if (item != null &&
            online &&
            !_offlinePlayback &&
            !audio.remote &&
            !lanEnabled) {
          unawaited(
            api
                .call(
                  '/api/history',
                  method: 'POST',
                  data: {'trackId': item.id},
                )
                .catchError((_) => <String, dynamic>{}),
          );
        }
      }),
    );
  }
  void tell(String message) {
    notice = message;
    noticeRevision++;
    notifyListeners();
  }

  Future<void> restoreCustomizationScope() async {
    appearanceStore ??= AppearanceStore(api, preferences)
      ..addListener(_appearanceChanged);
    await appearanceStore!.selectScope(
      loggedIn ? namespace : null,
      fallback: loggedIn ? settings : {},
    );
  }

  Future<void> initialize() async {
    preferences = await SharedPreferences.getInstance();
    backgroundConnectEnabled = preferences.getBool('backgroundConnect') ?? true;
    await energy.initialize(preferences);
    var savedServer = preferences.getString('server');
    if (api.server == 'https://wave.gluk.tech' &&
        savedServer == 'http://192.168.3.7:4000') {
      // Retire the endpoint embedded in the previous LAN-only test build.
      await preferences.remove('server');
      savedServer = null;
    }
    if (savedServer != null) {
      try {
        api.server = WaveApi.validateServer(savedServer);
      } on WaveException catch (error) {
        tell(error.message);
        await preferences.remove('server');
      }
    }
    final storedLocale = preferences.getString('autoLanguage:${api.server}');
    if (languageNames.containsKey(storedLocale)) {
      _automaticLanguage = storedLocale;
    }
    _applyLanguage();
    deviceId = preferences.getString('deviceId') ?? const Uuid().v4();
    await preferences.setString('deviceId', deviceId);
    api.deviceId = deviceId;
    api.clientKind = deviceKind;
    api.deviceName = deviceName;
    api.surfaceId = surfaceId;
    try {
      await desktop.initialize(startMinimized: startMinimized);
      _desktopReady = true;
    } catch (e) {
      api.diagnostics.report(e, kind: 'background', code: 'DESKTOP_INIT');
      tell(wt('native.159f366d10', values: {'p0': (e)}));
    }
    if (Platform.isAndroid || Platform.isIOS) await audio.initializeSession();
    final volumeStore = DeviceVolumeStore(preferences);
    await audio.localCommand('volume', {'volume': volumeStore.value});
    audio.onVolumeChanged = volumeStore.save;
    final session = await secure.read(key: 'session:${api.server}');
    if (session != null) {
      final value = object(jsonDecode(session));
      api.token = value['token'] as String?;
      user = WaveUser(object(value['user']));
    }
    await cache.open(namespace);
    waveforms.open(cache.directory);
    await _restore();
    _mergeSavedTracks();
    await restoreCustomizationScope();
    _applyLanguage();
    unawaited(resolveAutomaticLanguage());
    await refresh();
    if (Platform.isAndroid) {
      homeWidgets = HomeWidgetBridge(
        onCommand: widgetCommand,
        onGrantChanged: (grant) => audio.widgetGrant = grant,
        onError: (error) => api.diagnostics.report(
          error,
          kind: 'background',
          code: 'HOME_WIDGET',
        ),
      );
      audio.onWidgetCommand = widgetCommand;
      addListener(_updateHomeWidgets);
      try {
        await homeWidgets!.initialize();
        audio.widgetGrant = homeWidgets!.grant;
        _updateHomeWidgets();
      } catch (error) {
        api.diagnostics.report(
          error,
          kind: 'background',
          code: 'HOME_WIDGET_INIT',
        );
        homeWidgets?.dispose();
        homeWidgets = null;
        audio.onWidgetCommand = null;
      }
    }
    _heartbeat = Timer.periodic(const Duration(seconds: 3), (_) {
      _report();
      if (room != null) unawaited(_correctDrift());
    });
  }

  Future<void> _restore() async {
    final directory = await cache.supportDirectory();
    final file = File(p.join(directory.path, 'state-$namespace.json'));
    if (!await file.exists()) return;
    try {
      final data = object(jsonDecode(await file.readAsString()));
      tracks = objects(data['tracks']).map(WaveTrack.new).toList();
      likedIds = List<String>.from(data['likedIds'] ?? []);
      playlists = objects(data['playlists']);
      history = objects(data['history']);
      settings = {...settings, ...object(data['settings'])};
      config = object(data['config']);
      _applySettings();
    } catch (_) {
      error = wt('native.25ed968e60');
    }
  }

  void _mergeSavedTracks() {
    final ids = tracks.map((track) => track.id).toSet();
    tracks = [
      ...tracks,
      ...savedTracks.where((track) => !ids.contains(track.id)),
    ];
  }

  Future<void> _persist() async {
    if (user == null || _logoutPending != null) return;
    final scope = namespace;
    final session = api.token;
    final confirmed = _libraryMutationScope == _editScope
        ? _libraryMutations?.base
        : null;
    final snapshot = jsonEncode({
      'tracks': confirmed?['tracks'] ?? tracks.map((t) => t.json).toList(),
      'likedIds': confirmed?['likedIds'] ?? likedIds,
      'playlists': confirmed?['playlists'] ?? playlists,
      'history': history,
      'settings': settings,
      'config': config,
    });
    final directory = await cache.supportDirectory();
    final operation = _metadataWrites.catchError((_) {}).then((_) async {
      if (_disposed ||
          scope != namespace ||
          user == null ||
          _logoutPending != null ||
          session != api.token) {
        return;
      }
      final file = File(p.join(directory.path, 'state-$scope.json'));
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(snapshot, flush: true);
      if (scope != namespace ||
          user == null ||
          _logoutPending != null ||
          session != api.token) {
        await temp.delete();
        return;
      }
      await temp.rename(file.path);
    });
    _metadataWrites = operation;
    await operation;
  }

  LibraryMutations? _libraryMutations;
  String? _libraryMutationScope;
  final Map<String, Future<void>> _libraryWrites = {};
  String get _editScope =>
      '$namespace:${api.server}:${api.token}:$_accountGeneration';
  LibraryMutations _edits() {
    if (_libraryMutationScope != _editScope) {
      _libraryMutationScope = _editScope;
      _libraryWrites.clear();
      _libraryMutations = LibraryMutations({
        'tracks': tracks.map((t) => t.json).toList(),
        'likedIds': likedIds,
        'playlists': playlists,
        'history': history,
      });
    }
    return _libraryMutations!;
  }

  List<String> get librarySaving => _libraryMutationScope == _editScope
      ? _libraryMutations?.saving ?? []
      : [];
  List<Json> playlistsForTrack(String id) => playlists
      .where((p) => List<String>.from(p['trackIds'] ?? []).contains(id))
      .toList();
  void _showLibraryEdits() {
    final value = _edits().visible;
    tracks = objects(value['tracks']).map(WaveTrack.new).toList();
    _mergeSavedTracks();
    likedIds = List<String>.from(value['likedIds'] ?? []);
    playlists = objects(value['playlists']);
    history = objects(value['history']);
    notifyListeners();
  }

  void _acceptLibrarySnapshot(Json value, int began) {
    _edits().acceptSnapshot(value, began);
    _showLibraryEdits();
  }

  Future<Json> _writeLibrary(
    LibraryEdit edit,
    Future<Json> Function() request,
  ) {
    final journal = _edits(), scope = _editScope;
    _showLibraryEdits();
    final result = Completer<Json>();
    final key = edit.key;
    late final Future<void> task;
    task = (_libraryWrites[key] ?? Future<void>.value())
        .catchError((_) {})
        .then((_) async {
          if (_disposed || scope != _editScope) {
            result.completeError(StateError('Library session changed'));
            return;
          }
          try {
            final response = await request();
            if (_disposed || scope != _editScope) {
              result.completeError(StateError('Library session changed'));
              return;
            }
            final saved = object(response['playlist']);
            if (edit.kind == 'create' &&
                (saved['id']?.toString() ?? '').isEmpty) {
              throw StateError('Playlist response is missing');
            }
            journal.acknowledge(edit, playlist: saved.isEmpty ? null : saved);
            _showLibraryEdits();
            unawaited(_persist().catchError((_) {}));
            result.complete(response);
          } catch (error, trace) {
            if (!_disposed && scope == _editScope) {
              journal.reject(edit);
              _showLibraryEdits();
              unawaited(_persist().catchError((_) {}));
            }
            result.completeError(error, trace);
          }
        });
    _libraryWrites[key] = task;
    unawaited(
      task.whenComplete(() {
        if (identical(_libraryWrites[key], task)) _libraryWrites.remove(key);
      }),
    );
    return result.future;
  }

  void acceptPlaylist(Json value) {
    if (value.isEmpty) return;
    _edits().acceptPlaylist(value);
    _showLibraryEdits();
    unawaited(_persist().catchError((_) {}));
  }

  Future<Json> createPlaylist(
    String name, {
    String description = '',
    bool public = false,
    List<String> ids = const [],
    List<WaveTrack> knownTracks = const [],
  }) async {
    final id = 'pending:${const Uuid().v4()}',
        draft = {
          'id': id,
          'name': name.trim(),
          'description': description,
          'public': public,
          'trackIds': ids,
        };
    final edit = _edits().begin('create:$id', 'create', id, {
      'playlist': draft,
      'knownTracks': knownTracks
          .where((track) => ids.contains(track.id))
          .map((track) => track.json)
          .toList(),
    });
    final data = await _writeLibrary(
      edit,
      () => api.call(
        '/api/playlists',
        method: 'POST',
        data: {
          'name': name.trim(),
          'description': description,
          'public': public,
          'trackIds': ids,
        },
      ),
    );
    final saved = object(data['playlist']);
    if (saved.isEmpty) throw StateError('Playlist response is missing');
    return saved;
  }

  Future<Json> updatePlaylist(String id, Json patch) async {
    if (id.startsWith('pending:')) throw StateError('Playlist is still saving');
    final edit = _edits().begin('playlist:$id', 'update', id, patch);
    final data = await _writeLibrary(
      edit,
      () => api.call(
        '/api/playlists/${Uri.encodeComponent(id)}',
        method: 'PATCH',
        data: patch,
      ),
    );
    return object(data['playlist']).isNotEmpty
        ? object(data['playlist'])
        : playlists.where((p) => p['id'] == id).firstOrNull ?? {};
  }

  Future<Json> setPlaylistTrack(
    String id,
    WaveTrack target,
    bool present,
  ) async {
    if (id.startsWith('pending:')) throw StateError('Playlist is still saving');
    final edit = _edits().begin('playlist:$id', 'membership', id, {
      'trackId': target.id,
      'present': present,
      'track': target.json,
    });
    final data = await _writeLibrary(
      edit,
      () => api.call(
        '/api/playlists/${Uri.encodeComponent(id)}/tracks/${Uri.encodeComponent(target.id)}',
        method: 'PUT',
        data: {'present': present},
      ),
    );
    return object(data['playlist']).isNotEmpty
        ? object(data['playlist'])
        : playlists.where((p) => p['id'] == id).firstOrNull ?? {};
  }

  Future<void> deletePlaylist(String id) async {
    if (id.startsWith('pending:')) return;
    final edit = _edits().begin('playlist:$id', 'delete', id, {});
    await _writeLibrary(
      edit,
      () => api.call(
        '/api/playlists/${Uri.encodeComponent(id)}',
        method: 'DELETE',
      ),
    );
  }

  Future<void>? _libraryRefresh;
  Future<void> refreshLibrary() {
    if (_libraryRefresh != null) return _libraryRefresh!;
    final session = api.token, origin = api.server;
    final task = () async {
      if (!loggedIn || !online || _disposed) return;
      final editRevision = _edits().revision;
      final data = await api.call('/api/library');
      if (_disposed || session != api.token || origin != api.server) return;
      _acceptLibrarySnapshot(data, editRevision);
      await _persist();
    }();
    _libraryRefresh = task;
    unawaited(
      task.then<void>(
        (_) {
          if (identical(task, _libraryRefresh)) _libraryRefresh = null;
        },
        onError: (Object _, StackTrace __) {
          if (identical(task, _libraryRefresh)) _libraryRefresh = null;
        },
      ),
    );
    return task;
  }

  Future<void> refresh() async {
    final session = api.token, origin = api.server;
    final localeRequest = _localeRequest;
    var reachedServer = false, verifiedSession = false;
    refreshing = true;
    loading = !loggedIn && tracks.isEmpty && savedTracks.isEmpty;
    error = null;
    notifyListeners();
    try {
      final serverConfig = await api.call('/api/config');
      if (session != api.token || origin != api.server) return;
      config = serverConfig;
      reachedServer = true;
      final locale = object(serverConfig['localization'])['language'];
      if (localeRequest == _localeRequest &&
          customization.language == 'auto' &&
          locale is String &&
          languageNames.containsKey(locale)) {
        _automaticLanguage = locale;
        _applyLanguage();
      }
      online = true;
      if (api.token != null) {
        final current = object((await api.call('/api/auth/me'))['user']);
        if (session != api.token || origin != api.server) return;
        if (current.isEmpty) {
          await logout(remote: false);
          return;
        }
        user = WaveUser(current);
        verifiedSession = true;
        final editRevision = _edits().revision;
        final data = await api.call('/api/library');
        if (session != api.token || origin != api.server) return;
        _acceptLibrarySnapshot(data, editRevision);
        final serverSettings = await api.call('/api/settings');
        await _receiveSettings(
          object(serverSettings['settings']),
          revision: (serverSettings['revision'] as num?)?.toInt(),
          expectedToken: session,
          expectedOrigin: origin,
        );
        if (session != api.token || origin != api.server) return;
        integrations = objects(
          (await api.call('/api/integrations'))['connections'],
        );
        final roomList = await api.call('/api/rooms');
        _receiveRoomDirectory(roomList);
        devices = objects((await api.call('/api/devices'))['devices']);
        await refreshConnect();
        _applySettings();
        await _persist();
        _connectSocket();
        await refreshDiscord(silent: true);
      }
    } catch (e) {
      if (session != api.token || origin != api.server) return;
      if (e is WaveException && (e.code == 'unauthorized' || e.status == 401)) {
        await logout(remote: false);
        error = wt('native.b217602ba0');
      } else {
        // A failed library/settings call is not an absent internet connection.
        online = reachedServer;
        if (verifiedSession) _connectSocket();
        error = e.toString();
      }
    } finally {
      refreshing = false;
      loading = false;
      notifyListeners();
    }
  }

  Future<void> setServer(String value) async {
    final next = WaveApi.validateServer(value);
    if (next == api.server) return;
    await logout(remote: false);
    api.server = next;
    _localeRequest++;
    _automaticLanguage = preferences.getString('autoLanguage:$next');
    if (!languageNames.containsKey(_automaticLanguage)) {
      _automaticLanguage = null;
    }
    _applyLanguage();
    await preferences.setString('server', next);
    await cache.open(namespace);
    waveforms.open(cache.directory);
    unawaited(resolveAutomaticLanguage());
    await refresh();
  }

  Future<void> authenticate(
    String email,
    String password, {
    String? username,
    String? displayName,
  }) async {
    final captchaToken = captchaEnabled ? await verifyCaptcha() : null;
    final result = await api.call(
      '/api/auth/${username != null ? 'register' : 'login'}',
      method: 'POST',
      data: {
        'email': email.trim(),
        'password': password,
        if (captchaToken != null) 'captchaToken': captchaToken,
        if (username != null) 'username': username.trim(),
        if (displayName != null) 'displayName': displayName.trim(),
      },
    );
    await acceptSession(result);
  }

  Future<String> verifyCaptcha() async {
    final bridge = await api.call(
      '/api/auth/native-captcha',
      method: 'POST',
      data: {},
    );
    await openUrl(bridge['url'] as String);
    final expires = challengeExpiry(bridge['expiresAt']);
    cancelAuth = false;
    while (!cancelAuth && DateTime.now().isBefore(expires)) {
      final result = await api.call(
        '/api/auth/native-captcha/${bridge['id']}',
        query: {'secret': bridge['secret']},
      );
      if (result['status'] == 'approved' && result['captchaToken'] is String) {
        return result['captchaToken'] as String;
      }
      if (result['status'] == 'expired') break;
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    throw WaveException(wt('native.b85fd36bb6'));
  }

  bool get supportsNativeCaptcha =>
      object(config['auth'])['nativeCaptcha'] == true;

  Future<void> requestPasswordReset(String email) async {
    final token = captchaEnabled ? await verifyCaptcha() : null;
    await api.call(
      '/api/auth/forgot',
      method: 'POST',
      data: {'email': email.trim(), if (token != null) 'captchaToken': token},
    );
  }

  Future<void> acceptSession(Json data) async {
    if (data['token'] is! String || object(data['user']).isEmpty) {
      throw WaveException(wt('native.d8b4826b17'));
    }
    if (user != null &&
        (user!.id != object(data['user'])['id'] ||
            api.token != data['token'])) {
      await logout(remote: false);
    }
    api.token = data['token'] as String;
    user = WaveUser(object(data['user']));
    await secure.write(
      key: 'session:${api.server}',
      value: jsonEncode({'token': api.token, 'user': user!.json}),
    );
    await cache.open(namespace);
    waveforms.open(cache.directory);
    await _restore();
    await appearanceStore?.selectScope(namespace, fallback: settings);
    _localeRequest++;
    _applyLanguage();
    unawaited(resolveAutomaticLanguage());
    await refresh();
  }

  Future<void> browserLogin({String method = 'google'}) async {
    final bridge = await api.call(
      '/api/auth/native',
      method: 'POST',
      data: {'method': method, 'deviceName': deviceName},
    );
    await openUrl(bridge['url'] as String);
    await pollSession(
      '/api/auth/native/${bridge['id']}',
      bridge['secret'] as String,
      challengeExpiry(bridge['expiresAt']),
    );
  }

  bool cancelAuth = false;
  ({String id, String? token, String origin, DateTime expires})? _qrApproval;
  Future<void> pollSession(String path, String secret, DateTime expires) async {
    cancelAuth = false;
    while (!cancelAuth && DateTime.now().isBefore(expires)) {
      final data = await api.call(path, query: {'secret': secret});
      if (data['status'] == 'approved') {
        await acceptSession(data);
        return;
      }
      if (data['status'] == 'expired') break;
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    if (!cancelAuth) {
      throw WaveException(wt('native.b85fd36bb6'));
    }
  }

  Future<void> approveQr(String value) async {
    if (user == null) {
      throw WaveException(wt('native.4c922f0c45'));
    }
    final id = _qrId(value);
    final approval = _qrApproval;
    if (approval == null ||
        approval.id != id ||
        approval.token != api.token ||
        approval.origin != api.server ||
        !approval.expires.isAfter(DateTime.now())) {
      throw WaveException(wt('native.b85fd36bb6'), 'CHALLENGE_EXPIRED');
    }
    await api.call('/api/auth/qr/$id/approve', method: 'POST', data: {});
    if (identical(approval, _qrApproval)) _qrApproval = null;
    if (approval.token == api.token &&
        approval.origin == api.server &&
        !_disposed) {
      tell(wt('native.e5eacefb73'));
    }
  }

  Future<Json> qrInfo(String value) async {
    if (!loggedIn) throw WaveException(wt('native.4c922f0c45'));
    _qrApproval = null;
    final id = _qrId(value), token = api.token, origin = api.server;
    final info = await api.call('/api/auth/qr/$id/info');
    if (token != api.token || origin != api.server || _disposed) {
      throw WaveException(wt('native.b85fd36bb6'), 'CHALLENGE_EXPIRED');
    }
    if (info['status'] != 'pending' ||
        !challengeExpiry(info['expiresAt']).isAfter(DateTime.now())) {
      throw WaveException(wt('native.b85fd36bb6'), 'CHALLENGE_EXPIRED');
    }
    _qrApproval = (
      id: id,
      token: token,
      origin: origin,
      expires: challengeExpiry(info['expiresAt']),
    );
    return info;
  }

  String _qrId(String value) {
    try {
      return qrChallengeId(value, api.server);
    } on FormatException {
      throw WaveException(wt('native.283b363614'), 'INVALID_LOGIN_CODE');
    }
  }

  Future<void> logout({bool remote = true}) async {
    if (_logoutPending != null) {
      await _logoutPending;
      return;
    }
    final pending = _performLogout(remote: remote);
    _logoutPending = pending;
    try {
      await pending;
    } finally {
      if (identical(_logoutPending, pending)) _logoutPending = null;
    }
  }

  Future<void> _performLogout({bool remote = true}) async {
    _qrApproval = null;
    _selectionRevision++;
    transportPending = false;
    audio.showPendingSelection(null);
    transferPending = null;
    _transferFlight = null;
    pendingDeviceActions.clear();
    _homeWidgetsPaused = true;
    _homeArtworkKey = _homeArtworkPath = null;
    try {
      await homeWidgets?.clear();
      audio.widgetGrant = homeWidgets?.grant;
    } catch (error) {
      api.diagnostics.report(
        error,
        kind: 'background',
        code: 'HOME_WIDGET_CLEAR',
      );
    }
    await setLanEnabled(false);
    cancelAuth = true;
    _adoptingRoomId = null;
    _roomAdoption = null;
    socket?.dispose();
    socket = null;
    connected = false;
    connect = {};
    _accountRevision = -1;
    _connectSupported = null;
    _localOutputActive = false;
    _offlinePlayback = false;
    audio.offlineOnly = false;
    _provisionalOutput = false;
    _accountGeneration++;
    _confirmingControl = false;
    _confirmingScope = null;
    _waveVersion++;
    _waveTail = null;
    waveActive = false;
    waveMode = waveMood = 'personal';
    _deviceCommandGeneration++;
    audio.clearRemote();
    room = null;
    _roomGeneration++;
    _roomSyncGeneration++;
    _roomOutputActive = false;
    _roomRevision = -1;
    await (await SharedPreferences.getInstance()).remove('room:$namespace');
    await audio.clear();
    await _metadataWrites.catchError((_) {});
    cache.activeId = null;
    await cache.clear(includingDownloads: true);
    await waveforms.clear();
    final metadata = File(
      p.join((await cache.supportDirectory()).path, 'state-$namespace.json'),
    );
    if (await metadata.exists()) {
      await metadata.delete();
    }
    audio.current = null;
    audio.tracks = [];
    audio.mediaItem.add(null);
    audio.queue.add([]);
    _discordGeneration++;
    discordConnection = null;
    discordLoading = discordChanging = false;
    discordError = null;
    await push.disable();
    if (remote && online) {
      try {
        await api.call('/api/auth/logout', method: 'POST');
      } catch (_) {
        /* Local session is still cleared. */
      }
    }
    await secure.delete(key: 'session:${api.server}');
    api.token = null;
    user = null;
    await _syncBackgroundConnect();
    await appearanceStore?.selectScope(null);
    _localeRequest++;
    _applyLanguage();
    tracks = [];
    playlists = [];
    likedIds = [];
    devices = [];
    sessions = [];
    currentSessionId = null;
    sessionsError = null;
    _sessionsGeneration++;
    _devicesGeneration++;
    _devicesFlight = null;
    _devicesFlightScope = null;
    _devicesDirty = false;
    _pendingOAuth = null;
    rooms = [];
    publicRooms = [];
    moderationRooms = [];
    nextPublicRoomOffset = nextModerationRoomOffset = null;
    _roomDirectoryTimer?.cancel();
    _roomDirectoryFlight = null;
    _previewScope = null;
    _ensureControlScope();
    history = [];
    integrations = [];
    config = {};
    loading = false;
    _homeWidgetsPaused = false;
    notifyListeners();
  }

  void _updateHomeWidgets() {
    if (_disposed || _homeWidgetsPaused || homeWidgets == null) return;
    final a = customization.appearance;
    final dark =
        customization.theme == 'dark' ||
        customization.theme == 'amoled' ||
        customization.theme == 'system' &&
            WidgetsBinding
                    .instance
                    .platformDispatcher
                    .platformBrightness
                    .name ==
                'dark';
    final palette = customization.theme == 'amoled'
        ? a.amoled
        : dark
        ? a.dark
        : a.light;
    final current = loggedIn ? audio.viewCurrent : null;
    final uri = loggedIn ? audio.mediaItem.value?.artUri : null;
    final artworkKey = '$namespace:$uri';
    if (_homeArtworkKey != artworkKey) {
      _homeArtworkKey = artworkKey;
      _homeArtworkPath = null;
      _homeArtworkAttempt = DateTime.fromMillisecondsSinceEpoch(0);
    }
    if (uri != null &&
        _homeArtworkPath == null &&
        !_homeArtworkBusy &&
        DateTime.now().difference(_homeArtworkAttempt).inSeconds >= 10) {
      _homeArtworkBusy = true;
      _homeArtworkAttempt = DateTime.now();
      unawaited(
        HomeWidgetBridge.cachedArtwork(uri)
            .then((path) {
              if (!_disposed &&
                  !_homeWidgetsPaused &&
                  artworkKey == _homeArtworkKey &&
                  path != null) {
                _homeArtworkPath = path;
                _updateHomeWidgets();
              }
            })
            .whenComplete(() => _homeArtworkBusy = false),
      );
    }
    // Progress is deliberately omitted: launcher updates follow real state
    // transitions, not a timer or per-frame position stream.
    homeWidgets!.update({
      'scope': loggedIn ? namespace : '',
      'signedIn': loggedIn,
      'title': current?.title ?? homeWidgetText('empty'),
      'artist': current?.artist ?? 'GlukWave',
      'trackId': current?.id ?? '',
      'artwork': _homeArtworkPath ?? '',
      'playing': loggedIn && audio.playing,
      'loading': loggedIn && trackLoading,
      'liked': current != null && likedIds.contains(current.id),
      'canToggle': loggedIn && current != null && canTogglePlayback,
      'canSkip': loggedIn && current != null && canControl,
      'canWave': loggedIn && canControl && !lanEnabled,
      'status': !loggedIn
          ? homeWidgetText('signedOut')
          : trackLoading
          ? homeWidgetText('loading')
          : controllingRemote
          ? outputLabel
          : !canControl
          ? homeWidgetText('permission')
          : current != null && !audio.playing
          ? homeWidgetText('paused')
          : homeWidgetText('ready'),
      'background': palette.surface,
      'ink': palette.ink,
      'accent': palette.accent,
      'labels': {
        for (final key in [
          'wave',
          'play',
          'pause',
          'previous',
          'next',
          'like',
          'unlike',
          'open',
        ])
          key: homeWidgetText(key),
      },
    });
  }

  void refreshHomeWidgetAppearance() => _updateHomeWidgets();

  Future<void> widgetCommand(String command, String scope) async {
    if (_disposed ||
        _homeWidgetsPaused ||
        !loggedIn ||
        scope != namespace ||
        !HomeWidgetBridge.commands.contains(command) ||
        _widgetCommandBusy) {
      return;
    }
    _widgetCommandBusy = true;
    try {
      if (command == 'like') {
        final current = audio.viewCurrent;
        if (current != null) await like(current);
      } else if (command == 'wave') {
        if (canControl && !lanEnabled) await startWave();
      } else if (command == 'toggle') {
        if (canTogglePlayback && audio.viewCurrent != null) {
          await transport(audio.playing ? 'pause' : 'play');
        }
      } else if (canControl && audio.viewCurrent != null) {
        await transport(command);
      }
    } catch (error) {
      api.diagnostics.report(error, kind: 'playback', code: 'WIDGET_COMMAND');
      tell(error.toString());
    } finally {
      _widgetCommandBusy = false;
      _updateHomeWidgets();
    }
  }

  Future<void> startWave({
    String mood = 'personal',
    String mode = 'personal',
  }) async {
    if (!loggedIn || !canControl || lanEnabled) return;
    final scope = namespace,
        session = api.token,
        origin = api.server,
        version = ++_waveVersion;
    final response = await api.call(
      '/api/recommendations',
      query: {
        'mood': mood,
        'mode': mode,
        'nonce': '${DateTime.now().millisecondsSinceEpoch}',
      },
    );
    if (_disposed ||
        !loggedIn ||
        namespace != scope ||
        session != api.token ||
        origin != api.server ||
        version != _waveVersion ||
        !canControl ||
        lanEnabled) {
      return;
    }
    final recommendations = objects(
      response['tracks'],
    ).map(WaveTrack.new).toList();
    if (recommendations.isEmpty) {
      throw WaveException(homeWidgetText('noTracks'));
    }
    online = true;
    // Resolve the selected source through the same permitted-audio pipeline as
    // the full app. Do not filter every unresolved provider out of discovery.
    waveMode = mode;
    waveMood = mood;
    waveActive = true;
    await play(
      recommendations.first,
      list: recommendations,
      preserveWave: true,
    );
  }

  final Set<String> _failedAudio = {};
  String _failureScope = '';
  DateTime _failureStarted = DateTime.fromMillisecondsSinceEpoch(0);
  Future<bool> _recoverFailedTrack(WaveTrack failed, Object error) async {
    if (_disposed ||
        !online ||
        _offlinePlayback ||
        lanEnabled ||
        !canControl ||
        !outputHere ||
        !unavailableAudio(error)) {
      return false;
    }
    if (_failureScope != namespace ||
        DateTime.now().difference(_failureStarted).inMinutes >= 1 ||
        (!audio.trackLoading &&
            audio.current?.id == failed.id &&
            audio.position.inSeconds > 5)) {
      _failedAudio.clear();
      _failureScope = namespace;
      _failureStarted = DateTime.now();
    }
    if (_failedAudio.contains(failed.id) || _failedAudio.length >= 5) {
      return false;
    }
    final items = audio.viewTracks,
        index = items.indexWhere((item) => item.id == failed.id);
    if (index < 0 || audio.viewCurrent?.id != failed.id) return false;
    _failedAudio.add(failed.id);
    final active = room;
    if (active != null) {
      if (object(active['state'])['trackId'] != failed.id ||
          !_roomOutputActive) {
        return false;
      }
      await emitAck('room:command', {
        'roomId': active['id'],
        'command': 'failed',
        'trackId': failed.id,
        'expectedRevision': _roomRevision,
      });
      return true;
    }
    final remaining = items
        .where((item) => !_failedAudio.contains(item.id))
        .toList();
    final tail = items
        .skip(index + 1)
        .where((item) => !_failedAudio.contains(item.id));
    final next = tail.isNotEmpty
        ? tail.first
        : audio.repeat == AudioServiceRepeatMode.all && remaining.isNotEmpty
        ? remaining.first
        : null;
    audio.replaceQueue(remaining);
    if (next == null) {
      await audio.localCommand('pause');
      return false;
    }
    audio.showPendingSelection(next);
    await audio.playTrack(next, list: remaining);
    if (!_disposed) _report();
    return true;
  }

  DateTime _waveRetryAfter = DateTime.fromMillisecondsSinceEpoch(0);
  Future<bool> _refillWaveTail({bool early = false}) {
    if (_waveTail != null) return _waveTail!;
    final current = audio.viewCurrent, items = audio.viewTracks;
    if (_offlinePlayback ||
        !loggedIn ||
        !online ||
        !canControl ||
        lanEnabled ||
        current == null ||
        !items.any((item) => item.id == current.id) ||
        audio.repeat == AudioServiceRepeatMode.all ||
        (early &&
            (!waveActive ||
                audio.repeat != AudioServiceRepeatMode.none ||
                DateTime.now().isBefore(_waveRetryAfter))) ||
        items.length - 1 - items.indexWhere((item) => item.id == current.id) >
            (early ? 3 : 0)) {
      return Future.value(false);
    }
    final scope = controlScope,
        session = api.token,
        origin = api.server,
        version = _waveVersion;
    final operation = () async {
      final ids = items.map((item) => item.id).toList();
      final query = <String, dynamic>{
        'mode': waveMode,
        'mood': waveMood,
        'seedTrackId': current.id,
        'exclude': ids
            .skip((ids.length - 100).clamp(0, ids.length).toInt())
            .join(','),
        'limit': 20,
        'nonce': '${DateTime.now().millisecondsSinceEpoch}',
      };
      var result = await api.call('/api/recommendations', query: query);
      if (objects(result['tracks']).isEmpty && waveMode != 'discovery') {
        result = await api.call(
          '/api/recommendations',
          query: {...query, 'exclude': current.id},
        );
      }
      if (_disposed ||
          session != api.token ||
          origin != api.server ||
          version != _waveVersion ||
          scope != controlScope ||
          audio.viewCurrent?.id != current.id) {
        return false;
      }
      final incoming = objects(
        result['tracks'],
      ).map(WaveTrack.new).where((item) => item.id != current.id).toList();
      if (incoming.isEmpty) {
        _waveRetryAfter = DateTime.now().add(const Duration(seconds: 20));
        return false;
      }
      final fresh = incoming.where((item) => !ids.contains(item.id)).toList(),
          additions = <WaveTrack>[];
      if (early && fresh.isEmpty) {
        _waveRetryAfter = DateTime.now().add(const Duration(seconds: 20));
        return false;
      }
      _waveRetryAfter = DateTime.now().add(const Duration(seconds: 20));
      additions.addAll(fresh.isNotEmpty ? fresh : incoming);
      final addedIds = additions.map((item) => item.id).toSet();
      final start = (items.indexWhere((item) => item.id == current.id) - 60)
          .clamp(0, items.length)
          .toInt();
      final order = [
        ...items.skip(start).where((item) => !addedIds.contains(item.id)),
        ...additions,
      ];
      for (final item in additions) {
        if (!tracks.any((value) => value.id == item.id)) tracks.add(item);
      }
      waveActive = true;
      if (room != null || controllingRemote) {
        await _transport('queue', {
          'queue': order.map((item) => item.id).toList(),
          'trackId': current.id,
          'waveMode': waveMode,
          'waveMood': waveMood,
          'waveActive': true,
        });
      } else {
        audio.replaceQueue(order);
        _report();
      }
      if (_disposed ||
          session != api.token ||
          origin != api.server ||
          version != _waveVersion ||
          scope != controlScope ||
          audio.viewCurrent?.id != current.id) {
        return false;
      }
      waveActive = true;
      notifyListeners();
      return true;
    }();
    _waveTail = operation;
    unawaited(
      operation.then<void>(
        (_) {
          if (identical(_waveTail, operation)) _waveTail = null;
        },
        onError: (Object _, StackTrace __) {
          _waveRetryAfter = DateTime.now().add(const Duration(seconds: 20));
          if (identical(_waveTail, operation)) _waveTail = null;
        },
      ),
    );
    return operation;
  }

  void _applySettings() {
    _applyLanguage();
    cache.limitMB = (settings['cacheLimitMB'] as num?)?.toInt() ?? 1024;
    audio.autoCache = settings['autoCache'] != false;
    unawaited(
      audio
          .applyProcessing(
            customization.equalizer,
            customization.playbackRate,
            inRoom: room != null,
          )
          .catchError((Object error) {
            tell(error.toString());
          }),
    );
  }

  void _appearanceChanged() {
    if (_previousLanguage != customization.language) {
      _previousLanguage = customization.language;
      _localeRequest++;
      if (_previousLanguage == 'auto') unawaited(resolveAutomaticLanguage());
    }
    settings = {
      ...settings,
      ...?appearanceStore?.serverSettings,
      ...customization.toSettings(),
    };
    _applySettings();
    notifyListeners();
  }

  Future<void> _receiveSettings(
    Json incoming, {
    int? revision,
    String? expectedToken,
    String? expectedOrigin,
  }) async {
    final session = expectedToken ?? api.token,
        origin = expectedOrigin ?? api.server;
    if (session == null || session != api.token || origin != api.server) return;
    if (appearanceStore != null &&
        !await appearanceStore!.receiveRemote(
          incoming,
          revision: revision,
          expectedToken: session,
          expectedOrigin: origin,
        )) {
      return;
    }
    if (session != api.token || origin != api.server) return;
    settings = {
      ...settings,
      ...?appearanceStore?.serverSettings,
      ...customization.toSettings(),
    };
    _applySettings();
    await _persist();
    if (session == api.token && origin == api.server) notifyListeners();
  }

  Object? beginSettingsEdit() => appearanceStore?.beginEdit();
  void endSettingsEdit(Object? token) => appearanceStore?.endEdit(token);

  Future<void> customize(Json changes) async {
    if (loggedIn &&
        user?.plan == 'free' &&
        requiresAdvancedAppearance(changes)) {
      throw WaveException(
        parityLabel(resolvedLanguage, 'Advanced'),
        'PLAN_LIMIT',
        403,
      );
    }
    if (changes.containsKey('language')) _localeRequest++;
    await appearanceStore?.change(changes);
    _applyLanguage();
    if (changes['language'] == 'auto') unawaited(resolveAutomaticLanguage());
  }

  Future<void> updateSettings(Json changes) async {
    final session = api.token, origin = api.server;
    final incoming = await api.call(
      '/api/settings',
      method: 'PATCH',
      data: changes,
    );
    await _receiveSettings(
      object(incoming['settings']),
      revision: (incoming['revision'] as num?)?.toInt(),
      expectedToken: session,
      expectedOrigin: origin,
    );
    if (session != api.token || origin != api.server) return;
    if (changes.containsKey('discordPresence')) {
      await refreshDiscord(silent: true);
    }
  }

  /// Discord is updated by the server's canonical Connect output, not by this
  /// client's playback or local Discord IPC. The endpoint is independently
  /// recoverable so a temporary Discord outage cannot interrupt app startup.
  Future<void> refreshDiscord({bool silent = false}) async {
    final token = api.token, origin = api.server;
    if (token == null || _disposed) return;
    final generation = ++_discordGeneration;
    discordLoading = true;
    if (!silent) notifyListeners();
    try {
      final data = await api.call('/api/discord');
      if (data['eligible'] is! bool) {
        throw const FormatException('Discord snapshot');
      }
      if (_disposed ||
          generation != _discordGeneration ||
          token != api.token ||
          origin != api.server) {
        return;
      }
      discordConnection = DiscordConnection(data);
      discordError = null;
    } catch (_) {
      if (_disposed ||
          generation != _discordGeneration ||
          token != api.token ||
          origin != api.server) {
        return;
      }
      // Provider details and internal errors do not belong in account settings.
      discordError = 'refresh_failed';
    } finally {
      if (!_disposed &&
          generation == _discordGeneration &&
          token == api.token &&
          origin == api.server) {
        discordLoading = false;
        notifyListeners();
      }
    }
  }

  void receiveDiscordState(Json data) {
    if (_disposed || api.token == null || data['eligible'] is! bool) return;
    _discordGeneration++;
    discordConnection = DiscordConnection(data);
    discordError = null;
    discordLoading = false;
    notifyListeners();
  }

  Future<void> updateDiscord(Json changes) async {
    if (discordChanging) return;
    final token = api.token, origin = api.server;
    final generation = ++_discordGeneration;
    discordChanging = true;
    discordLoading = false;
    discordError = null;
    notifyListeners();
    try {
      final data = await api.call(
        '/api/discord',
        method: 'PATCH',
        data: changes,
      );
      if (data['eligible'] is! bool) {
        throw const FormatException('Discord snapshot');
      }
      if (_disposed ||
          generation != _discordGeneration ||
          token != api.token ||
          origin != api.server) {
        return;
      }
      discordConnection = DiscordConnection(data);
    } catch (_) {
      if (!_disposed && token == api.token && origin == api.server) {
        discordError = 'save_failed';
      }
    } finally {
      if (!_disposed && token == api.token && origin == api.server) {
        discordChanging = false;
        notifyListeners();
      }
    }
  }

  Future<void> enablePush(bool enabled) async {
    if (enabled) {
      if (object(config['push'])['fcmEnabled'] != true) {
        throw WaveException(wt('native.81798ba3b3'));
      }
      await push.enable();
    } else {
      await push.disable();
    }
    await updateSettings({'notifications': enabled});
  }

  WaveTrack? track(String? id) {
    if (id == null) return null;
    for (final t in [...tracks, ...results, ...audio.tracks]) {
      if (t.id == id) return t;
    }
    return null;
  }

  Future<WaveTrack> requireTrack(String id) async =>
      track(id) ??
      WaveTrack(
        object(
          (await api.call('/api/tracks/${Uri.encodeComponent(id)}'))['track'],
        ),
      );
  Future<void> play(
    WaveTrack target, {
    List<WaveTrack>? list,
    bool preserveWave = false,
  }) async {
    if (!online && cache.contains(target.id) && !lanEnabled) {
      await playSaved(target, list: list);
      return;
    }
    if (_offlinePlayback && (online || !cache.contains(target.id))) {
      _resumeCloudPlayback();
    }
    if (!canControl) throw WaveException(wt('native.131b87ec38'));
    if (!preserveWave) {
      _waveVersion++;
      waveActive = false;
      waveMode = waveMood = 'personal';
    }
    final revision = ++_selectionRevision;
    transportPending = true;
    audio.showPendingSelection(target);
    notifyListeners();
    try {
      await _playSelection(target, list: list, revision: revision);
    } finally {
      if (revision == _selectionRevision) {
        transportPending = false;
        audio.showPendingSelection(null);
        if (!_disposed) notifyListeners();
      }
    }
  }

  Future<void> _playSelection(
    WaveTrack target, {
    List<WaveTrack>? list,
    required int revision,
  }) async {
    if (lanEnabled) {
      await _lanControl('transport', {
        'command': 'track',
        'trackId': target.id,
        'queue': (list ?? tracks).map((t) => t.id).toList(),
      });
      return;
    }
    if (!target.playable && target.source != 'local') {
      target = await api.resolvePlayback(target);
    }
    if (revision != _selectionRevision || _disposed) return;
    if (!target.playable) {
      final url = target.sourceUrl.isNotEmpty
          ? target.sourceUrl
          : target.playback['embedUrl'] as String? ?? '';
      if (url.isEmpty) {
        throw WaveException(wt('native.fb5429ae1b'));
      }
      throw WaveException(
        wt('provider.unavailable', values: {'source': target.sourceName}),
      );
    }
    final ids = (list ?? tracks)
        .where((t) => t.playable || t.id == target.id)
        .map((t) => t.id)
        .toList();
    if (room != null) {
      await transport('track', {
        'trackId': target.id,
        'queue': ids,
        'waveMode': waveMode,
        'waveMood': waveMood,
        'waveActive': waveActive,
      });
      return;
    }
    if (controllingRemote) {
      await commandDevice(activeDeviceId!, 'track', {
        'surfaceId': activeSurfaceId,
        'trackId': target.id,
        'queue': ids,
        'waveMode': waveMode,
        'waveMood': waveMood,
        'waveActive': waveActive,
      });
      return;
    }
    if (!independentListening &&
        _connectSupported == true &&
        online &&
        socket?.connected == true) {
      final claimed = await emitAck('device:claim', {});
      await receiveAccountState(object(claimed['connect']));
    }
    if (revision != _selectionRevision || _disposed) return;
    audio.clearRemote();
    _localOutputActive = true;
    await audio.playTrack(target, list: list ?? tracks);
    if (revision == _selectionRevision &&
        !_disposed &&
        !_offlinePlayback &&
        audio.sourceReady &&
        !cache.contains(target.id)) {
      online = true;
    }
    _report();
  }

  /// Saved music is a local listening session. It never waits for a stale room
  /// or Connect output and never resolves a signed network URL.
  Future<void> playSaved(WaveTrack target, {List<WaveTrack>? list}) async {
    final scope = namespace,
        session = api.token,
        revision = ++_selectionRevision;
    transportPending = true;
    audio.showPendingSelection(target);
    notifyListeners();
    try {
      if (await cache.fileFor(target.id) == null) {
        throw WaveException(lanText('cache'), 'OFFLINE_MISSING');
      }
      if (_disposed ||
          revision != _selectionRevision ||
          scope != namespace ||
          session != api.token) {
        return;
      }
      if (lanEnabled) await setLanEnabled(false);
      _offlinePlayback = true;
      // A disconnected output is removed from live listening by the server.
      // This device can keep playing private local files without broadcasting.
      socket?.dispose();
      socket = null;
      connected = false;
      _accountGeneration++;
      _deviceCommandGeneration++;
      await clearRoomParticipation(pause: false);
      if (_disposed ||
          revision != _selectionRevision ||
          scope != namespace ||
          session != api.token) {
        return;
      }
      waveActive = false;
      _waveVersion++;
      _waveTail = null;
      audio.offlineOnly = true;
      audio.clearRemote();
      _localOutputActive = true;
      final items = <String, WaveTrack>{
        for (final item in list ?? savedTracks)
          if (cache.contains(item.id)) item.id: item,
        target.id: target,
      }.values.toList();
      await audio.playTrack(target, list: items);
    } finally {
      if (revision == _selectionRevision) {
        transportPending = false;
        audio.showPendingSelection(null);
        if (!_disposed) notifyListeners();
      }
    }
  }

  void _resumeCloudPlayback() {
    _offlinePlayback = false;
    audio.offlineOnly = false;
    connect = {};
    _accountRevision = -1;
    _localOutputActive = true;
    _ensureControlScope();
    _connectSocket();
  }

  void _energyChanged() {
    audio.prepareNext = !energySaving;
    if (!_disposed) notifyListeners();
  }

  Future<Json> lyricsFor(WaveTrack track) async {
    final scope = namespace, session = api.token;
    final saved = await cache.lyricsFor(track.id);
    if (scope != namespace || session != api.token || _disposed) {
      return <String, dynamic>{'lines': []};
    }
    if (_offlinePlayback || !online) {
      return saved ?? <String, dynamic>{'lines': []};
    }
    try {
      final result = await api.call(
        '/api/tracks/${Uri.encodeComponent(track.id)}/lyrics',
      );
      if (_disposed || scope != namespace || session != api.token) {
        return <String, dynamic>{'lines': []};
      }
      if (objects(result['lines']).isNotEmpty) {
        await cache.saveLyrics(track.id, result);
        return result;
      }
      return saved ?? result;
    } catch (_) {
      return saved ?? <String, dynamic>{'lines': []};
    }
  }

  /// One bounded transfer at a time, including repeated taps on the same track.
  /// The server descriptor is the authority for download permission.
  Future<void> downloadTrack(WaveTrack track) {
    final key = '$namespace:${track.id}',
        scope = namespace,
        session = api.token;
    if (_downloads[key] != null) return _downloads[key]!;
    cache.queueDownload(track.id);
    late final Future<void> job;
    job = _downloadTail
        .catchError((_) {})
        .then((_) async {
          if (_disposed ||
              scope != namespace ||
              session != api.token ||
              _logoutPending != null ||
              cache.downloadCancelled(track.id)) {
            return;
          }
          final resolved = cache.contains(track.id)
              ? savedTracks.where((t) => t.id == track.id).firstOrNull ?? track
              : await api.resolvePlayback(track);
          if (_disposed ||
              scope != namespace ||
              session != api.token ||
              _logoutPending != null ||
              cache.downloadCancelled(track.id)) {
            return;
          }
          await cache.save(resolved, manual: true);
          if (scope == namespace &&
              session == api.token &&
              cache.contains(track.id)) {
            _mergeSavedTracks();
            await lyricsFor(resolved);
          }
        })
        .catchError((Object error) {
          if (scope == namespace &&
              session == api.token &&
              !cache.downloadCancelled(track.id)) {
            cache.failures[track.id] = error.toString();
          }
          throw error;
        })
        .whenComplete(() {
          if (identical(_downloads[key], job)) _downloads.remove(key);
          if (scope == namespace && session == api.token) {
            cache.finishQueuedDownload(track.id);
          }
        });
    _downloads[key] = job;
    _downloadTail = job.catchError((_) {});
    return job;
  }

  Future<void> downloadTracks(List<WaveTrack> tracks) async {
    final scope = namespace;
    Object? firstError;
    for (final track in <String, WaveTrack>{
      for (final track in tracks) track.id: track,
    }.values) {
      if (_disposed || scope != namespace || _logoutPending != null) break;
      try {
        await downloadTrack(track);
      } catch (error) {
        firstError ??= error;
      }
    }
    if (firstError != null) throw firstError;
  }

  Future<void> setQueue(List<WaveTrack> items) async {
    if (!canControl) throw WaveException(wt('native.131b87ec38'));
    if (_offlinePlayback) {
      items = items.where((track) => cache.contains(track.id)).toList();
    }
    for (final track in items) {
      if (!tracks.any((value) => value.id == track.id)) tracks.add(track);
    }
    if (room == null && !controllingRemote && !lanEnabled) {
      audio.replaceQueue(items);
      _report();
    } else {
      await transport('queue', {
        'queue': items.map((track) => track.id).toList(),
      });
    }
  }

  Future<void> addQueue(WaveTrack track) async {
    if (audio.viewTracks.any((item) => item.id == track.id)) return;
    await setQueue([...audio.viewTracks, track]);
  }

  Future<void> moveQueue(int from, int to) async {
    final items = List<WaveTrack>.of(audio.viewTracks);
    if (from < 0 ||
        from >= items.length ||
        to < 0 ||
        to >= items.length ||
        from == to) {
      return;
    }
    items.insert(to, items.removeAt(from));
    await setQueue(items);
  }

  Future<void> removeQueue(String id) =>
      setQueue(audio.viewTracks.where((track) => track.id != id).toList());

  Future<void> transport(String command, [Json data = const {}]) async {
    if (['next', 'previous'].contains(command)) {
      if (trackLoading || !canControl) return;
      final revision = ++_selectionRevision;
      transportPending = true;
      notifyListeners();
      try {
        if (command == 'next') {
          final current = audio.viewCurrent, items = audio.viewTracks;
          final tail =
              loggedIn &&
              online &&
              !lanEnabled &&
              current != null &&
              items.isNotEmpty &&
              items.last.id == current.id &&
              audio.repeat != AudioServiceRepeatMode.all;
          if (tail) {
            final scope = controlScope, available = await _refillWaveTail();
            if (revision != _selectionRevision ||
                scope != controlScope ||
                audio.viewCurrent?.id != current.id) {
              return;
            }
            if (!available) {
              await _transport('pause', const {});
              return;
            }
          }
        }
        await _transport(command, data);
      } finally {
        if (revision == _selectionRevision) {
          transportPending = false;
          if (!_disposed) notifyListeners();
        }
      }
      return;
    }
    if (command == 'pause' || command == 'stop') {
      _selectionRevision++;
      transportPending = false;
      audio.showPendingSelection(null);
    }
    if (['volume', 'play', 'pause', 'shuffle', 'repeat'].contains(command)) {
      if (command != 'volume' &&
          !(command == 'play' || command == 'pause'
              ? canTogglePlayback
              : canControl)) {
        throw WaveException(wt('native.131b87ec38'));
      }
      _ensureControlScope();
      final scope = controlScope, token = api.token, origin = api.server;
      final field = command == 'play' || command == 'pause'
          ? 'playing'
          : command;
      final revision = (_controlRevisions[field] ?? 0) + 1;
      _controlRevisions[field] = revision;
      _confirmedControls.putIfAbsent(field, () => _controlValue(field));
      final value = switch (field) {
        'playing' => command == 'play',
        'volume' => number(data['volume']).clamp(0, 1),
        'shuffle' => data['enabled'] == true,
        _ =>
          data['repeat'] == 'one'
              ? AudioServiceRepeatMode.one
              : data['repeat'] == 'all'
              ? AudioServiceRepeatMode.all
              : AudioServiceRepeatMode.none,
      };
      await audio.previewControl(
        field,
        value,
        localVolume: field == 'volume' && outputHere,
      );
      if (field == 'playing' &&
          outputHere &&
          audio.current != null &&
          (command == 'pause' || audio.sourceReady)) {
        unawaited(audio.localCommand(command).catchError((_) {}));
      }
      if (!_disposed) notifyListeners();
      final operation = _controlWrites.catchError((_) {}).then((_) async {
        if (token != api.token ||
            origin != api.server ||
            scope != controlScope ||
            _controlRevisions[field] != revision) {
          return;
        }
        try {
          _confirmingControl = true;
          _confirmingScope = scope;
          await _transport(command, data);
          if (token != api.token ||
              origin != api.server ||
              scope != controlScope) {
            return;
          }
          if (!_offlinePlayback &&
              socket?.connected == true &&
              outputHere &&
              !lanEnabled) {
            final sent = snapshot().toJson();
            for (var attempt = 0; attempt < 2; attempt++) {
              final ack = await emitAck('device:state', {
                ...sent,
                'sequence': ++_stateSequence,
                'confirm': true,
                'outputActive': true,
                'roomId': room?['id'],
                'trackLoading': trackLoading,
              });
              final confirmed = object(ack['connect']),
                  state = object(confirmed['state']);
              final expected = field == 'repeat'
                  ? (value == AudioServiceRepeatMode.one
                        ? 'one'
                        : value == AudioServiceRepeatMode.all
                        ? 'all'
                        : 'off')
                  : value;
              if (state[field] == expected) {
                await receiveAccountState(confirmed);
                break;
              }
              if (attempt == 1) {
                throw WaveException(
                  wt('native.7e03f83d51'),
                  'PLAYBACK_CHANGED',
                );
              }
            }
          }
          if (token != api.token ||
              origin != api.server ||
              scope != controlScope) {
            return;
          }
          _confirmedControls[field] = value;
          audio.acceptControl(field, value);
        } catch (_) {
          if (token == api.token &&
              origin == api.server &&
              scope == controlScope &&
              _controlRevisions[field] == revision) {
            final confirmed = _confirmedControls[field];
            final rollback = switch (field) {
              'playing' => {'command': confirmed == true ? 'play' : 'pause'},
              'shuffle' => {'command': 'shuffle', 'enabled': confirmed},
              'repeat' => {
                'command': 'repeat',
                'repeat': confirmed == AudioServiceRepeatMode.one
                    ? 'one'
                    : confirmed == AudioServiceRepeatMode.all
                    ? 'all'
                    : 'off',
              },
              _ => {'command': 'volume', 'volume': confirmed},
            };
            if (outputHere) {
              await audio.localCommand(rollback['command'] as String, rollback);
            } else {
              await audio.previewControl(field, confirmed);
            }
          }
          rethrow;
        } finally {
          if (token == api.token &&
              origin == api.server &&
              scope == controlScope &&
              _controlRevisions[field] == revision) {
            await audio.clearControlPreview(
              field,
              localVolume: field == 'volume' && outputHere,
            );
            _confirmedControls.remove(field);
            if (!_disposed) notifyListeners();
          }
          if (_confirmingScope == scope &&
              token == api.token &&
              origin == api.server) {
            _confirmingControl = false;
            _confirmingScope = null;
          }
        }
      });
      _controlWrites = operation.catchError((_) {});
      await operation;
      return;
    }
    await _transport(command, data);
  }

  Future<void> _transport(String command, Json data) async {
    // A user seek must not target the old source while its replacement loads.
    // Internal room/Connect synchronization still uses audio.localCommand.
    if (command == 'seek' && trackLoading) return;
    if (lanEnabled) {
      await _lanControl('transport', {'command': command, ...data});
      return;
    }
    if (jamListener && ['play', 'pause'].contains(command)) {
      final result = await api.call(
        '/api/jams/${room!['id']}/pause',
        method: 'POST',
        data: {'paused': command == 'pause'},
      );
      if (result['connect'] is Map) {
        await receiveAccountState(object(result['connect']));
      } else {
        await refreshConnect();
      }
      return;
    }
    if (room != null && command != 'volume') {
      if (!canControl) {
        throw WaveException(wt('native.131b87ec38'));
      }
      if (!independentListening &&
          activeDeviceId == null &&
          ['play', 'track', 'next', 'previous'].contains(command)) {
        final joined = await emitAck('room:join', {'roomId': room!['id']});
        if (joined['connect'] is Map) {
          await receiveAccountState(object(joined['connect']));
        }
      }
      final id = room!['id'];
      final response = await emitAck('room:command', {
        'roomId': id,
        'command': command,
        ...data,
      });
      if (room?['id'] == id && response['state'] is Map) {
        await receiveRoomState({
          'roomId': id,
          'state': response['state'],
          'serverTime': response['serverTime'],
        });
      }
    } else if (controllingRemote) {
      await commandDevice(activeDeviceId!, command, {
        'surfaceId': activeSurfaceId,
        ...data,
      });
    } else {
      if (command == 'play' &&
          !independentListening &&
          _connectSupported == true &&
          activeDeviceId == null &&
          audio.viewCurrent != null) {
        await play(audio.viewCurrent!, list: audio.viewTracks);
        return;
      }
      await audio.localCommand(command, data);
      _report();
    }
  }

  Future<void> like(WaveTrack t) async {
    final liked = !likedIds.contains(t.id);
    final edit = _edits().begin('like:${t.id}', 'like', t.id, {
      'liked': liked,
      'track': t.json,
    });
    await _writeLibrary(
      edit,
      () => api.call(
        '/api/library/likes/${Uri.encodeComponent(t.id)}',
        method: 'PUT',
        data: {'liked': liked},
      ),
    );
  }

  Future<void> search(String query, {String source = 'all'}) async {
    final revision = ++_searchRevision;
    if (query.trim().isEmpty) {
      results = [];
      artistResults = [];
      playlistResults = [];
      suggestion = null;
      notifyListeners();
      return;
    }
    final data = await api.call(
      '/api/search',
      query: {'q': query.trim(), 'source': source},
    );
    if (revision != _searchRevision) return;
    results = objects(data['tracks']).map(WaveTrack.new).toList();
    artistResults = objects(data['artists']);
    playlistResults = objects(data['playlists']);
    suggestion = data['suggestion'] as String?;
    final failures = objects(data['errors']);
    if (failures.isNotEmpty) {
      tell(failures.map((e) => e['message'] ?? e['provider']).join(' · '));
    }
    notifyListeners();
  }

  Future<void> searchArtist(Json artist) => search(
    artist['name'] as String,
    source: artist['source'] as String? ?? 'all',
  );

  Future<void> resolve(String url) async {
    final t = WaveTrack(
      object(
        (await api.call(
          '/api/tracks/resolve',
          method: 'POST',
          data: {'url': url.trim()},
        ))['track'],
      ),
    );
    await like(t);
    await refresh();
    tell(wt('native.239486deb5'));
  }

  Future<void> uploadAudio() async {
    final selection = await FilePicker.pickFiles(
      type: FileType.audio,
      allowMultiple: true,
    );
    if (selection == null) return;
    try {
      for (final file in selection.files) {
        if (file.path == null) continue;
        uploadProgress = 0;
        notifyListeners();
        await api.upload(
          '/api/tracks/upload',
          file.path!,
          progress: (value) {
            uploadProgress = value;
            notifyListeners();
          },
        );
      }
      await refresh();
      tell(wt('native.90bb5d60ca'));
    } finally {
      uploadProgress = null;
      notifyListeners();
    }
  }

  Future<void> importFile() async {
    final selection = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'json'],
    );
    final path = selection?.files.single.path;
    if (path == null) return;
    final data = await api.upload('/api/integrations/import-file', path);
    await refresh();
    tell(wt('native.b2ac0da1b6', values: {'p0': (data['imported'])}));
  }

  Future<void> playlist(String name, {List<String> ids = const []}) async {
    await createPlaylist(name, ids: ids);
  }

  Future<void> addToPlaylist(Json playlist, WaveTrack target) async {
    await setPlaylistTrack(playlist['id'].toString(), target, true);
  }

  Future<void> connectProvider(String provider) async {
    final data = await api.call(
      '/api/integrations/$provider/connect',
      method: 'POST',
      data: {},
    );
    _pendingOAuth = provider;
    try {
      await openUrl(data['url'] as String);
    } catch (_) {
      _pendingOAuth = null;
      rethrow;
    }
    tell(wt('native.b1426ae61b'));
  }

  /// OAuth happens in the system browser. Returning to the app asks the server
  /// for the real connection, rather than treating a browser launch as success.
  Future<void> applicationResumed() async {
    if (api.token == null || _offlinePlayback) return;
    await _syncBackgroundConnect();
    if (socket?.connected == false) socket!.connect();
    final token = api.token, origin = api.server, pending = _pendingOAuth;
    try {
      final data = await api.call('/api/integrations');
      if (_disposed || token != api.token || origin != api.server) return;
      integrations = objects(data['connections']);
      if (pending != null &&
          integrations.any(
            (entry) =>
                entry['provider'] == pending && entry['connected'] == true,
          )) {
        _pendingOAuth = null;
        tell(wt('connections.connected', values: {'name': pending}));
      }
      await refreshConnect();
      await refreshSessions();
      await refreshDiscord(silent: true);
      notifyListeners();
    } catch (error) {
      if (pending != null && token == api.token && origin == api.server) {
        tell(wt('connections.refreshFailed'));
      }
    }
  }

  Future<void> disconnectProvider(String provider) async {
    await api.call('/api/integrations/$provider', method: 'DELETE');
    await refresh();
  }

  Future<void> updateProfile(Json changes) async {
    user = WaveUser(
      object(
        (await api.call(
          '/api/profile',
          method: 'PATCH',
          data: changes,
        ))['user'],
      ),
    );
    await secure.write(
      key: 'session:${api.server}',
      value: jsonEncode({'token': api.token, 'user': user!.json}),
    );
    notifyListeners();
  }

  Future<void> uploadProfile(String kind) async {
    final selection = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'webp', 'gif'],
    );
    final path = selection?.files.single.path;
    if (path == null) return;
    user = WaveUser(
      object(
        (await api.upload(
          '/api/profile/media',
          path,
          fields: {'kind': kind},
        ))['user'],
      ),
    );
    notifyListeners();
  }

  Future<void> removeProfileMedia(String kind) async {
    if (!['avatar', 'banner'].contains(kind)) return;
    final response = await api.call(
      '/api/profile/media/$kind',
      method: 'DELETE',
    );
    final changed = object(response['user']);
    if (changed.isNotEmpty) user = WaveUser(changed);
    if (user != null && api.token != null) {
      await secure.write(
        key: 'session:${api.server}',
        value: jsonEncode({'token': api.token, 'user': user!.json}),
      );
    }
    await _persist();
    notifyListeners();
  }

  void _connectSocket() {
    if (_offlinePlayback || socket != null || api.token == null) return;
    unawaited(_syncBackgroundConnect());
    final session = api.token, origin = api.server;
    socket = io.io(
      api.server,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .enableForceNew()
          .setAuth({
            'token': api.token,
            'language': resolvedLanguage,
            'deviceId': deviceId,
            'surfaceId': surfaceId,
            'name': deviceName,
            'kind': deviceKind,
          })
          .build(),
    );
    socket!.onConnect((_) async {
      connected = true;
      notifyListeners();
      await refreshConnect();
      if (session != api.token || origin != api.server) return;
      unawaited(refreshDiscord(silent: true));
      _report();
      if (room != null) {
        unawaited(_rejoinRoom().catchError((_) {}));
      }
    });
    socket!.onDisconnect((_) {
      connected = false;
      notifyListeners();
    });
    socket!.onConnectError((error) {
      api.diagnostics.report('Socket connection failed', kind: 'socket');
      connected = false;
      notifyListeners();
    });
    socket!.on('settings:changed', (data) {
      if (session != api.token || origin != api.server) return;
      final envelope = object(data);
      unawaited(
        _receiveSettings(
          object(envelope['settings']),
          revision: (envelope['revision'] as num?)?.toInt(),
          expectedToken: session,
          expectedOrigin: origin,
        ).catchError((error) {
          if (session == api.token && origin == api.server) {
            tell(error.toString());
          }
        }),
      );
    });
    socket!.on('devices:changed', (data) {
      if (session != api.token || origin != api.server) return;
      unawaited(receiveDeviceChange(data).catchError((_) {}));
    });
    socket!.on('sessions:changed', (_) {
      if (session != api.token || origin != api.server) return;
      unawaited(refreshSessions());
    });
    socket!.on('library:changed', (_) {
      if (session != api.token || origin != api.server) return;
      unawaited(refreshLibrary().catchError((_) {}));
    });
    socket!.on('integrations:changed', (_) {
      if (session != api.token || origin != api.server) return;
      unawaited(refreshDiscord(silent: true));
    });
    socket!.on('discord:changed', (data) {
      if (session != api.token || origin != api.server) return;
      final state = object(data);
      if (state['eligible'] is bool) {
        receiveDiscordState(state);
      } else {
        unawaited(refreshDiscord(silent: true));
      }
    });
    socket!.on('account:state', (data) {
      if (session != api.token || origin != api.server) return;
      unawaited(
        receiveAccountState(object(data)).catchError((error) {
          api.diagnostics.report(error, kind: 'socket', code: 'ACCOUNT_STATE');
        }),
      );
    });
    socket!.on('session:revoked', (_) {
      if (session != api.token || origin != api.server) return;
      socket?.disconnect();
      socket?.dispose();
      socket = null;
      unawaited(logout(remote: false).then((_) => tell(wt('connect.revoked'))));
    });
    socket!.on('device:command', (event) async {
      final data = event is List ? object(event.first) : object(event);
      final ack = event is List && event.last is Function
          ? event.last as Function
          : null;
      try {
        await receiveDeviceCommand(data);
        ack?.call({'ok': true, 'state': snapshot().toJson()});
      } catch (e) {
        api.diagnostics.report(e, kind: 'playback', code: 'DEVICE_COMMAND');
        ack?.call({
          'error': {
            'code': e is WaveException ? e.code : 'PLAYBACK_FAILED',
            'message': e.toString(),
            if (e is WaveException && e.status != null) 'status': e.status,
          },
        });
        tell(e.toString());
      }
    });
    socket!.on('room:state', (data) {
      unawaited(
        receiveRoomState(object(data)).catchError((e) {
          api.diagnostics.report(e, kind: 'socket', code: 'ROOM_STATE');
          tell(e.toString());
        }),
      );
    });
    socket!.on('room:directory', (_) {
      if (session != api.token ||
          origin != api.server ||
          _roomDirectoryViews == 0) {
        return;
      }
      _roomDirectoryTimer?.cancel();
      _roomDirectoryTimer = Timer(
        const Duration(milliseconds: 250),
        () => unawaited(refreshRoomDirectory().catchError((_) {})),
      );
    });
    socket!.on('room:members', (data) {
      final update = object(data);
      if (room != null && update['roomId'] == room!['id']) {
        room!['members'] = update['members'];
        final members = objects(room!['members']);
        room!['memberCount'] = members.length;
        room!['onlineCount'] = members.where((m) => m['online'] == true).length;
        room!['listeningCount'] = members
            .where(
              (m) =>
                  m['online'] == true &&
                  objects(m['devices']).any(
                    (d) =>
                        d['outputActive'] == true &&
                        d['playing'] == true &&
                        d['online'] != false,
                  ),
            )
            .length;
        if (!objects(room!['members']).any((m) => m['userId'] == user?.id)) {
          unawaited(clearRoomParticipation());
        }
        notifyListeners();
      }
    });
    socket!.on('room:closed', (data) {
      if (session != api.token || origin != api.server) return;
      final closed = object(data);
      if ((closed['roomId'] ?? closed['id']) == room?['id']) {
        unawaited(clearRoomParticipation());
      }
    });
    socket!.on('room:left', (data) {
      if (session != api.token || origin != api.server) return;
      if (object(data)['roomId'] == room?['id']) {
        unawaited(clearRoomParticipation());
      }
    });
    socket!.on('room:message', (data) {
      final update = object(data);
      if (update['roomId'] == room?['id']) {
        final message = object(update['message']);
        if (!messages.any((m) => m['id'] == message['id'])) {
          messages.add(message);
        }
        notifyListeners();
      }
    });
    socket!.on('notification', (data) {
      final value = object(data);
      tell(
        '${value['title'] ?? 'GlukWave'}${value['body'] != null ? ': ${value['body']}' : ''}',
      );
    });
    socket!.connect();
  }

  Future<void> setLanEnabled(bool enabled) async {
    if (enabled == lanEnabled) return;
    if (!enabled) {
      final previous = _lan;
      _lan = null;
      audio.offlineOnly = false;
      await previous?.close();
      if (previous != null) await audio.suspendLocalOutput();
      audio.clearRemote();
      _lanOutputId = null;
      _lanState = {};
      lanInvite = lanError = null;
      _localOutputActive = false;
      if (!_disposed) notifyListeners();
      return;
    }
    if (user == null) throw WaveException(lanText('account'));
    if (room != null) throw WaveException(lanText('room'));
    _offlinePlayback = false;
    Json trusted = {};
    try {
      trusted = object(
        jsonDecode(await secure.read(key: 'lan:$namespace') ?? '{}'),
      );
    } catch (_) {}
    final scope = namespace;
    final local = LanTransport(
      account: scope,
      deviceId: deviceId,
      name: deviceName,
      kind: deviceKind,
      maximumPeers: ['beta', 'unbound'].contains(user!.plan) ? 10 : 3,
      trusted: trusted,
      command: _lanCommand,
      state: _receiveLanState,
      changed: () {
        if (!_disposed && _lan != null) {
          _lanChanged();
          notifyListeners();
        }
      },
      persist: (value) =>
          secure.write(key: 'lan:$scope', value: jsonEncode(value)),
    );
    _lan = local;
    audio.offlineOnly = true;
    _lanOutputId = deviceId;
    _lanMutating = true;
    try {
      await local.start();
      if (audio.current != null && !cache.contains(audio.current!.id)) {
        await audio.suspendLocalOutput();
      }
      audio.tracks = audio.tracks
          .where((t) => cache.contains(t.id))
          .take(100)
          .toList();
      if (audio.current != null && cache.contains(audio.current!.id)) {
        final before = snapshot();
        await audio.playTrack(
          await _lanCached(audio.current!.id),
          list: audio.tracks,
          position: before.position,
          playing: before.playing,
        );
      }
      audio.clearRemote();
      _localOutputActive = false;
      socket?.emit('device:state', {
        ...snapshot().toJson(),
        'playing': false,
        'outputActive': false,
        'roomId': null,
      });
      await _publishLan();
      _lanMutating = false;
    } catch (_) {
      _lan = null;
      audio.offlineOnly = false;
      _lanMutating = false;
      await local.close();
      throw WaveException(lanText('network'));
    }
    notifyListeners();
  }

  Future<void> createLanInvite() async {
    await setLanEnabled(true);
    if (!lanHosting) throw WaveException(lanText('busy'));
    try {
      lanInvite = await _lan!.invite();
      lanError = null;
      notifyListeners();
    } catch (_) {
      throw WaveException(lanText('network'));
    }
  }

  Future<void> connectLan(String invitation) async {
    await setLanEnabled(true);
    try {
      await audio.suspendLocalOutput();
      await _lan!.join(invitation);
      lanInvite = lanError = null;
      final state = await _lan!.request('snapshot', {});
      await _receiveLanState(state);
    } catch (error) {
      lanError = lanText(
        error is StateError
            ? error.message.toString()
            : error is FormatException && error.message == 'LAN account'
            ? 'account'
            : error is FormatException
            ? 'invitation'
            : 'network',
      );
      notifyListeners();
      throw WaveException(lanError!);
    }
  }

  Future<void> disconnectLan() async {
    await setLanEnabled(false);
  }

  Future<void> removeLanPeer(String id) async {
    await _lan?.remove(id);
    _lanChanged();
    if (!_disposed) notifyListeners();
  }

  void _lanChanged() {
    final local = _lan;
    if (local == null) return;
    if (local.lastError != null) lanError = lanText('network');
    final output = _lanOutputId;
    final lost = local.hosting
        ? output != null &&
              output != deviceId &&
              !local.peers.any((p) => p['id'] == output && p['online'] == true)
        : !local.connected;
    if (lost) {
      if (output == deviceId) unawaited(audio.suspendLocalOutput());
      final value = object(_lanState['state']);
      if (value.isNotEmpty && value['playing'] == true) {
        _lanState = {
          ..._lanState,
          'state': {
            ...value,
            'playing': false,
            'updatedAt': DateTime.now().millisecondsSinceEpoch,
          },
        };
        if (output != deviceId) {
          audio.showRemote(
            PlaybackSnapshot.fromJson(object(_lanState['state'])),
            audio.viewCurrent,
            audio.viewTracks,
          );
        }
      }
    }
  }

  Json _localLanState() => {
    'state': snapshot().toJson(),
    'track': audio.current?.json,
    'queueTracks': audio.tracks.map((t) => t.json).toList(),
    'activeDeviceId': _lanOutputId,
    'activeDeviceName': activeDeviceName,
  };
  Future<void> _publishLan() async {
    if (_lan?.hosting != true) return;
    if (_lanOutputId == deviceId) _lanState = _localLanState();
    await _lan!.broadcast(_lanState);
  }

  Future<void> _receiveLanState(Json value) async {
    if (!lanEnabled || _disposed) return;
    _lanState = value;
    _lanOutputId = value['activeDeviceId'] as String?;
    if (_lanOutputId == deviceId) {
      audio.clearRemote();
    } else {
      await audio.suspendLocalOutput();
      final current = object(value['track']);
      audio.showRemote(
        PlaybackSnapshot.fromJson(object(value['state'])),
        current.isEmpty ? null : WaveTrack(current),
        objects(value['queueTracks']).map(WaveTrack.new).toList(),
      );
    }
    notifyListeners();
  }

  Future<void> _lanReport() async {
    if (_lanReporting || _lanMutating || _disposed || _lan == null) return;
    _lanReporting = true;
    try {
      if (lanHosting) {
        await _publishLan();
      } else if (_lan!.connected && _lanOutputId == deviceId) {
        await _lan!.request('report', _localLanState());
      }
    } catch (_) {
      lanError = lanText('network');
    } finally {
      _lanReporting = false;
    }
  }

  Future<Json> _lanControl(String command, Json args) async {
    try {
      if (!lanHosting) return await _lan!.request(command, args);
      return await _lanCommand(command, args, deviceId);
    } catch (error) {
      throw WaveException(
        lanText(error is StateError ? error.message.toString() : 'network'),
      );
    }
  }

  Future<Json> _lanCommand(String command, Json args, String peerId) async {
    if (_lan == null) throw StateError('network');
    if (command == 'apply' && !lanHosting && peerId == _lan!.hostId) {
      return _lanApply(args['command'] as String, args);
    }
    if (!lanHosting) throw StateError('network');
    if (command == 'snapshot') return _lanState;
    if (command == 'report') {
      if (peerId != _lanOutputId || _lanMutating) return {};
      _lanState = {
        ...args,
        'activeDeviceId': _lanOutputId,
        'activeDeviceName': activeDeviceName,
      };
      audio.showRemote(
        PlaybackSnapshot.fromJson(object(args['state'])),
        object(args['track']).isEmpty ? null : WaveTrack(object(args['track'])),
        objects(args['queueTracks']).map(WaveTrack.new).toList(),
      );
      await _publishLan();
      return {};
    }
    if (!['transport', 'transfer'].contains(command)) {
      throw StateError('network');
    }
    final predecessor = _lanSerial, release = Completer<void>();
    _lanSerial = release.future;
    await predecessor;
    _lanMutating = true;
    try {
      if (_lan == null || !lanHosting) throw StateError('network');
      if (command == 'transfer') {
        await _lanTransfer(args['deviceId'] as String);
      } else {
        final result = await _lanOutput(args['command'] as String, args);
        _lanState = {
          ...result,
          'activeDeviceId': _lanOutputId,
          'activeDeviceName': activeDeviceName,
        };
      }
      if (_lanOutputId != deviceId) await _receiveLanState(_lanState);
      await _publishLan();
      return _lanState;
    } finally {
      _lanMutating = false;
      release.complete();
    }
  }

  Future<Json> _lanOutput(String command, Json args, {String? target}) {
    final id = target ?? _lanOutputId;
    if (id == deviceId) return _lanApply(command, args);
    return _lan!.request('apply', {'command': command, ...args}, peerId: id);
  }

  Future<WaveTrack> _lanCached(String id) async {
    final data = object(object(cache.entries[id])['track']);
    if (data['id'] != id || await cache.fileFor(id) == null) {
      throw StateError('cache');
    }
    return WaveTrack({
      ...data,
      'playback': {
        ...object(data['playback']),
        'kind': 'audio',
        'offline': true,
      },
    });
  }

  Future<Json> _lanApply(String command, Json args) async {
    if (['track', 'prepare'].contains(command)) {
      final track = await _lanCached(args['trackId'] as String);
      final queue = <WaveTrack>[track];
      for (final id in List<String>.from(args['queue'] ?? []).take(100)) {
        if (id != track.id && cache.contains(id)) {
          queue.add(await _lanCached(id));
        }
      }
      await audio.playTrack(
        track,
        list: queue,
        position: number(args['position']),
        playing: command == 'track',
      );
      audio.applyPlaybackModes(
        PlaybackSnapshot.fromJson({
          'repeat': args['repeat'],
          'shuffle': args['enabled'],
        }),
      );
      if (!audio.sourceReady) throw StateError('cache');
    } else if (command == 'queue') {
      final items = <WaveTrack>[];
      for (final id in List<String>.from(args['queue'] ?? []).take(100)) {
        items.add(await _lanCached(id));
      }
      audio.replaceQueue(items);
    } else {
      if (![
        'play',
        'pause',
        'stop',
        'seek',
        'volume',
        'next',
        'previous',
        'shuffle',
        'repeat',
        'queue',
      ].contains(command)) {
        throw StateError('network');
      }
      if (command == 'play' &&
          (audio.current == null || !cache.contains(audio.current!.id))) {
        throw StateError('cache');
      }
      await audio.localCommand(command, args);
    }
    return _localLanState();
  }

  Future<void> _lanTransfer(String target) async {
    if (target == _lanOutputId) return;
    if (target != deviceId &&
        !lanPeers.any((p) => p['id'] == target && p['online'] == true)) {
      throw StateError('network');
    }
    final previous = _lanOutputId;
    final state = PlaybackSnapshot.fromJson(object(_lanState['state']));
    if (state.trackId == null) throw StateError('cache');
    // Prepare and validate the receiver before pausing the current output.
    await _lanOutput('prepare', {
      'trackId': state.trackId,
      'queue': state.queue,
      'position': state.projectedPosition(
        DateTime.now().millisecondsSinceEpoch,
      ),
      'repeat': state.repeat,
      'enabled': state.shuffle,
    }, target: target);
    try {
      await _lanOutput('pause', {}, target: previous);
      final result = await _lanOutput(
        state.playing ? 'play' : 'pause',
        {},
        target: target,
      );
      _lanOutputId = target;
      _lanState = {
        ...result,
        'activeDeviceId': target,
        'activeDeviceName': activeDeviceName,
      };
    } catch (_) {
      try {
        await _lanOutput('pause', {}, target: target);
        if (state.playing) await _lanOutput('play', {}, target: previous);
      } catch (_) {}
      rethrow;
    }
  }

  PlaybackSnapshot snapshot() => PlaybackSnapshot(
    trackId: audio.current?.id,
    position: audio.outputPosition.inMilliseconds / 1000,
    volume: audio.outputVolume,
    playing: audio.outputPlaying,
    shuffle: audio.shuffle,
    repeat: audio.repeat == AudioServiceRepeatMode.one
        ? 'one'
        : audio.repeat == AudioServiceRepeatMode.all
        ? 'all'
        : 'off',
    queue: audio.tracks.map((t) => t.id).toList(),
    updatedAt: DateTime.now().millisecondsSinceEpoch,
  );
  void _report() {
    if (_offlinePlayback) return;
    if (_confirmingControl && _confirmingScope == controlScope) return;
    if (lanEnabled) {
      unawaited(_lanReport());
      return;
    }
    if (socket?.connected == true) {
      socket!.emit('device:state', {
        ...snapshot().toJson(),
        'sequence': ++_stateSequence,
        'waveMode': waveMode,
        'waveMood': waveMood,
        'waveActive': waveActive,
        'outputActive': room != null
            ? _roomOutputActive && outputHere
            : !controllingRemote && _localOutputActive,
        'roomId': room?['id'],
        'trackLoading': trackLoading,
      });
    }
  }

  Future<Json> emitAck(String event, Json data) async {
    if (socket?.connected != true) {
      throw WaveException(wt('native.79b5d767d1'));
    }
    final response = object(
      await socket!
          .emitWithAckAsync(event, data)
          .timeout(const Duration(seconds: 12)),
    );
    if (response['error'] != null) {
      throw WaveException(
        object(response['error'])['message'] as String? ??
            wt('native.215c1efc19'),
      );
    }
    return response;
  }

  Future<void> receiveDeviceCommand(Json data) async {
    if (_offlinePlayback) {
      throw WaveException(lanText('busy'), 'OFFLINE_LISTENING');
    }
    if (lanEnabled) throw WaveException(lanText('busy'));
    final command = data['command'];
    if (command == 'queue' &&
        data['trackId'] != null &&
        data['trackId'] != audio.viewCurrent?.id) {
      throw WaveException(wt('native.7e03f83d51'), 'PLAYBACK_CHANGED');
    }
    final generation = ['track', 'transfer', 'pause', 'stop'].contains(command)
        ? ++_deviceCommandGeneration
        : _deviceCommandGeneration;
    if (command == 'pause' || command == 'stop') audio.cancelPendingLoad();
    final previousProvisional = _provisionalOutput;
    final previousRoomOutput = _roomOutputActive;
    final previousLocalOutput = _localOutputActive;
    try {
      await _applyDeviceCommand(data, generation);
    } catch (_) {
      if (generation == _deviceCommandGeneration) {
        _provisionalOutput = previousProvisional;
        _roomOutputActive = previousRoomOutput;
        _localOutputActive = previousLocalOutput;
      }
      rethrow;
    }
  }

  Future<void> _applyDeviceCommand(Json data, int generation) async {
    final command = data['command'] as String? ?? '';
    if (data['waveMode'] is String && data['waveMood'] is String) {
      waveMode = data['waveMode'] as String;
      waveMood = data['waveMood'] as String;
      waveActive = data['waveActive'] == true;
    }
    if (data['localOnly'] == true && data['outputActive'] is bool) {
      _provisionalOutput = data['outputActive'] == true;
    }
    if (data['roomId'] is String && data['roomId'] != room?['id']) {
      await _adoptRoom(data['roomId'] as String);
    } else if (data.containsKey('roomId') &&
        data['roomId'] == null &&
        room != null) {
      await clearRoomParticipation(pause: false);
    }
    if (generation != _deviceCommandGeneration) {
      throw WaveException(wt('native.1d9a81e50c'), 'playback_cancelled');
    }
    if (data['localOnly'] == true && data['outputActive'] is bool) {
      _roomOutputActive = data['outputActive'] as bool;
      _localOutputActive = data['outputActive'] as bool;
      _provisionalOutput = data['outputActive'] == true;
    }
    if (command == 'track' || command == 'transfer') {
      final id = data['trackId'] as String?;
      if (id == null) throw WaveException(wt('native.27962f8ac9'));
      final target = await requireTrack(id);
      if (!target.playable && target.source == 'local') {
        throw WaveException(wt('native.2b386cb1d4'));
      }
      final queue = <WaveTrack>[];
      for (final id in List<String>.from(data['queue'] ?? [target.id])) {
        queue.add(await requireTrack(id));
      }
      final previousTrack = audio.current;
      final previousQueue = List<WaveTrack>.from(audio.tracks);
      final previousState = snapshot();
      final expectedAudioRevision = audio.loadRevision + 1;
      try {
        audio.clearRemote();
        _localOutputActive = data['outputActive'] != false;
        await audio.playTrack(
          target,
          list: queue,
          position: number(data['position']),
          playing: data['playing'] != false,
          recover: false,
        );
        if (generation != _deviceCommandGeneration ||
            audio.loadRevision != expectedAudioRevision) {
          throw WaveException(wt('native.1d9a81e50c'), 'playback_cancelled');
        }
        if (audio.current?.id != target.id ||
            !audio.sourceReady ||
            data['playing'] != false && !audio.outputPlaying) {
          throw WaveException(wt('native.1d9a81e50c'));
        }
        if (data['volume'] != null) {
          await audio.localCommand('volume', {'volume': data['volume']});
        }
        audio.applyPlaybackModes(
          PlaybackSnapshot.fromJson({
            'repeat': data['repeat'],
            'shuffle': data['enabled'],
          }),
        );
        if (!_disposed) notifyListeners();
      } catch (_) {
        if (generation == _deviceCommandGeneration) _provisionalOutput = false;
        // Preserve this receiver's previous playback after a failed transfer.
        // A later user command has priority over this rollback.
        if (generation == _deviceCommandGeneration &&
            audio.loadRevision == expectedAudioRevision &&
            previousTrack != null &&
            audio.current?.id == target.id) {
          try {
            await audio.playTrack(
              previousTrack,
              list: previousQueue,
              position: previousState.position,
              playing: previousState.playing,
              recover: false,
            );
            await audio.localCommand('volume', {
              'volume': previousState.volume,
            });
          } catch (error) {
            tell(wt('native.ce93da4baa', values: {'p0': (error)}));
          }
        }
        rethrow;
      }
    } else if (data['localOnly'] == true || command == 'volume') {
      await audio.localCommand(command, data);
    } else {
      // This command already targets this output. Routing it back through
      // Connect would send it to the server a second time.
      await audio.localCommand(command, data);
    }
    _report();
  }

  Future<void> commandDevice(
    String id,
    String command, [
    Json data = const {},
  ]) async {
    await api.call(
      '/api/devices/command',
      method: 'POST',
      data: {'deviceId': id, 'command': command, ...data},
    );
  }

  Future<void> transferCloud(String id, {String? targetSurfaceId}) =>
      transfer(id, targetSurfaceId: targetSurfaceId, cloud: true);

  Future<void> transfer(
    String id, {
    String? targetSurfaceId,
    bool cloud = false,
  }) {
    // One in-flight handoff across cloud and LAN; repeated gestures share its ACK.
    if (_transferFlight != null) return _transferFlight!;
    if (_offlinePlayback) _resumeCloudPlayback();
    final token = api.token, origin = api.server;
    transferPending = id;
    pendingDeviceActions.add('transfer:$id');
    notifyListeners();
    late final Future<void> work;
    work = () async {
      try {
        if (cloud && lanEnabled) {
          await setLanEnabled(false);
          if (token != api.token || origin != api.server || _disposed) return;
          await refreshConnect();
          if (token != api.token || origin != api.server || _disposed) return;
        }
        if (lanEnabled) {
          await _lanControl('transfer', {'deviceId': id});
        } else {
          final response = await api.call(
            '/api/devices/command',
            method: 'POST',
            data: {
              'deviceId': id,
              'command': 'transfer',
              'fromDeviceId': independentListening
                  ? deviceId
                  : activeDeviceId ?? deviceId,
              if (targetSurfaceId != null) 'surfaceId': targetSurfaceId,
            },
          );
          if (token != api.token || origin != api.server || _disposed) return;
          if (response['connect'] is Map) {
            await receiveAccountState(object(response['connect']));
          } else {
            await refreshConnect();
          }
        }
      } finally {
        // A new account never inherits a pending handoff from the old one.
        if (identical(_transferFlight, work)) {
          transferPending = null;
          pendingDeviceActions.remove('transfer:$id');
          _transferFlight = null;
          if (!_disposed) notifyListeners();
        }
      }
    }();
    _transferFlight = work;
    return work;
  }

  Future<void> listenHere() async {
    if (lanEnabled) {
      await transfer(deviceId);
      return;
    }
    if (room != null && activeDeviceId == null && !independentListening) {
      await _deviceAction('transfer:$deviceId', () async {
        final joined = await emitAck('room:join', {'roomId': room!['id']});
        if (joined['connect'] is Map) {
          await receiveAccountState(object(joined['connect']));
        }
      });
    } else if (activeDeviceId == null && audio.viewCurrent != null) {
      await play(audio.viewCurrent!, list: audio.viewTracks);
    } else {
      await transfer(deviceId, targetSurfaceId: surfaceId);
    }
  }

  Future<void> _deviceAction(String key, Future<void> Function() action) async {
    if (pendingDeviceActions.contains(key)) return;
    pendingDeviceActions.add(key);
    notifyListeners();
    try {
      await action();
    } finally {
      pendingDeviceActions.remove(key);
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> refreshConnect() async {
    if (api.token == null) return;
    final generation = _accountGeneration;
    final session = api.token, origin = api.server;
    try {
      final response = await api.call('/api/connect');
      if (generation != _accountGeneration ||
          session != api.token ||
          origin != api.server) {
        return;
      }
      _connectSupported = response['connect'] is Map;
      await receiveAccountState(object(response['connect']));
    } on WaveException catch (error) {
      // Older deployments have no account-wide Connect yet. Device commands
      // and local playback continue to work until their backend is updated.
      if (error.status != 404 &&
          !['not_found', 'NOT_FOUND'].contains(error.code)) {
        rethrow;
      }
      if (generation == _accountGeneration &&
          session == api.token &&
          origin == api.server) {
        _connectSupported = false;
      }
    }
  }

  Future<void> setIndependentListening(bool value) async {
    if (_offlinePlayback) _resumeCloudPlayback();
    if (connectChanging) return;
    connectChanging = true;
    notifyListeners();
    try {
      final response = await api.call(
        '/api/connect',
        method: 'PATCH',
        data: {'independent': value},
      );
      await receiveAccountState(object(response['connect']));
    } finally {
      connectChanging = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> revokeDevice(String id) async {
    await _deviceAction('revoke:$id', () async {
      final token = api.token, origin = api.server;
      await api.call(
        '/api/devices/${Uri.encodeComponent(id)}',
        method: 'DELETE',
      );
      if (token != api.token || origin != api.server) return;
      if (id == deviceId) {
        await logout(remote: false);
        return;
      }
      await refreshDevices();
      await refreshSessions();
    });
  }

  Future<void> receiveDeviceChange(dynamic data) async {
    final payload = data is List ? data : object(data)['devices'];
    if (payload is List) {
      _devicesGeneration++;
      devices = objects(payload);
      if (!_disposed) notifyListeners();
      return;
    }
    // The server emits an invalidation, not an empty directory. Keep the last
    // known names/tracks while a scoped, shared request refreshes the directory.
    await refreshDevices(invalidated: true);
  }

  Future<void> refreshDevices({bool invalidated = false}) {
    final token = api.token, origin = api.server;
    final scope = '$origin:$token';
    if (_devicesFlight != null && _devicesFlightScope == scope) {
      _devicesDirty |= invalidated;
      return _devicesFlight!;
    }
    _devicesFlightScope = scope;
    _devicesDirty = false;
    late final Future<void> work;
    work = () async {
      try {
        do {
          _devicesDirty = false;
          final generation = ++_devicesGeneration;
          final response = await api.call('/api/devices');
          if (_disposed || token != api.token || origin != api.server) return;
          if (generation == _devicesGeneration && response['devices'] is List) {
            devices = objects(response['devices']);
            notifyListeners();
          }
        } while (_devicesDirty && _devicesFlightScope == scope);
      } finally {
        if (identical(_devicesFlight, work)) {
          _devicesFlight = null;
          _devicesFlightScope = null;
        }
      }
    }();
    _devicesFlight = work;
    return work;
  }

  Future<void> refreshSessions() async {
    if (api.token == null) return;
    final generation = ++_sessionsGeneration;
    final token = api.token, origin = api.server;
    sessionsLoading = true;
    sessionsError = null;
    notifyListeners();
    try {
      final response = await api.call('/api/account/sessions');
      if (_disposed ||
          generation != _sessionsGeneration ||
          token != api.token ||
          origin != api.server) {
        return;
      }
      sessionsSupported = true;
      sessions = objects(response['sessions']);
      currentSessionId = response['currentSessionId'] as String?;
    } on WaveException catch (error) {
      if (_disposed ||
          generation != _sessionsGeneration ||
          token != api.token ||
          origin != api.server) {
        return;
      }
      if (error.status == 404) {
        sessionsSupported = false;
        sessions = [];
      } else {
        sessionsError = wt('sessions.loadFailed');
      }
    } catch (_) {
      if (generation == _sessionsGeneration &&
          token == api.token &&
          origin == api.server) {
        sessionsError = wt('sessions.loadFailed');
      }
    } finally {
      if (!_disposed && generation == _sessionsGeneration) {
        sessionsLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> revokeSession(String? id) async {
    final key = id ?? 'others';
    if (pendingSessionActions.contains(key)) return;
    pendingSessionActions.add(key);
    notifyListeners();
    try {
      final token = api.token, origin = api.server;
      await api.call(
        '/api/account/sessions${id == null ? '' : '/${Uri.encodeComponent(id)}'}',
        method: 'DELETE',
      );
      if (token != api.token || origin != api.server) return;
      if (id != null &&
          (id == currentSessionId ||
              sessions.any((s) => s['id'] == id && s['current'] == true))) {
        await logout(remote: false);
        return;
      }
      await refreshSessions();
      await refreshDevices();
      await refreshConnect();
    } finally {
      pendingSessionActions.remove(key);
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> receiveAccountState(Json incoming) async {
    if (_offlinePlayback || lanEnabled) return;
    if (incoming.isEmpty) return;
    final revision = (object(incoming['state'])['revision'] as num?)?.toInt();
    if (revision != null && revision < _accountRevision) return;
    if (revision != null) _accountRevision = revision;
    _connectSupported = true;
    final generation = ++_accountGeneration;
    connect = Map.of(incoming);
    final waveState = object(incoming['state']);
    if (!independentListening &&
        !transportPending &&
        waveState['waveMode'] is String &&
        waveState['waveMood'] is String) {
      waveMode = waveState['waveMode'] as String;
      waveMood = waveState['waveMood'] as String;
      waveActive = waveState['waveActive'] == true;
    }
    _ensureControlScope();
    if (_provisionalOutput &&
        activeDeviceId == deviceId &&
        (activeSurfaceId == null || activeSurfaceId == surfaceId)) {
      _provisionalOutput = false;
    }
    final linkedRoom = incoming['roomId'] as String?;
    if (linkedRoom != null && linkedRoom != room?['id']) {
      await _adoptRoom(linkedRoom);
      if (activeRoomId != linkedRoom ||
          _disposed ||
          generation != _accountGeneration) {
        return;
      }
    }
    if (room != null &&
        incoming.containsKey('roomId') &&
        linkedRoom == null &&
        !independentListening) {
      await clearRoomParticipation();
    }
    if (room != null) {
      if (incoming['state'] is Map && linkedRoom == room!['id']) {
        // Connect uses an account revision; room commands use a separate room
        // revision. Preserve that room revision while mirroring the live clock.
        final roomRevision = object(room!['state'])['revision'];
        room!['state'] = {
          ...object(room!['state']),
          ...object(incoming['state']),
          if (roomRevision != null) 'revision': roomRevision,
        };
      }
      _roomOutputActive = outputHere;
      if (!outputHere) {
        _localOutputActive = false;
        audio.cancelPendingLoad();
        await audio.suspendLocalOutput();
      }
      if (outputHere &&
          !audio.remote &&
          audio.current?.id == object(room!['state'])['trackId']) {
        // Account heartbeats must not restart/cancel a source that is loading.
        // Room commands already arrive through the ordered room state stream.
        notifyListeners();
        return;
      }
      await receiveRoomState({
        'roomId': room!['id'],
        'state': room!['state'],
        'serverTime': incoming['serverTime'],
      }, force: true);
      return;
    }
    if (!controllingRemote &&
        (activeDeviceId != null || independentListening)) {
      if (!independentListening) {
        audio.applyPlaybackModes(
          PlaybackSnapshot.fromJson(object(incoming['state'])),
        );
      }
      audio.clearRemote();
      notifyListeners();
      return;
    }
    if (_localOutputActive) {
      _localOutputActive = false;
      audio.cancelPendingLoad();
      await audio.suspendLocalOutput();
    }
    final rawTrack = object(incoming['track']);
    var target = rawTrack.isNotEmpty ? WaveTrack(rawTrack) : null;
    final state = PlaybackSnapshot.fromJson(object(incoming['state']));
    target ??= track(state.trackId);
    if (target == null && state.trackId != null) {
      target = await requireTrack(state.trackId!);
    }
    if (generation != _accountGeneration ||
        !controllingRemote && activeDeviceId != null ||
        room != null) {
      return;
    }
    final queue = objects(incoming['queueTracks']).map(WaveTrack.new).toList();
    final serverTime =
        (incoming['serverTime'] as num?)?.toInt() ?? state.updatedAt;
    final projected = state.projectedPosition(
      serverTime,
      duration: target?.duration,
    );
    audio.showRemote(
      PlaybackSnapshot(
        trackId: state.trackId,
        position: projected,
        volume: state.volume,
        playing: activeDeviceId != null && state.playing,
        queue: state.queue,
        shuffle: state.shuffle,
        repeat: state.repeat,
        revision: state.revision,
      ),
      target,
      queue,
    );
    notifyListeners();
  }

  Future<void> createRoom(String name, {bool public = false}) async {
    if (lanEnabled) throw WaveException(lanText('room'));
    final data = await api.call(
      '/api/rooms',
      method: 'POST',
      data: {'name': name.trim(), 'visibility': public ? 'public' : 'private'},
    );
    await enterRoom(object(data['room']));
  }

  Future<void> joinRoom(String code) async {
    if (lanEnabled) throw WaveException(lanText('room'));
    final invite = Uri.tryParse(code)?.queryParameters['room'] ?? code.trim();
    final data = await api.call(
      '/api/rooms/join',
      method: 'POST',
      data: {'inviteCode': invite},
    );
    await enterRoom(object(data['room']));
  }

  Future<void> _adoptRoom(String id) async {
    if (lanEnabled) return;
    if (room?['id'] == id) return;
    if (_adoptingRoomId == id && _roomAdoption != null) {
      await _roomAdoption;
      return;
    }
    _adoptingRoomId = id;
    final token = api.token, origin = api.server;
    final adoption = () async {
      final response = await api.call('/api/rooms/${Uri.encodeComponent(id)}');
      if (_disposed ||
          token != api.token ||
          origin != api.server ||
          _adoptingRoomId != id) {
        return;
      }
      final target = object(response['room']);
      if (target['id'] != id) throw WaveException(wt('room.unavailable'));
      if (room != null) await clearRoomParticipation();
      if (_disposed ||
          token != api.token ||
          origin != api.server ||
          _adoptingRoomId != id) {
        return;
      }
      await enterRoom(target, adoptOnly: true);
    }();
    _roomAdoption = adoption;
    try {
      await adoption;
    } finally {
      if (identical(_roomAdoption, adoption)) {
        _roomAdoption = null;
        _adoptingRoomId = null;
      }
    }
  }

  Future<void> enterRoom(Json target, {bool adoptOnly = false}) async {
    if (_offlinePlayback) {
      _resumeCloudPlayback();
    }
    if (lanEnabled) throw WaveException(lanText('room'));
    if (room != null && room?['id'] != target['id']) await leaveRoom();
    final generation = ++_roomGeneration;
    final session = api.token, origin = api.server;
    room = target;
    _ensureControlScope();
    _roomOutputActive = _connectSupported != true;
    _roomRevision = -1;
    _roomSyncGeneration++;
    audio.cancelPendingLoad();
    await audio.applyProcessing(
      customization.equalizer,
      customization.playbackRate,
      inRoom: true,
    );
    final history = objects(
      (await api.call('/api/rooms/${target['id']}/messages'))['messages'],
    );
    if (generation != _roomGeneration ||
        session != api.token ||
        origin != api.server ||
        room?['id'] != target['id']) {
      return;
    }
    messages = history;
    final joined = adoptOnly && socket?.connected != true
        ? <String, dynamic>{}
        : await emitAck('room:join', {
            'roomId': target['id'],
            if (adoptOnly) 'adoptOnly': true,
          });
    if (generation != _roomGeneration ||
        session != api.token ||
        origin != api.server ||
        room?['id'] != target['id']) {
      return;
    }
    final live = object(joined['room']);
    if (live.isNotEmpty) room = {...target, ...live};
    if (!adoptOnly && joined['connect'] is Map) {
      await receiveAccountState(object(joined['connect']));
    }
    _roomOutputActive = outputHere;
    await (await SharedPreferences.getInstance()).setString(
      'room:$namespace',
      target['id'] as String,
    );
    if (adoptOnly) {
      notifyListeners();
      return;
    }
    await receiveRoomState({
      'roomId': target['id'],
      'state': room!['state'],
    }, force: true);
    notifyListeners();
  }

  Future<void> _rejoinRoom() async {
    final id = room?['id'], generation = _roomGeneration;
    final session = api.token, origin = api.server;
    if (id == null) return;
    final response = await emitAck('room:join', {
      'roomId': id,
      'adoptOnly': activeDeviceId != null || independentListening,
    });
    if (room?['id'] != id ||
        generation != _roomGeneration ||
        session != api.token ||
        origin != api.server) {
      return;
    }
    final live = object(response['room']);
    if (live.isNotEmpty) {
      room!['members'] = live['members'];
      if (response['connect'] is Map) {
        await receiveAccountState(object(response['connect']));
      }
      await receiveRoomState({
        'roomId': id,
        'state': live['state'],
      }, force: true);
    }
  }

  Future<void> leaveRoom() async {
    if (room == null) return;
    final id = room!['id'];
    if (room!['ownerId'] == user?.id && socket?.connected == true) {
      final response = await emitAck('room:leave', {'roomId': id});
      if (response['connect'] is Map) {
        await receiveAccountState(object(response['connect']));
      }
    } else {
      await api.call('/api/rooms/$id/leave', method: 'POST');
    }
    await clearRoomParticipation();
    await refresh();
  }

  Future<void> clearRoomParticipation({bool pause = true}) async {
    _roomGeneration++;
    _roomSyncGeneration++;
    audio.cancelPendingLoad();
    room = null;
    _ensureControlScope();
    _roomOutputActive = false;
    _provisionalOutput = false;
    _localOutputActive = false;
    messages = [];
    _roomRevision = -1;
    await (await SharedPreferences.getInstance()).remove('room:$namespace');
    audio.clearRemote();
    if (pause) await audio.localCommand('pause');
    await audio.applyProcessing(
      customization.equalizer,
      customization.playbackRate,
    );
    if (!_disposed) notifyListeners();
  }

  void _receiveRoomDirectory(
    Json data, {
    bool appendPublic = false,
    bool appendModeration = false,
  }) {
    rooms = objects(data['rooms']);
    final incoming = objects(data['publicRooms']);
    publicRooms = appendPublic
        ? <String, Json>{
            for (final item in publicRooms) item['id'].toString(): item,
            for (final item in incoming) item['id'].toString(): item,
          }.values.toList()
        : incoming;
    nextPublicRoomOffset = (data['nextPublicOffset'] as num?)?.toInt();
    final moderation = user?.admin == true
        ? objects(data['moderationRooms'])
        : <Json>[];
    moderationRooms = appendModeration
        ? <String, Json>{
            for (final item in moderationRooms) item['id'].toString(): item,
            for (final item in moderation) item['id'].toString(): item,
          }.values.toList()
        : moderation;
    nextModerationRoomOffset = user?.admin == true
        ? (data['nextModerationOffset'] as num?)?.toInt()
        : null;
  }

  void openRoomDirectory() {
    _roomDirectoryViews++;
    if (online && loggedIn) {
      scheduleMicrotask(() {
        if (_roomDirectoryViews > 0 && !_disposed) {
          unawaited(refreshRoomDirectory().catchError((_) {}));
        }
      });
    }
  }

  void closeRoomDirectory() {
    _roomDirectoryViews = (_roomDirectoryViews - 1).clamp(0, 100);
    if (_roomDirectoryViews == 0) _roomDirectoryTimer?.cancel();
  }

  Future<void> refreshRoomDirectory({
    bool morePublic = false,
    bool moreModeration = false,
  }) async {
    if (_roomDirectoryFlight != null) {
      await _roomDirectoryFlight;
      return;
    }
    if (!loggedIn || !online) return;
    final token = api.token, origin = api.server;
    final publicLoaded = publicRooms.length,
        moderationLoaded = moderationRooms.length;
    final offset = morePublic ? nextPublicRoomOffset : 0,
        moderationOffset = moreModeration ? nextModerationRoomOffset : 0;
    if (morePublic && offset == null ||
        moreModeration && moderationOffset == null) {
      return;
    }
    roomDirectoryLoading = true;
    if (!_disposed) notifyListeners();
    final operation = () async {
      try {
        final first = await api.call(
          '/api/rooms',
          query: {
            'offset': offset ?? 0,
            if (user?.admin == true) 'moderationOffset': moderationOffset ?? 0,
          },
        );
        if (_disposed || token != api.token || origin != api.server) return;
        // Loading one directory must not reset the other directory's paging.
        final savedPublic = List<Json>.of(publicRooms),
            savedModeration = List<Json>.of(moderationRooms),
            savedPublicNext = nextPublicRoomOffset,
            savedModerationNext = nextModerationRoomOffset;
        _receiveRoomDirectory(
          first,
          appendPublic: morePublic,
          appendModeration: moreModeration,
        );
        if (morePublic) {
          moderationRooms = savedModeration;
          nextModerationRoomOffset = savedModerationNext;
        }
        if (moreModeration) {
          publicRooms = savedPublic;
          nextPublicRoomOffset = savedPublicNext;
        }
        if (!morePublic && !moreModeration) {
          final requestedPages = <String>{};
          while ((publicRooms.length < publicLoaded &&
                  nextPublicRoomOffset != null) ||
              (moderationRooms.length < moderationLoaded &&
                  nextModerationRoomOffset != null)) {
            if (!requestedPages.add(
              '$nextPublicRoomOffset:$nextModerationRoomOffset',
            )) {
              break;
            }
            final more = await api.call(
              '/api/rooms',
              query: {
                'offset': nextPublicRoomOffset ?? 0,
                if (user?.admin == true)
                  'moderationOffset': nextModerationRoomOffset ?? 0,
              },
            );
            if (_disposed || token != api.token || origin != api.server) return;
            _receiveRoomDirectory(
              more,
              appendPublic: true,
              appendModeration: true,
            );
          }
        }
      } finally {
        roomDirectoryLoading = false;
        if (!_disposed && token == api.token && origin == api.server) {
          notifyListeners();
        }
      }
    }();
    _roomDirectoryFlight = operation;
    try {
      await operation;
    } finally {
      if (identical(_roomDirectoryFlight, operation)) {
        _roomDirectoryFlight = null;
      }
    }
  }

  Future<void> deleteRoom(Json target) async {
    if (user?.admin != true && target['ownerId'] != user?.id) {
      throw WaveException(wt('native.131b87ec38'));
    }
    await api.call('/api/rooms/${target['id']}', method: 'DELETE');
    if (room?['id'] == target['id']) await clearRoomParticipation();
    await refresh();
  }

  Future<void> roomMessage(String text) async {
    if (room == null || text.trim().isEmpty) return;
    final result = await api.call(
      '/api/rooms/${room!['id']}/messages',
      method: 'POST',
      data: {'text': text.trim()},
    );
    final message = object(result['message']);
    if (message.isNotEmpty && !messages.any((m) => m['id'] == message['id'])) {
      messages.add(message);
    }
    notifyListeners();
  }

  Future<void> roomPermission(String id, bool allowed) async {
    if (room == null) return;
    final roomId = room!['id'];
    final response = await api.call(
      '/api/rooms/${room!['id']}/members/$id',
      method: 'PATCH',
      data: {'canControl': allowed},
    );
    if (room?['id'] != roomId) return;
    final changed = object(response['room']);
    if (changed['members'] is List) room!['members'] = changed['members'];
    notifyListeners();
  }

  Future<void> receiveRoomState(Json update, {bool force = false}) async {
    if (lanEnabled) return;
    if (room == null || update['roomId'] != room!['id']) return;
    final state = PlaybackSnapshot.fromJson(object(update['state']));
    if (state.revision < _roomRevision ||
        (!force && state.revision == _roomRevision)) {
      return;
    }
    final generation = ++_roomSyncGeneration;
    final session = api.token, origin = api.server;
    audio.cancelPendingLoad();
    _roomRevision = state.revision;
    room!['state'] = state.toJson();
    if (update['serverTime'] is num) {
      _clockOffset =
          (update['serverTime'] as num).toInt() -
          DateTime.now().millisecondsSinceEpoch;
    }
    final activeRoom = room!['id'];
    bool currentState() =>
        room?['id'] == activeRoom &&
        _roomRevision == state.revision &&
        generation == _roomSyncGeneration &&
        session == api.token &&
        origin == api.server;
    if (state.trackId == null) {
      await audio.clear();
      if (currentState()) {
        notifyListeners();
        _report();
      }
      return;
    }
    final target = await requireTrack(state.trackId!);
    if (!currentState()) return;
    room!['currentTrack'] = target.json;
    final queue = await Future.wait(state.queue.map(requireTrack));
    if (!currentState()) return;
    if (!outputHere || !_roomOutputActive) {
      if (audio.outputPlaying || audio.provider.track != null) {
        await audio.suspendLocalOutput();
      }
      if (!currentState()) return;
      audio.showRemote(
        PlaybackSnapshot(
          trackId: state.trackId,
          position: state.projectedPosition(
            DateTime.now().millisecondsSinceEpoch + _clockOffset,
            duration: target.duration,
          ),
          playing:
              state.playing && !(jamListener && connect['jamPaused'] == true),
          volume: number(
            object(connect['state'])['volume'],
            audio.outputVolume,
          ),
          queue: state.queue,
          shuffle: state.shuffle,
          repeat: state.repeat,
          revision: state.revision,
        ),
        target,
        queue,
      );
      notifyListeners();
      _report();
      return;
    }
    audio.clearRemote();
    audio.applyPlaybackModes(state);
    if (audio.tracks.map((track) => track.id).join("\n") !=
        queue.map((track) => track.id).join("\n")) {
      audio.replaceQueue(queue);
    }
    if (state.trackId != null &&
        (state.trackId != audio.current?.id ||
            audio.current?.embedded == true && audio.provider.track == null)) {
      if (!target.playable && target.source == 'local') {
        tell(wt('native.001bce4367', values: {'p0': (target.sourceName)}));
        return;
      }
      await audio.playTrack(
        target,
        list: queue,
        position: state.projectedPosition(
          DateTime.now().millisecondsSinceEpoch + _clockOffset,
          duration: target.duration,
        ),
        playing:
            (audio.previewPlaying ?? state.playing) &&
            _roomOutputActive &&
            !(jamListener && connect['jamPaused'] == true),
      );
    }
    if (!currentState()) return;
    await _correctDrift();
    final shouldPlay =
        (audio.previewPlaying ?? state.playing) &&
        _roomOutputActive &&
        !(jamListener && connect['jamPaused'] == true);
    if (shouldPlay != audio.outputPlaying && audio.current != null) {
      await audio.localCommand(shouldPlay ? 'play' : 'pause');
    }
    if (state.trackId == null) await audio.localCommand('pause');
    notifyListeners();
    _report();
  }

  Future<void> _correctDrift() async {
    if (room == null ||
        audio.current == null ||
        !outputHere ||
        !_roomOutputActive ||
        jamListener && connect['jamPaused'] == true ||
        audio.previewPlaying == false) {
      return;
    }
    final state = PlaybackSnapshot.fromJson(object(room!['state']));
    if (state.trackId != audio.current!.id) return;
    final expected = state.projectedPosition(
      DateTime.now().millisecondsSinceEpoch + _clockOffset,
      duration: audio.current!.duration,
    );
    final actual = audio.outputPosition.inMilliseconds / 1000;
    if ((expected - actual).abs() > 1.25) {
      await audio.localCommand('seek', {'position': expected});
    }
  }

  Future<void> openUrl(String value) async {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !['https', 'http'].contains(uri.scheme) ||
        uri.host.isEmpty) {
      throw WaveException(wt('native.21d3c7b0bf'));
    }
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw WaveException(wt('native.adb57243da'));
    }
  }

  @override
  void dispose() {
    _disposed = true;
    energy.removeListener(_energyChanged);
    energy.dispose();
    _roomDirectoryTimer?.cancel();
    removeListener(_updateHomeWidgets);
    homeWidgets?.dispose();
    unawaited(backgroundConnect.update(false).catchError((_) => false));
    audio.onWidgetCommand = null;
    audio.onNotificationLike = null;
    audio.widgetGrant = null;
    audio.onLoadingChanged = null;
    unawaited(_lan?.close() ?? Future.value());
    _discordGeneration++;
    _roomGeneration++;
    _roomSyncGeneration++;
    audio.cancelPendingLoad();
    audio.onProcessingChanged = null;
    audio.onVolumeChanged = null;
    _localeRequest++;
    waveforms.removeListener(notifyListeners);
    waveforms.dispose();
    appearanceStore?.removeListener(_appearanceChanged);
    appearanceStore?.dispose();
    _heartbeat?.cancel();
    socket?.dispose();
    for (final sub in _subscriptions) {
      unawaited(sub.cancel());
    }
    cache.removeListener(notifyListeners);
    desktop.removeListener(notifyListeners);
    desktop.dispose();
    api.diagnostics.dispose();
    super.dispose();
  }
}
