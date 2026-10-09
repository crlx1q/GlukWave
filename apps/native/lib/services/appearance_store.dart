import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/api.dart';
import '../core/appearance.dart';
import '../core/models.dart';

/// Device-local presentation survives network failures; account changes have
/// independent scopes and cannot receive an older account's in-flight response.
class AppearanceStore extends ChangeNotifier {
  final WaveApi api;
  final SharedPreferences preferences;
  WaveCustomization current = const WaveCustomization();
  bool pending = false, authenticated = false;
  String? lastError;
  String _key = 'appearance:guest';
  Json _patch = {};
  Json _flight = {};
  Json _remoteSettings = {};
  int _remoteRevision = -1;
  int get remoteRevision => _remoteRevision;
  Json get serverSettings => Map<String, dynamic>.unmodifiable(_remoteSettings);
  int _generation = 0, _revision = 0;
  Timer? _timer;
  Future<void> _writes = Future.value();
  Future<void>? _syncing;
  String? _scopeToken;
  String _scopeOrigin = '';
  bool _disposed = false;
  AppearanceStore(this.api, this.preferences);

  Future<void> selectScope(String? scope, {Json fallback = const {}}) async {
    final generation = ++_generation;
    _revision++;
    _timer?.cancel();
    _syncing = null;
    _flight = {};
    _scopeToken = api.token;
    _scopeOrigin = api.server;
    authenticated = scope != null;
    _key = 'appearance:${scope ?? 'guest'}';
    current = WaveCustomization.fromSettings(fallback);
    _remoteSettings = {...fallback};
    _remoteRevision = (fallback['revision'] as num?)?.toInt() ?? -1;
    pending = false;
    _patch = {};
    lastError = null;
    await flushLocalWrites();
    if (_disposed || generation != _generation) return;
    final stored = preferences.getString(_key);
    if (stored != null) {
      try {
        final data = object(jsonDecode(stored));
        current = WaveCustomization.fromSettings(object(data['settings']));
        _remoteSettings = data['remoteSettings'] is Map
            ? object(data['remoteSettings'])
            : current.toSettings();
        _remoteRevision = (data['remoteRevision'] as num?)?.toInt() ?? -1;
        pending = authenticated && data['pending'] == true;
        if (pending) {
          _patch = data['patch'] is Map
              ? object(data['patch'])
              : current.toSettings();
        }
      } catch (_) {
        await preferences.remove(_key);
      }
    }
    if (!_disposed) notifyListeners();
  }

  /// Local writes are serialized. Scope restores and application lifecycle
  /// changes can wait for durability without requiring a network connection.
  Future<void> flushLocalWrites() => _writes.catchError((_) {});

  Future<void> _persist() {
    final key = _key;
    final value = jsonEncode({
      'settings': current.toSettings(),
      'pending': pending,
      // A restart replays an interrupted request as a sparse patch. Newer
      // local edits win over the values that were already being sent.
      'patch': mergeAppearancePatch(_flight, _patch),
      'remoteSettings': _remoteSettings,
      'remoteRevision': _remoteRevision,
    });
    final write = _writes.catchError((_) {}).then((_) async {
      await preferences.setString(key, value);
    });
    _writes = write;
    return write;
  }

  Future<void> change(Json changes) async {
    final generation = _generation;
    current = current.merge(changes);
    _patch = mergeAppearancePatch(_patch, presentationPatch(changes, current));
    _revision++;
    pending = authenticated && (_patch.isNotEmpty || _flight.isNotEmpty);
    lastError = null;
    if (!_disposed) notifyListeners();
    await _persist();
    if (generation != _generation || _disposed) return;
    _timer?.cancel();
    if (authenticated) {
      _timer = Timer(
        const Duration(milliseconds: 550),
        () => unawaited(flush()),
      );
    }
  }

  bool _matchesScope(int generation, String? token, String origin) =>
      !_disposed &&
      generation == _generation &&
      token == api.token &&
      origin == api.server &&
      token == _scopeToken &&
      origin == _scopeOrigin;

  bool _takeRemote(Json settings, {int? revision}) {
    final version = revision ?? (settings['revision'] as num?)?.toInt();
    if (version != null && version <= _remoteRevision) return false;
    if (version == null && _remoteRevision > 0) return false;
    _remoteRevision = version ?? 0;
    _remoteSettings = mergeAppearancePatch(_remoteSettings, settings);
    return true;
  }

  void _reconcile() {
    current = WaveCustomization.fromSettings(
      _remoteSettings,
    ).merge(_flight).merge(_patch);
    pending = authenticated && (_patch.isNotEmpty || _flight.isNotEmpty);
  }

  Future<bool> receiveRemote(
    Json settings, {
    int? revision,
    String? expectedToken,
    String? expectedOrigin,
  }) async {
    final generation = _generation;
    final token = expectedToken ?? api.token,
        origin = expectedOrigin ?? api.server;
    if (!_matchesScope(generation, token, origin) ||
        !_takeRemote(settings, revision: revision)) {
      return false;
    }
    _reconcile();
    lastError = null;
    await _persist();
    if (!_matchesScope(generation, token, origin)) return false;
    notifyListeners();
    if (pending && _syncing == null) await flush();
    return _matchesScope(generation, token, origin);
  }

  Future<void> flush() async {
    _timer?.cancel();
    if (_syncing != null) {
      await _syncing;
      return;
    }
    if (!pending ||
        !authenticated ||
        _patch.isEmpty ||
        api.token == null ||
        _disposed) {
      return;
    }
    final generation = _generation, revision = _revision;
    final token = api.token, origin = api.server;
    if (!_matchesScope(generation, token, origin)) return;
    final payload = <String, dynamic>{..._patch};
    _patch = {};
    _flight = payload;
    final operation = () async {
      try {
        final data = await api.call(
          '/api/settings',
          method: 'PATCH',
          data: payload,
        );
        if (!_matchesScope(generation, token, origin)) return;
        _takeRemote(
          object(data['settings']),
          revision: (data['revision'] as num?)?.toInt(),
        );
        _flight = {};
        _reconcile();
        lastError = null;
        await _persist();
        if (_matchesScope(generation, token, origin)) notifyListeners();
      } catch (error) {
        if (!_matchesScope(generation, token, origin)) return;
        // A plan rejection is authoritative. Roll back the rejected edit while
        // preserving changes made after it was sent; never retry it forever.
        if (error is! WaveException || error.code.toUpperCase() != 'PLAN_LIMIT') {
          _patch = mergeAppearancePatch(payload, _patch);
        }
        _flight = {};
        _reconcile();
        lastError = error.toString();
        await _persist();
        notifyListeners();
      }
    }();
    _syncing = operation;
    try {
      await operation;
    } finally {
      if (identical(_syncing, operation)) _syncing = null;
      if (pending &&
          authenticated &&
          _matchesScope(generation, token, origin)) {
        _timer = Timer(
          Duration(milliseconds: revision == _revision ? 15000 : 550),
          () => unawaited(flush()),
        );
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
    super.dispose();
  }
}
