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
import 'appearance.dart';
import '../services/appearance_store.dart';
import '../services/audio.dart';
import '../services/cache.dart';
import '../services/desktop.dart';
import '../services/push.dart';
import '../services/presence_bridge.dart';
import '../services/waveform.dart';
import '../l10n/wave_localizations.dart';

class WaveController extends ChangeNotifier {
  final WaveApi api;
  final MusicCache cache;
  final WaveAudioHandler audio;
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
  final DiscordPresence discord = DiscordPresence();
  final PresenceBridge presenceBridge = PresenceBridge();
  String bridgePairing = '';
  Json? _webPresence;
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
  List<String> likedIds = [];
  List<Json> playlists = [],
      history = [],
      integrations = [],
      rooms = [],
      devices = [],
      messages = [];
  Json? room;
  bool _roomOutputActive = true;
  int _roomGeneration = 0, _roomSyncGeneration = 0;
  bool loading = true, online = false, connected = false;
  double? uploadProgress;
  String? error, notice, suggestion;
  int noticeRevision = 0,
      _searchRevision = 0,
      _roomRevision = -1,
      _clockOffset = 0;
  String deviceId = '';
  String get deviceKind => Platform.isWindows
      ? 'windows'
      : Platform.isIOS
      ? 'ios'
      : 'android';
  String get deviceName =>
      '${Platform.isWindows
          ? wt('native.1db1b7e7a7')
          : Platform.isIOS
          ? 'iPhone'
          : 'Android'} · GlukWave';
  bool get loggedIn => user != null;
  bool get canControl =>
      room == null || (user != null && mayControlRoom(room!, user!.id));
  String get namespace => const Uuid().v5(
    Namespace.url.value,
    '${api.server}:${user?.id ?? 'guest'}',
  );
  String get appUrl => config['appUrl'] as String? ?? api.server;
  bool get captchaEnabled =>
      (object(config['auth'])['turnstileSiteKey'] as String? ?? '').isNotEmpty;
  WaveController(this.api, this.cache, this.audio) {
    _applyLanguage();
    waveforms = WaveformStore(api)..addListener(notifyListeners);
    desktop = DesktopShell(audio);
    push = WavePush(api);
    cache.addListener(notifyListeners);
    desktop.addListener(notifyListeners);
    discord.addListener(notifyListeners);
    audio.onError = tell;
    audio.onProcessingChanged = notifyListeners;
    audio.onEnded = (track, repeat) async {
      final active = room;
      if (active == null) return false;
      if (canControl && _roomOutputActive && object(active['state'])['trackId'] == track.id) {
        await emitAck('room:command', {
          'roomId': active['id'],
          'command': 'ended',
          'trackId': track.id,
          'expectedRevision': _roomRevision,
          'repeat': repeat == AudioServiceRepeatMode.one ? 'one' : repeat == AudioServiceRepeatMode.all ? 'all' : 'none',
        });
      }
      return true;
    };
    audio.onTransport = (command, data) async {
      if (room == null || command == 'volume') return false;
      await transport(command, data);
      return true;
    };
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
        if (item != null) unawaited(waveforms.load(item.id));
        if (item != null && online) {
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
    final savedServer = preferences.getString('server');
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
    try {
      await desktop.initialize();
      _desktopReady = true;
    } catch (e) {
      tell(wt('native.159f366d10', values: {'p0': (e)}));
    }
    if (Platform.isAndroid || Platform.isIOS) await audio.initializeSession();
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
        _applySettings();
        await _persist();
        _connectSocket();
        await _connectDiscord();
        if (Platform.isWindows &&
            preferences.getBool('presenceBridge') == true) {
          await togglePresenceBridge(true);
        }
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
    if (captchaEnabled) {
      await browserLogin(method: 'email');
      return;
    }
    final result = await api.call(
      '/api/auth/${username != null ? 'register' : 'login'}',
      method: 'POST',
      data: {
        'email': email.trim(),
        'password': password,
        if (username != null) 'username': username.trim(),
        if (displayName != null) 'displayName': displayName.trim(),
      },
    );
    await acceptSession(result);
  }

  Future<void> acceptSession(Json data) async {
    if (data['token'] is! String || object(data['user']).isEmpty) {
      throw WaveException(wt('native.d8b4826b17'));
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
      DateTime.parse(bridge['expiresAt'] as String),
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
    cancelAuth = true;
    socket?.dispose();
    socket = null;
    connected = false;
    room = null;
    _roomRevision = -1;
    await audio.localCommand('stop');
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
    discord.close();
    await presenceBridge.stop();
    _webPresence = null;
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
    unawaited(audio.applyProcessing(customization.equalizer, customization.playbackRate, inRoom: room != null)
        .catchError((Object error) { tell(error.toString()); }));
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
    if (changes.containsKey('discordPresence')) await _connectDiscord();
  }

  Future<void> _connectDiscord() async {
    if (settings['discordPresence'] != true || !Platform.isWindows) {
      discord.close();
      return;
    }
    if (!discord.ready) {
      await discord.connect(
        object(config['discord'])['clientId'] as String? ?? '',
      );
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
    if (!target.playable) {
      final url = target.sourceUrl.isNotEmpty
          ? target.sourceUrl
          : target.playback['embedUrl'] as String? ?? '';
      if (url.isEmpty) {
        throw WaveException(wt('native.fb5429ae1b'));
      }
      await audio.localCommand('pause');
      await openUrl(url);
      tell(wt('native.bb5aee59aa', values: {'p0': (target.sourceName)}));
      return;
    }
    final ids = (list ?? tracks)
        .where((t) => t.playable)
        .map((t) => t.id)
        .toList();
    if (room != null) {
      await transport('track', {'trackId': target.id, 'queue': ids});
      return;
    }
    await audio.playTrack(target, list: list ?? tracks);
    _report();
  }

  Future<void> transport(String command, [Json data = const {}]) async {
    if (room != null && command != 'volume') {
      if (!canControl) {
        throw WaveException(wt('native.131b87ec38'));
      }
      if (command == 'play' || command == 'track' || command == 'next' || command == 'previous') _roomOutputActive = true;
      await emitAck('room:command', {
        'roomId': room!['id'],
        'command': command,
        ...data,
      });
    } else {
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
    suggestion = data['suggestion'] as String?;
    final failures = objects(data['errors']);
    if (failures.isNotEmpty) {
      tell(failures.map((e) => e['message'] ?? e['provider']).join(' · '));
    }
    notifyListeners();
  }

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
    await openUrl(data['url'] as String);
    tell(wt('native.b1426ae61b'));
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
            'name': deviceName,
            'kind': deviceKind,
          })
          .build(),
    );
    socket!.onConnect((_) {
      connected = true;
      _report();
      notifyListeners();
      if (room != null) {
        unawaited(
          _rejoinRoom().catchError((_) {}),
        );
      }
    });
    socket!.onDisconnect((_) {
      connected = false;
      notifyListeners();
    });
    socket!.onConnectError((_) {
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
      devices = data is List ? objects(data) : objects(object(data)['devices']);
      notifyListeners();
    });
    socket!.on('device:command', (event) async {
      final data = event is List ? object(event.first) : object(event);
      final ack = event is List && event.last is Function
          ? event.last as Function
          : null;
      try {
        await _deviceCommand(data);
        ack?.call({'ok': true, 'state': snapshot().toJson()});
      } catch (e) {
        ack?.call({
          'error': {'code': 'playback_failed', 'message': e.toString()},
        });
        tell(e.toString());
      }
    });
    socket!.on('room:state', (data) {
      unawaited(
        _roomState(object(data)).catchError((e) {
          tell(e.toString());
        }),
      );
    });
    socket!.on('room:members', (data) {
      final update = object(data);
      if (room != null && update['roomId'] == room!['id']) {
        room!['members'] = update['members'];
        if (!objects(room!['members']).any((m) => m['userId'] == user?.id)) {
          room = null;
          unawaited(audio.localCommand('pause'));
        }
        notifyListeners();
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

  PlaybackSnapshot snapshot() => PlaybackSnapshot(
    trackId: audio.current?.id,
    position: audio.player.position.inMilliseconds / 1000,
    volume: audio.volume,
    playing: audio.player.playing,
    queue: audio.tracks.map((t) => t.id).toList(),
    updatedAt: DateTime.now().millisecondsSinceEpoch,
  );
  void _report() {
    if (socket?.connected == true) {
      socket!.emit('device:state', snapshot().toJson());
    }
    final web = _webPresence;
    if (web != null &&
        !audio.player.playing &&
        DateTime.now().millisecondsSinceEpoch - (web['receivedAt'] as int) <
            30000) {
      discord.update(
        web['track'] as WaveTrack?,
        web['playing'] == true,
        number(web['position']) +
            (web['playing'] == true
                ? (DateTime.now().millisecondsSinceEpoch -
                          (web['receivedAt'] as int)) /
                      1000
                : 0),
        appUrl,
      );
      return;
    }
    discord.update(
      audio.current,
      audio.player.playing,
      audio.player.position.inMilliseconds / 1000,
      appUrl,
      room: room,
    );
  }

  Future<void> togglePresenceBridge(bool enabled) async {
    if (!Platform.isWindows) {
      throw WaveException(wt('native.b8b235d91f'));
    }
    if (enabled) {
      bridgePairing =
          preferences.getString('bridgePairing:$namespace') ??
          const Uuid().v4();
      await preferences.setString('bridgePairing:$namespace', bridgePairing);
      await presenceBridge.start(
        bridgePairing,
        {Uri.parse(appUrl).origin, Uri.parse(api.server).origin},
        (data) async {
          if (user == null) {
            throw const WaveException('Native session required');
          }
          final trackId = data['trackId'] as String?;
          final target = trackId != null ? await requireTrack(trackId) : null;
          _webPresence = {
            ...data,
            'track': target,
            'receivedAt': DateTime.now().millisecondsSinceEpoch,
          };
          _report();
        },
      );
    } else {
      await presenceBridge.stop();
      _webPresence = null;
    }
    await preferences.setBool('presenceBridge', enabled);
    notifyListeners();
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

  Future<void> _deviceCommand(Json data) async {
    final command = data['command'] as String? ?? '';
    if (data['localOnly'] == true && data['outputActive'] is bool) {
      _roomOutputActive = data['outputActive'] as bool;
    }
    if (command == 'track' || command == 'transfer') {
      final id = data['trackId'] as String?;
      if (id == null) throw WaveException(wt('native.27962f8ac9'));
      final target = await requireTrack(id);
      if (!target.playable) {
        throw WaveException(wt('native.2b386cb1d4'));
      }
      final queue = <WaveTrack>[];
      for (final id in List<String>.from(data['queue'] ?? [target.id])) {
        queue.add(await requireTrack(id));
      }
      final previousTrack = audio.current;
      final previousQueue = List<WaveTrack>.from(audio.tracks);
      final previousState = snapshot();
      try {
        await audio.playTrack(
          target,
          list: queue,
          position: number(data['position']),
          playing: data['playing'] != false,
        );
        if (audio.current?.id != target.id) {
          throw WaveException(wt('native.1d9a81e50c'));
        }
        if (data['volume'] != null) {
          await audio.localCommand('volume', {'volume': data['volume']});
        }
      } catch (_) {
        // Preserve this receiver's previous playback after a failed transfer.
        // A later user command has priority over this rollback.
        if (previousTrack != null && audio.current?.id == target.id) {
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
      await transport(command, data);
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

  Future<void> transfer(String id) => commandDevice(id, 'transfer', {
    'fromDeviceId': deviceId,
    ...snapshot().toJson(),
  });
  Future<void> createRoom(String name) async {
    final data = await api.call(
      '/api/rooms',
      method: 'POST',
      data: {'name': name.trim()},
    );
    await enterRoom(object(data['room']));
  }

  Future<void> joinRoom(String code) async {
    final invite = Uri.tryParse(code)?.queryParameters['room'] ?? code.trim();
    final data = await api.call(
      '/api/rooms/join',
      method: 'POST',
      data: {'inviteCode': invite},
    );
    await enterRoom(object(data['room']));
  }

  Future<void> enterRoom(Json target) async {
    if (room != null) await leaveRoom();
    final generation = ++_roomGeneration;
    final session = api.token, origin = api.server;
    room = target;
    _roomOutputActive = true;
    _roomRevision = -1;
    _roomSyncGeneration++;
    audio.cancelPendingLoad();
    await audio.applyProcessing(customization.equalizer, customization.playbackRate, inRoom: true);
    final history = objects(
      (await api.call('/api/rooms/${target['id']}/messages'))['messages'],
    );
    if (generation != _roomGeneration || session != api.token || origin != api.server || room?['id'] != target['id']) return;
    messages = history;
    final joined = await emitAck('room:join', {'roomId': target['id']});
    if (generation != _roomGeneration || session != api.token || origin != api.server || room?['id'] != target['id']) return;
    final live = object(joined['room']);
    if (live.isNotEmpty) room = {...target, ...live};
    await _roomState({'roomId': target['id'], 'state': room!['state']}, force: true);
    notifyListeners();
  }

  Future<void> _rejoinRoom() async {
    final id = room?['id'], generation = _roomGeneration;
    final session = api.token, origin = api.server;
    if (id == null) return;
    final response = await emitAck('room:join', {'roomId': id});
    if (room?['id'] != id || generation != _roomGeneration || session != api.token || origin != api.server) return;
    final live = object(response['room']);
    if (live.isNotEmpty) {
      room!['members'] = live['members'];
      await _roomState({'roomId': id, 'state': live['state']}, force: true);
    }
  }

  Future<void> leaveRoom() async {
    if (room == null) return;
    final id = room!['id'];
    _roomGeneration++;
    _roomSyncGeneration++;
    audio.cancelPendingLoad();
    await api.call('/api/rooms/$id/leave', method: 'POST');
    if (socket?.connected == true) await emitAck('room:leave', {'roomId': id});
    room = null;
    _roomOutputActive = true;
    messages = [];
    _roomRevision = -1;
    await audio.localCommand('pause');
    await audio.applyProcessing(customization.equalizer, customization.playbackRate);
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

  Future<void> _roomState(Json update, {bool force = false}) async {
    if (room == null || update['roomId'] != room!['id']) return;
    final state = PlaybackSnapshot.fromJson(object(update['state']));
    if (state.revision < _roomRevision || (!force && state.revision == _roomRevision)) return;
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
    bool currentState() => room?['id'] == activeRoom && _roomRevision == state.revision &&
        generation == _roomSyncGeneration && session == api.token && origin == api.server;
    if (state.trackId == null) {
      await audio.clear();
      if (currentState()) { notifyListeners(); _report(); }
      return;
    }
    if (state.trackId != null && state.trackId != audio.current?.id) {
      final target = await requireTrack(state.trackId!);
      if (!currentState()) return;
      if (!target.playable) {
        tell(wt('native.001bce4367', values: {'p0': (target.sourceName)}));
        return;
      }
      final queue = await Future.wait(state.queue.map(requireTrack));
      if (!currentState()) return;
      await audio.playTrack(
        target,
        list: queue,
        position: state.projectedPosition(
          DateTime.now().millisecondsSinceEpoch + _clockOffset,
          duration: target.duration,
        ),
        playing: state.playing && _roomOutputActive,
      );
    }
    if (!currentState()) return;
    await _correctDrift();
    final shouldPlay = state.playing && _roomOutputActive;
    if (shouldPlay != audio.player.playing && audio.current != null) {
      await audio.localCommand(shouldPlay ? 'play' : 'pause');
    }
    if (state.trackId == null) await audio.localCommand('pause');
    notifyListeners();
    _report();
  }

  Future<void> _correctDrift() async {
    if (room == null || audio.current == null) return;
    final state = PlaybackSnapshot.fromJson(object(room!['state']));
    if (state.trackId != audio.current!.id) return;
    final expected = state.projectedPosition(
      DateTime.now().millisecondsSinceEpoch + _clockOffset,
      duration: audio.current!.duration,
    );
    final actual = audio.player.position.inMilliseconds / 1000;
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
    _roomGeneration++;
    _roomSyncGeneration++;
    audio.cancelPendingLoad();
    audio.onProcessingChanged = null;
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
    discord.removeListener(notifyListeners);
    desktop.dispose();
    discord.dispose();
    super.dispose();
  }
}
