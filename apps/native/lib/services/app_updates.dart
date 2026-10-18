import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../core/api.dart';

/// SemVer precedence plus the numeric native build number for equal versions.
int compareAppVersions(String a, String b) {
  List<String> parts(String value) {
    if (!RegExp(
      r'^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+\d+)?$',
    ).hasMatch(value)) {
      throw const FormatException('Invalid application version');
    }
    return value.split(RegExp(r'[.+-]'));
  }

  final aa = parts(a), bb = parts(b);
  for (var i = 0; i < 3; i++) {
    final result = BigInt.parse(aa[i]).compareTo(BigInt.parse(bb[i]));
    if (result != 0) return result;
  }
  String pre(String value) =>
      value.split('+').first.split('-').skip(1).join('-');
  final ap = pre(a), bp = pre(b);
  if (ap != bp) {
    if (ap.isEmpty) return 1;
    if (bp.isEmpty) return -1;
    final left = ap.split('.'), right = bp.split('.');
    for (var i = 0; i < left.length && i < right.length; i++) {
      if (left[i] == right[i]) continue;
      final x = BigInt.tryParse(left[i]), y = BigInt.tryParse(right[i]);
      return x != null && y != null
          ? x.compareTo(y)
          : x != null
          ? -1
          : y != null
          ? 1
          : left[i].compareTo(right[i]);
    }
    return left.length.compareTo(right.length);
  }
  BigInt build(String value) =>
      BigInt.parse(value.contains('+') ? value.split('+').last : '0');
  return build(a).compareTo(build(b));
}

class AppRelease {
  final String version, platform, sha256, url, format;
  final int bytes;
  const AppRelease({
    required this.version,
    required this.platform,
    required this.sha256,
    required this.url,
    required this.format,
    required this.bytes,
  });
  static AppRelease? parse(dynamic data, String platform) {
    if (data is! Map ||
        data['platform'] != platform ||
        data['available'] != true ||
        data['bytes'] is! int ||
        data['bytes'] < 1024 ||
        data['bytes'] > 512 * 1024 * 1024 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch('${data['sha256']}') ||
        data['url'] != '/api/downloads/$platform' ||
        data['format'] != (platform == 'windows' ? 'installer' : 'package')) {
      return null;
    }
    try {
      compareAppVersions('${data['version']}', '0.0.0');
    } catch (_) {
      return null;
    }
    return AppRelease(
      version: data['version'],
      platform: platform,
      sha256: data['sha256'],
      url: data['url'],
      format: data['format'],
      bytes: data['bytes'],
    );
  }

  Map<String, dynamic> toJson() => {
    'version': version,
    'platform': platform,
    'sha256': sha256,
    'url': url,
    'format': format,
    'bytes': bytes,
    'available': true,
  };
}

enum UpdatePhase {
  idle,
  checking,
  available,
  downloading,
  ready,
  installing,
  error,
}

