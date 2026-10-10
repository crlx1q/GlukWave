import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';

/// Presentation-only bridge. It never stores credentials, stream URLs or a
/// second queue. Android controls return to the existing account/media session.
class HomeWidgetBridge {
  static const channelName = 'tech.gluk.glukwave/home_widgets';
  static const commands = {'toggle', 'previous', 'next', 'like', 'wave'};
  final MethodChannel channel;
  final bool enabled;
  final Future<void> Function(String command, String scope) onCommand;
  final void Function(Object error)? onError;
  final void Function(String? grant)? onGrantChanged;
  bool _disposed = false, _ready = false, _writing = false;
  int _revision = 0;
  String? grant;
  String? _last;
  Map<String, Object?>? _pending;
  HomeWidgetBridge({
    required this.onCommand,
    this.onError,
    this.onGrantChanged,
    MethodChannel? channel,
    bool? enabled,
  }) : channel = channel ?? const MethodChannel(channelName),
       enabled = enabled ?? Platform.isAndroid;

  Future<void> initialize() async {
    if (!enabled || _disposed) return;
    channel.setMethodCallHandler((call) async {
      if (call.method != 'action') return;
      await _dispatch(call.arguments);
    });
    _ready = true;
    final action = await channel.invokeMethod<Object?>('initialize');
    if (action is Map && action['grant'] is String) {
      grant = action['grant'] as String;
      onGrantChanged?.call(grant);
      await _dispatch(action['action']);
    } else {
      await _dispatch(action);
    }
  }

  Future<void> _dispatch(Object? argument) async {
    if (_disposed || !_ready || argument is! Map) return;
    final command = argument['command'], scope = argument['scope'];
    if (command is! String || !commands.contains(command) || scope is! String) {
      return;
    }
    try {
      await onCommand(command, scope);
    } catch (error) {
      onError?.call(error);
    }
  }

  /// Many controller notifications concern progress or network housekeeping.
  /// Coalesce them; equal snapshots result in no platform/disk/launcher work.
  void update(Map<String, Object?> snapshot) {
    if (!enabled || !_ready || _disposed) return;
    _pending = Map.of(snapshot);
    if (!_writing) unawaited(_flush());
  }

  Future<void> _flush() async {
    _writing = true;
    try {
      while (_pending != null && !_disposed) {
        final value = _pending!;
        _pending = null;
        final fingerprint = jsonEncode(value);
        if (fingerprint == _last) continue;
        final revision = _revision;
        final updatedGrant = await channel.invokeMethod<String>(
          'update',
          value,
        );
        if (revision == _revision && updatedGrant != null) {
          grant = updatedGrant;
          onGrantChanged?.call(grant);
        }
        if (revision == _revision) _last = fingerprint;
      }
    } catch (error) {
      onError?.call(error);
    } finally {
      _writing = false;
      if (_pending != null && !_disposed) unawaited(_flush());
    }
  }

  Future<void> clear() async {
    if (!enabled || _disposed) return;
    _revision++;
    _last = null;
    _pending = null;
    grant = await channel.invokeMethod<String>('clear');
    onGrantChanged?.call(grant);
  }

  Future<bool> pin(String kind) async {
    if (!enabled || !{'player', 'wave'}.contains(kind)) return false;
    return await channel.invokeMethod<bool>('pin', {'kind': kind}) ?? false;
  }

  /// Reuse already downloaded notification artwork. No widget-specific remote
  /// fetch, bearer token, URL grant or unbounded image is persisted.
  static Future<String?> cachedArtwork(Uri? uri) async {
    if (uri == null) return null;
    if (uri.scheme == 'file') return File.fromUri(uri).path;
    try {
      return (await AudioService.cacheManager.getFileFromCache(
        uri.toString(),
      ))?.file.path;
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    _disposed = true;
    _pending = null;
    _revision++;
    grant = null;
    onGrantChanged?.call(null);
    if (enabled) channel.setMethodCallHandler(null);
  }
}
