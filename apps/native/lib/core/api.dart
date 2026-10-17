import '../l10n/wave_localizations.dart';
import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'models.dart';
import '../services/diagnostics.dart';
import '../services/metadata_cache.dart';

class WaveException implements Exception {
  final String message, code;
  final int? status;
  const WaveException(
    this.message, [
    this.code = 'request_failed',
    this.status,
  ]);
  @override
  String toString() => message;
}

class WaveApi {
  final MetadataCache metadata = MetadataCache();
  final Map<String, Future<Json>> _metadataFlights = {};
  String? _metadataIdentity;
  String get _identity => '$server:${token ?? ""}';
  void _checkMetadataScope() {
    if (_metadataIdentity == _identity) return;
    _metadataIdentity = _identity;
    metadata.reset();
    _metadataFlights.clear();
  }

  Future<void> openMetadata(Directory directory, String owner) async {
    _metadataIdentity = _identity;
    _metadataFlights.clear();
    await metadata.open(directory, owner);
  }

  Json? peekMetadata(String path, {Json? query}) {
    _checkMetadataScope();
    return metadata.peek(MetadataCache.key(path, query));
  }

  Future<Json> cachedCall(
    String path, {
    Json? query,
    Duration maxAge = const Duration(minutes: 2),
    bool force = false,
  }) {
    _checkMetadataScope();
    final key = MetadataCache.key(path, query), identity = _identity;
    final saved = metadata.peek(key);
    if (!force && saved != null && metadata.fresh(key, maxAge)) {
      return Future.value(saved);
    }
    final active = _metadataFlights[key];
    if (active != null) return active;
    final job = () async {
      try {
        final value = await call(path, query: query);
        if (identity != _identity || _metadataIdentity != identity) {
          throw const WaveException('Session changed', 'STALE_REQUEST');
        }
        metadata.put(key, value);
        return value;
      } catch (error) {
        if (identity == _identity &&
            error is WaveException &&
            [401, 403, 404].contains(error.status)) {
          metadata.remove(key);
        }
        if (identity == _identity &&
            saved != null &&
            !(error is WaveException &&
                [401, 403, 404].contains(error.status))) {
          return saved;
        }
        rethrow;
      }
    }();
    _metadataFlights[key] = job;
    unawaited(
      job.then<void>(
        (_) {
          if (identical(_metadataFlights[key], job)) {
            _metadataFlights.remove(key);
          }
        },
        onError: (Object _, StackTrace __) {
          if (identical(_metadataFlights[key], job)) {
            _metadataFlights.remove(key);
          }
        },
      ),
    );
    return job;
  }