class AppUpdater extends ChangeNotifier {
  final WaveApi api;
  String currentVersion;
  final String platform;
  final Dio client;
  final DateTime Function() clock;
  final Future<void> Function(File, String)? installer;
  SharedPreferences? _preferences;
  Directory? _directory;
  AppRelease? release;
  UpdatePhase phase = UpdatePhase.idle;
  double progress = 0;
  String? error;
  bool dismissed = false, _disposed = false;
  CancelToken? _download;
  Future<void>? _check;
  String? _releaseOrigin;
  static const _bridge = MethodChannel('tech.gluk.glukwave/updates');
  AppUpdater(
    this.api, {
    required this.currentVersion,
    String? platform,
    Dio? client,
    DateTime Function()? clock,
    this.installer,
  }) : platform =
           platform ??
           (Platform.isWindows
               ? 'windows'
               : Platform.isAndroid
               ? 'android'
               : 'unsupported'),
       client =
           client ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 8),
               receiveTimeout: const Duration(seconds: 20),
               followRedirects: false,
             ),
           ),
       clock = clock ?? DateTime.now;

  String get _key => 'updates:v1:${api.server}:$platform';
  bool get supported => ['windows', 'android'].contains(platform);
  bool get visible =>
      release != null && !dismissed && _releaseOrigin == api.server;
  void _publish() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize(
    SharedPreferences preferences,
    Directory support,
  ) async {
    _preferences = preferences;
    _directory = Directory(p.join(support.path, 'updates'));
    if (installer == null && supported) {
      try {
        final installed = await _bridge.invokeMethod<String>('version');
        if (installed != null) {
          compareAppVersions(installed, '0.0.0');
          currentVersion = installed;
        }
      } catch (_) {
        /* The compiled version remains available in tests/older runners. */
      }
    }
    try {
      final saved = AppRelease.parse(
        jsonDecode(preferences.getString('$_key:candidate') ?? 'null'),
        platform,
      );
      if (saved != null &&
          compareAppVersions(saved.version, currentVersion) > 0) {
        release = saved;
        _releaseOrigin = api.server;
        phase = UpdatePhase.available;
      }
    } catch (_) {}
  }

  Future<void> check({bool force = false}) =>
      _check ??= _runCheck(force).whenComplete(() => _check = null);
  Future<void> _runCheck(bool force) async {
    if (!supported ||
        _disposed ||
        _download != null ||
        phase == UpdatePhase.installing) {
      return;
    }
    final preferences = _preferences;
    if (preferences == null) return;
    final origin = api.server, key = _key, now = clock().millisecondsSinceEpoch;
    final last = preferences.getInt('$key:checked') ?? 0;
    if (!force &&
        now >= last &&
        now - last < const Duration(days: 1).inMilliseconds) {
      return;
    }
    // Record the attempt before I/O: repeated launches during an outage stay quiet.
    await preferences.setInt('$key:checked', now);
    phase = UpdatePhase.checking;
    error = null;
    _publish();
    try {
      final response = await client.get(
        api.url('/api/releases'),
        options: Options(responseType: ResponseType.json),
      );
      if (_disposed || origin != api.server) return;
      final data = response.data;
      if (data is! Map || data['releases'] is! List) {
        throw const FormatException('Invalid update manifest');
      }
      AppRelease? newest;
      for (final value in data['releases']) {
        final candidate = AppRelease.parse(value, platform);
        if (candidate != null &&
            compareAppVersions(candidate.version, currentVersion) > 0 &&
            (newest == null ||
                compareAppVersions(candidate.version, newest.version) > 0)) {
          newest = candidate;
        }
      }
      release = newest;
      _releaseOrigin = origin;
      dismissed = false;
      if (newest == null) {
        await preferences.remove('$key:candidate');
        phase = UpdatePhase.idle;
      } else {
        await preferences.setString(
          '$key:candidate',
          jsonEncode(newest.toJson()),
        );
        phase = UpdatePhase.available;
      }
    } catch (_) {
      if (!_disposed && origin == api.server) {
        error = 'check';
        phase = release == null ? UpdatePhase.idle : UpdatePhase.available;
      }
    } finally {
      _publish();
    }
  }

  File _package(AppRelease value) => File(
    p.join(
      _directory!.path,
      'glukwave-${value.sha256}.${platform == 'windows' ? 'exe' : 'apk'}',
    ),
  );
  Future<bool> _verified(File file, AppRelease value) async {
    if (!await file.exists() || await file.length() != value.bytes) {
      return false;
    }
    final sink = Sha256().toSync().newHashSink();
    await for (final chunk in file.openRead()) {
      sink.add(chunk);
    }
    sink.close();
    return (await sink.hash()).bytes
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join() ==
        value.sha256;
  }

  Future<void> download() async {
    final candidate = release, origin = _releaseOrigin;
    if (candidate == null ||
        _directory == null ||
        _download != null ||
        origin != api.server ||
        _disposed) {
      return;
    }
    final cancel = CancelToken();
    final deadline = Timer(
      const Duration(minutes: 10),
      () => cancel.cancel('timeout'),
    );
    _download = cancel;
    final file = _package(candidate),
        partial = File('${_package(candidate).path}.partial');
    phase = UpdatePhase.downloading;
    progress = 0;
    error = null;
    _publish();
    IOSink? sink;
    try {
      await _directory!.create(recursive: true);
      if (!await _verified(file, candidate)) {
        final response = await client.get<ResponseBody>(
          api.url(candidate.url),
          options: Options(
            responseType: ResponseType.stream,
            followRedirects: false,
          ),
          cancelToken: cancel,
        );
        final length = int.tryParse(
          response.headers.value('content-length') ?? '',
        );
        final advertised = response.headers.value('x-content-sha256');
        if (response.statusCode != 200 ||
            (length != null && length != candidate.bytes) ||
            (advertised != null && advertised != candidate.sha256)) {
          throw const FormatException('Update changed');
        }
        sink = partial.openWrite();
        var received = 0;
        var buffered = 0, publishedAt = 0;
        await for (final chunk in response.data!.stream.timeout(
          const Duration(seconds: 20),
        )) {
          if (_disposed || cancel.isCancelled || origin != api.server) {
            throw const FormatException('Update cancelled');
          }
          received += chunk.length;
          if (received > candidate.bytes) {
            throw const FormatException('Update exceeds expected size');
          }
          sink.add(chunk);
          buffered += chunk.length;
          if (buffered >= 512 * 1024) {
            await sink.flush();
            buffered = 0;
          }
          progress = received / candidate.bytes;
          final tick = DateTime.now().millisecondsSinceEpoch;
          if (tick - publishedAt >= 120) {
            publishedAt = tick;
            _publish();
          }
        }
        await sink.flush();
        await sink.close();
        sink = null;
        if (!await _verified(partial, candidate)) {
          throw const FormatException('Invalid update checksum');
        }
        if (await file.exists()) await file.delete();
        await partial.rename(file.path);
      }
      if (!_disposed && origin == api.server && !cancel.isCancelled) {
        progress = 1;
        phase = UpdatePhase.ready;
      }
    } catch (_) {
      if (!_disposed) {
        error = cancel.isCancelled ? null : 'download';
        phase = cancel.isCancelled ? UpdatePhase.available : UpdatePhase.error;
      }
    } finally {
      deadline.cancel();
      await sink?.close();
      if (await partial.exists()) await partial.delete();
      if (identical(_download, cancel)) _download = null;
      _publish();
    }
  }

  void cancel() => _download?.cancel('user');
  void dismiss() {
    dismissed = true;
    _publish();
  }

  Future<void> install() async {
    final candidate = release;
    if (candidate == null ||
        phase != UpdatePhase.ready ||
        _releaseOrigin != api.server) {
      return;
    }
    final file = _package(candidate);
    try {
      if (!await _verified(file, candidate)) {
        throw const FormatException('Invalid update checksum');
      }
      if (_disposed ||
          _releaseOrigin != api.server ||
          !identical(release, candidate)) {
        return;
      }
      phase = UpdatePhase.installing;
      error = null;
      _publish();
      if (installer != null) {
        await installer!(file, platform);
      } else if (platform == 'windows') {
        await Process.start(
          file.path,
          const [],
          mode: ProcessStartMode.detached,
          runInShell: false,
        );
      } else {
        await _bridge.invokeMethod('install', {'path': file.path});
      }
      // The OS owns confirmation and may refuse/close its installer.
      phase = UpdatePhase.ready;
    } catch (_) {
      error = 'install';
      phase = UpdatePhase.error;
    }
    _publish();
  }

  @override
  void dispose() {
    _disposed = true;
    cancel();
    client.close(force: true);
    super.dispose();
  }
}
