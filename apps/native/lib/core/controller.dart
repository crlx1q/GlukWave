import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import 'api.dart';
import 'models.dart';
import 'discord.dart';
import 'appearance.dart';
import '../services/appearance_store.dart';
import '../services/audio.dart';
import '../services/volume_store.dart';
import '../services/cache.dart';
import '../services/desktop.dart';
import '../services/push.dart';
import '../services/waveform.dart';
import '../services/lan_transport.dart';
import '../l10n/lan_strings.dart';
import '../l10n/wave_localizations.dart';
import '../l10n/parity_strings.dart';

class WaveController extends ChangeNotifier {
  final WaveApi api;
  final MusicCache cache;
  final WaveAudioHandler audio;
  final bool startMinimized;
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
  List<Json> artistResults = [];
  List<String> likedIds = [];
  List<Json> playlists = [],
      history = [],
      integrations = [],
      rooms = [],
      devices = [],
      sessions = [],
      messages = [];
  String? currentSessionId, sessionsError;
  bool sessionsLoading = false, sessionsSupported = true;
  int _sessionsGeneration = 0;
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
  bool get trackLoading => audio.trackLoading;
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
  String? get activeDeviceId =>
      lanEnabled ? _lanOutputId : connect['activeDeviceId'] as String?;
  String? get activeSurfaceId => connect['activeSurfaceId'] as String?;
  bool get controllingRemote => lanEnabled
      ? _lanOutputId != deviceId
      : !_provisionalOutput &&
            !independentListening &&
            activeDeviceId != null &&
            (activeDeviceId != deviceId ||
                activeSurfaceId != null && activeSurfaceId != surfaceId);
  bool get outputHere => lanEnabled
      ? _lanOutputId == deviceId
      : _provisionalOutput ||
            independentListening ||
            activeDeviceId == deviceId &&
                (activeSurfaceId == null || activeSurfaceId == surfaceId) ||
            _connectSupported != true && _roomOutputActive;
  String? get activeRoomId => connect['roomId'] as String?;
  String get outputLabel => activeDeviceId == null
      ? wt('connect.noOutput')
      : wt('connect.playingOn', values: {'name': activeDeviceName});
  String get activeDeviceName => lanEnabled
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
                .firstOrNull ??
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
      (user != null &&
          (room!['type'] == 'jam'
              ? room!['ownerId'] == user!.id
              : mayControlRoom(room!, user!.id)));
  bool get jamListener =>
      room?['type'] == 'jam' && room?['ownerId'] != user?.id;
  bool get canTogglePlayback => canControl || jamListener;
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
    desktop.addListener(notifyListeners);
    audio.onError = (message) {
      api.diagnostics.report(message, kind: 'playback');
      tell(message);
    };
    audio.onProcessingChanged = notifyListeners;
    audio.onEnded = (track, repeat) async {
      if (lanEnabled) {
        if (outputHere) {
          if (repeat == AudioServiceRepeatMode.one) {
            await transport('seek', {'position': 0});
            await transport('play');
          } else {
            await transport('next');
          }
        }
        return true;
      }
      final active = room;
      if (active == null) return false;
      if (canControl &&
          _roomOutputActive &&
          outputHere &&
          object(active['state'])['trackId'] == track.id) {
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
      if (lanEnabled) {
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
    audio.onLoadingChanged = notifyListeners;
    _subscriptions.add(
      audio.playbackState.listen((state) {
        notifyListeners();
        _report();
        unawaited(desktop.updateTitle());
      }),
    );
    _subscriptions.add(
      audio.mediaItem.listen((item) {
        notifyListeners();
        if (item != null && !lanEnabled) unawaited(waveforms.load(item.id));
        if (item != null && online && !audio.remote && !lanEnabled) {
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
    await restoreCustomizationScope();
    _applyLanguage();
    unawaited(resolveAutomaticLanguage());
    await refresh();
    _heartbeat = Timer.periodic(const Duration(seconds: 3), (_) {
      _report();
      if (room != null) unawaited(_correctDrift());
    });
  }

  Future<void> _restore() async {
    final directory = await getApplicationSupportDirectory();
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

  Future<void> _persist() async {
    if (user == null) return;
    final directory = await getApplicationSupportDirectory();
    final file = File(p.join(directory.path, 'state-$namespace.json'));
    await file.writeAsString(
      jsonEncode({
        'tracks': tracks.map((t) => t.json).toList(),
        'likedIds': likedIds,
        'playlists': playlists,
        'history': history,
        'settings': settings,
        'config': config,
      }),
      flush: true,
    );
  }

  Future<void> refresh() async {
    final session = api.token, origin = api.server;
    final localeRequest = _localeRequest;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final serverConfig = await api.call('/api/config');
      if (session != api.token || origin != api.server) return;
      config = serverConfig;
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
        final data = await api.call('/api/library');
        if (session != api.token || origin != api.server) return;
        tracks = objects(data['tracks']).map(WaveTrack.new).toList();
        likedIds = List<String>.from(data['likedIds'] ?? []);
        playlists = objects(data['playlists']);
        history = objects(data['history']);
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
        rooms = objects((await api.call('/api/rooms'))['rooms']);
        devices = objects((await api.call('/api/devices'))['devices']);
        await refreshConnect();
        _applySettings();
        await _persist();
        _connectSocket();
        await refreshDiscord(silent: true);
      }
    } catch (e) {
      if (session != api.token || origin != api.server) return;
      if (e is WaveException && e.code == 'unauthorized') {
        await logout(remote: false);
        error = wt('native.b217602ba0');
      } else {
        online = false;
        error = e.toString();
      }
    } finally {
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
    final uri = Uri.tryParse(value);
    final id = uri?.queryParameters['qr'] ?? value.trim();
    if (!RegExp(r'^[a-zA-Z0-9_-]{8,100}$').hasMatch(id)) {
      throw WaveException(wt('native.283b363614'));
    }
    await api.call('/api/auth/qr/$id/approve', method: 'POST', data: {});
    tell(wt('native.e5eacefb73'));
  }

  Future<Json> qrInfo(String value) async {
    final id = Uri.tryParse(value)?.queryParameters['qr'] ?? value.trim();
    if (!RegExp(r'^[a-zA-Z0-9_-]{8,100}$').hasMatch(id)) {
      throw WaveException(wt('native.283b363614'));
    }
    return api.call('/api/auth/qr/$id/info');
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
    _provisionalOutput = false;
    _accountGeneration++;
    _deviceCommandGeneration++;
    audio.clearRemote();
    room = null;
    _roomGeneration++;
    _roomSyncGeneration++;
    _roomOutputActive = false;
    _roomRevision = -1;
    await (await SharedPreferences.getInstance()).remove('room:$namespace');
    await audio.clear();
    cache.activeId = null;
    await cache.clear(includingDownloads: true);
    await waveforms.clear();
    final metadata = File(
      p.join(
        (await getApplicationSupportDirectory()).path,
        'state-$namespace.json',
      ),
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
    _pendingOAuth = null;
    rooms = [];
    history = [];
    integrations = [];
    config = {};
    loading = false;
    notifyListeners();
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
  Future<void> play(WaveTrack target, {List<WaveTrack>? list}) async {
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
      await transport('track', {'trackId': target.id, 'queue': ids});
      return;
    }
    if (controllingRemote) {
      await commandDevice(activeDeviceId!, 'track', {
        'surfaceId': activeSurfaceId,
        'trackId': target.id,
        'queue': ids,
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
    audio.clearRemote();
    _localOutputActive = true;
    await audio.playTrack(target, list: list ?? tracks);
    _report();
  }

  Future<void> transport(String command, [Json data = const {}]) async {
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
      await emitAck('room:command', {
        'roomId': room!['id'],
        'command': command,
        ...data,
      });
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
    await api.call(
      '/api/library/likes/${t.id}',
      method: 'PUT',
      data: {'liked': liked},
    );
    if (liked) {
      likedIds.add(t.id);
    } else {
      likedIds.remove(t.id);
    }
    if (!tracks.any((value) => value.id == t.id)) tracks.add(t);
    await _persist();
    notifyListeners();
  }

  Future<void> search(String query, {String source = 'all'}) async {
    final revision = ++_searchRevision;
    if (query.trim().isEmpty) {
      results = [];
      artistResults = [];
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
    await api.call(
      '/api/playlists',
      method: 'POST',
      data: {'name': name.trim(), 'trackIds': ids},
    );
    await refresh();
  }

  Future<void> addToPlaylist(Json playlist, WaveTrack target) async {
    final ids = List<String>.from(playlist['trackIds'] ?? []);
    if (!ids.contains(target.id)) ids.add(target.id);
    await api.call(
      '/api/playlists/${playlist['id']}',
      method: 'PATCH',
      data: {'trackIds': ids},
    );
    await refresh();
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
    if (api.token == null) return;
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
    if (socket != null || api.token == null) return;
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
      devices = data is List ? objects(data) : objects(object(data)['devices']);
      notifyListeners();
    });
    socket!.on('sessions:changed', (_) {
      if (session != api.token || origin != api.server) return;
      unawaited(refreshSessions());
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
          'error': {'code': 'playback_failed', 'message': e.toString()},
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
    socket!.on('room:members', (data) {
      final update = object(data);
      if (room != null && update['roomId'] == room!['id']) {
        room!['members'] = update['members'];
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
      if (!audio.sourceReady) throw StateError('cache');
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
    queue: audio.tracks.map((t) => t.id).toList(),
    updatedAt: DateTime.now().millisecondsSinceEpoch,
  );
  void _report() {
    if (lanEnabled) {
      unawaited(_lanReport());
      return;
    }
    if (socket?.connected == true) {
      socket!.emit('device:state', {
        ...snapshot().toJson(),
        'outputActive': room != null
            ? _roomOutputActive && outputHere
            : !controllingRemote && _localOutputActive,
        'roomId': room?['id'],
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
    if (lanEnabled) throw WaveException(lanText('busy'));
    final command = data['command'];
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
        _localOutputActive = true;
        await audio.playTrack(
          target,
          list: queue,
          position: number(data['position']),
          playing: data['playing'] != false,
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

  Future<void> transfer(String id, {String? targetSurfaceId}) => lanEnabled
      ? _lanControl('transfer', {'deviceId': id}).then((_) {})
      : _deviceAction('transfer:$id', () async {
          await commandDevice(id, 'transfer', {
            'fromDeviceId': activeDeviceId ?? deviceId,
            if (targetSurfaceId != null) 'surfaceId': targetSurfaceId,
          });
          await refreshConnect();
        });

  Future<void> listenHere() async {
    if (lanEnabled) {
      await _lanControl('transfer', {'deviceId': deviceId});
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

  Future<void> refreshDevices() async {
    final token = api.token, origin = api.server;
    final response = await api.call('/api/devices');
    if (_disposed || token != api.token || origin != api.server) return;
    devices = objects(response['devices']);
    notifyListeners();
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
    if (lanEnabled) return;
    if (incoming.isEmpty) return;
    final revision = (object(incoming['state'])['revision'] as num?)?.toInt();
    if (revision != null && revision < _accountRevision) return;
    if (revision != null) _accountRevision = revision;
    _connectSupported = true;
    final generation = ++_accountGeneration;
    connect = Map.of(incoming);
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
    if (lanEnabled) throw WaveException(lanText('room'));
    if (room != null && room?['id'] != target['id']) await leaveRoom();
    final generation = ++_roomGeneration;
    final session = api.token, origin = api.server;
    room = target;
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
            state.playing &&
            _roomOutputActive &&
            !(jamListener && connect['jamPaused'] == true),
      );
    }
    if (!currentState()) return;
    await _correctDrift();
    final shouldPlay =
        state.playing &&
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
        jamListener && connect['jamPaused'] == true) {
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