  String _playbackScope = '';
  final Map<String, ({DateTime at, Future<Json> job})> _playbackWarmup = {};
  final Dio dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'X-GlukWave-Client': 'native'},
    ),
  );
  String server;
  String language = 'en';
  String? token;
  String deviceId = '', surfaceId = '';
  String clientKind = Platform.isWindows
      ? 'windows'
      : Platform.isIOS
      ? 'ios'
      : 'android';
  String deviceName = '';
  final Future<void> Function(Duration) playbackDelay;
  late final WaveDiagnostics diagnostics;
  WaveApi(String value, {Future<void> Function(Duration)? playbackDelay})
    : server = validateServer(value),
      playbackDelay = playbackDelay ?? Future<void>.delayed {
    diagnostics = WaveDiagnostics(() => server, () => headers);
    dio.interceptors.add(
      InterceptorsWrapper(
        onError: (error, handler) {
          final status = error.response?.statusCode;
          if (error.type != DioExceptionType.cancel &&
              (status == null || status >= 500)) {
            diagnostics.report(
              error.response == null
                  ? 'Network request failed: ${error.type.name}'
                  : 'Server request failed',
              kind: 'network',
              stack: error.stackTrace,
              code: object(
                object(error.response?.data)['error'],
              )['code']?.toString(),
              status: status,
            );
          }
          handler.next(error);
        },
      ),
    );
  }
  String url(String path) => Uri.parse('$server/').resolve(path).toString();
  Map<String, String> get headers => {
    'X-GlukWave-Client': 'native',
    'X-GlukWave-Kind': clientKind,
    // dart:io rejects Unicode header values before making a connection.
    if (deviceName.isNotEmpty)
      'X-GlukWave-Device-Name': Uri.encodeComponent(deviceName),
    'Accept-Language': language,
    if (deviceId.isNotEmpty) 'X-GlukWave-Device': deviceId,
    if (surfaceId.isNotEmpty) 'X-GlukWave-Surface': surfaceId,
    if (token != null) 'Authorization': 'Bearer $token',
  };
  Future<Json> localeMetadata(String browserLanguage) async {
    final response = await dio.get<dynamic>(
      url('/api/locale'),
      options: Options(
        headers: {...headers, 'Accept-Language': browserLanguage},
      ),
    );
    return object(response.data);
  }

  /// A bounded reachability probe; cancellation also stops the underlying I/O.
  Future<Json> probe() async {
    final cancellation = CancelToken();
    final budget = Timer(
      const Duration(seconds: 6),
      () => cancellation.cancel('Connectivity deadline'),
    );
    try {
      final response = await dio.get<dynamic>(
        url('/api/config'),
        cancelToken: cancellation,
        options: Options(
          headers: headers,
          receiveTimeout: const Duration(seconds: 6),
        ),
      );
      return object(response.data);
    } on DioException catch (error) {
      throw WaveException(
        wt('native.5918da6940'),
        'network',
        error.response?.statusCode,
      );
    } finally {
      budget.cancel();
    }
  }

  static String validateServer(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        uri.host.isEmpty ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw WaveException(wt('native.8a5e96055a'));
    }
    if (!kDebugMode &&
        uri.scheme != 'https' &&
        !['localhost', '127.0.0.1', '::1'].contains(uri.host)) {
      throw WaveException(wt('native.6ade2e521e'));
    }
    return uri.origin;
  }

  Future<Json> call(
    String path, {
    String method = 'GET',
    dynamic data,
    Json? query,
  }) async {
    final playback =
        method == 'GET' &&
        RegExp(r'^/api/tracks/[^/]+/playback$').hasMatch(path);
    final action =
        method == 'POST' &&
        (path == '/api/devices/command' ||
            RegExp(r'^/api/integrations/[^/]+/import$').hasMatch(path));
    final intent = action
        ? (object(data)['requestId']?.toString() ??
              'native-${DateTime.now().microsecondsSinceEpoch}')
        : '';
    final poll = playback || action;
    final account = token, origin = server;
    final deadline = DateTime.now().add(Duration(minutes: action ? 5 : 2));
    var retries = 0;
    while (true) {
      if (poll &&
          (!DateTime.now().isBefore(deadline) ||
              account != token ||
              origin != server)) {
        throw WaveException(
          wt('native.5918da6940'),
          action ? 'ACTION_TIMEOUT' : 'PLAYBACK_TIMEOUT',
        );
      }
      final cancellation = poll ? CancelToken() : null;
      final budget = poll
          ? Timer(
              deadline.difference(DateTime.now()),
              () => cancellation!.cancel('Playback resolution deadline'),
            )
          : null;
      try {
        final result = await dio.request<dynamic>(
          url(path),
          data: data,
          queryParameters: query,
          cancelToken: cancellation,
          options: Options(
            method: method,
            headers: {
              ...headers,
              if (playback) 'X-GlukWave-Playback-Wait': 'poll',
              if (action) 'X-GlukWave-Command-Wait': 'poll',
              if (action) 'X-GlukWave-Intent': intent,
            },
            receiveTimeout: poll ? const Duration(seconds: 15) : null,
          ),
        );
        if (poll && result.statusCode == 202) {
          if (DateTime.now().isAfter(deadline)) {
            throw WaveException(
              wt('native.5918da6940'),
              action ? 'ACTION_TIMEOUT' : 'PLAYBACK_TIMEOUT',
            );
          }
          final seconds =
              (int.tryParse(result.headers.value('retry-after') ?? '') ?? 2)
                  .clamp(1, 4);
          await playbackDelay(Duration(seconds: seconds));
          continue;
        }
        return object(result.data);
      } on DioException catch (error) {
        if (poll && !DateTime.now().isBefore(deadline)) {
          throw WaveException(
            wt('native.5918da6940'),
            action ? 'ACTION_TIMEOUT' : 'PLAYBACK_TIMEOUT',
          );
        }
        final status = error.response?.statusCode;
        final temporary =
            [502, 503, 504].contains(status) ||
            [
              DioExceptionType.connectionTimeout,
              DioExceptionType.receiveTimeout,
              DioExceptionType.connectionError,
            ].contains(error.type);
        if (poll &&
            temporary &&
            retries < 2 &&
            DateTime.now().isBefore(deadline)) {
          await playbackDelay(Duration(milliseconds: 600 * ++retries));
          continue;
        }
        final detail = object(object(error.response?.data)['error']);
        throw WaveException(
          detail['message']?.toString() ?? wt('native.5918da6940'),
          detail['code']?.toString() ??
              (error.response?.statusCode == 401 ? 'unauthorized' : 'network'),
          error.response?.statusCode,
        );
      } finally {
        budget?.cancel();
      }
    }
  }

  Future<Json> upload(
    String path,
    String filePath, {
    Json fields = const {},
    void Function(double)? progress,
  }) async {
    const mimeTypes = {
      'mp3': 'audio/mpeg',
      'wav': 'audio/wav',
      'm4a': 'audio/mp4',
      'aac': 'audio/aac',
      'flac': 'audio/flac',
      'ogg': 'audio/ogg',
      'opus': 'audio/ogg',
      'webm': 'audio/webm',
      'gif': 'image/gif',
      'png': 'image/png',
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'webp': 'image/webp',
      'csv': 'text/csv',
      'json': 'application/json',
    };
    final mime = mimeTypes[filePath.split('.').last.toLowerCase()];
    final data = FormData.fromMap({
      ...fields,
      'file': await MultipartFile.fromFile(
        filePath,
        contentType: mime != null ? DioMediaType.parse(mime) : null,
      ),
    });
    try {
      final result = await dio.post<dynamic>(
        url(path),
        data: data,
        options: Options(
          headers: headers,
          sendTimeout: const Duration(minutes: 10),
          receiveTimeout: const Duration(minutes: 3),
        ),
        onSendProgress: (sent, total) =>
            progress?.call(total > 0 ? sent / total : 0),
      );
      return object(result.data);
    } on DioException catch (error) {
      final detail = object(object(error.response?.data)['error']);
      throw WaveException(
        detail['message'] as String? ?? wt('native.6a2f34c7ec'),
        detail['code'] as String? ?? 'upload',
      );
    }
  }

  Future<void> download(
    WaveTrack track,
    File target, {
    void Function(double)? progress,
    CancelToken? cancelToken,
  }) async {
    try {
      await dio.download(
        downloadUrl(track),
        target.path,
        options: Options(
          headers: headers,
          receiveTimeout: const Duration(minutes: 10),
        ),
        deleteOnError: true,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) =>
            progress?.call(total > 0 ? received / total : 0),
      );
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) {
        throw WaveException(wt('native.7e03f83d51'), 'cancelled');
      }
      if (error.response?.statusCode == 401 ||
          error.response?.statusCode == 403) {
        throw WaveException(wt('native.3d96e7d07c'), 'download_forbidden');
      }
      throw WaveException(wt('native.5eb9f20ac7'), 'download');
    }
  }

  Future<WaveTrack> resolvePlayback(
    WaveTrack track, {
    bool fresh = false,
  }) async {
    final scope = '$server:$token';
    if (_playbackScope != scope) {
      _playbackScope = scope;
      _playbackWarmup.clear();
    }
    final existing = _playbackWarmup[track.id];
    if (fresh ||
        existing != null &&
            DateTime.now().difference(existing.at) >
                const Duration(seconds: 60)) {
      _playbackWarmup.remove(track.id);
    }
    var entry = _playbackWarmup[track.id];
    if (entry == null) {
      entry = (
        at: DateTime.now(),
        job: call('/api/tracks/${Uri.encodeComponent(track.id)}/playback'),
      );
      _playbackWarmup[track.id] = entry;
      while (_playbackWarmup.length > 3) {
        _playbackWarmup.remove(_playbackWarmup.keys.first);
      }
    }
    Json data;
    try {
      data = await entry.job;
    } catch (_) {
      if (identical(_playbackWarmup[track.id]?.job, entry.job)) {
        _playbackWarmup.remove(track.id);
      }
      rethrow;
    }
    final descriptor = object(data['playback']);
    if (descriptor['kind'] != 'audio' ||
        descriptor['url'] is! String ||
        (descriptor['url'] as String).isEmpty) {
      if (identical(_playbackWarmup[track.id]?.job, entry.job)) {
        _playbackWarmup.remove(track.id);
      }
      throw WaveException(wt('native.266e43ddb8'), 'AUDIO_UNAVAILABLE');
    }
    return WaveTrack({...track.json, 'playback': descriptor});
  }

  String downloadUrl(WaveTrack track) {
    final supplied = track.playback['downloadUrl'];
    if (supplied is String) {
      final target = Uri.tryParse(url(supplied));
      if (target != null &&
          ['http', 'https'].contains(target.scheme) &&
          target.userInfo.isEmpty &&
          target.origin == Uri.parse(server).origin &&
          target.path.startsWith('/api/')) {
        return target.toString();
      }
      throw WaveException(wt('native.3d96e7d07c'), 'download_forbidden');
    }
    return url('/api/media/${Uri.encodeComponent(track.id)}/download');
  }
}
