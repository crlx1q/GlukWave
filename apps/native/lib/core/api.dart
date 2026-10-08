import '../l10n/wave_localizations.dart';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'models.dart';
import '../services/diagnostics.dart';

class WaveException implements Exception {
  final String message, code;
  const WaveException(this.message, [this.code = 'request_failed']);
  @override
  String toString() => message;
}

class WaveApi {
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
  late final WaveDiagnostics diagnostics;
  WaveApi(String value) : server = validateServer(value) {
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
              code:
                  object(object(error.response?.data)['error'])['code']
                      as String?,
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
    'Accept-Language': language,
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
    try {
      final result = await dio.request<dynamic>(
        url(path),
        data: data,
        queryParameters: query,
        options: Options(method: method, headers: headers),
      );
      return object(result.data);
    } on DioException catch (error) {
      final detail = object(object(error.response?.data)['error']);
      throw WaveException(
        detail['message'] as String? ?? wt('native.5918da6940'),
        detail['code'] as String? ??
            (error.response?.statusCode == 401 ? 'unauthorized' : 'network'),
      );
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
        url('/api/media/${Uri.encodeComponent(track.id)}/download'),
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
}
