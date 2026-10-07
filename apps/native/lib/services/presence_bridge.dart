import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../core/models.dart';
import '../core/api.dart';

class PresenceBridge {
  HttpServer? _server;
  String secret = '';
  Set<String> origins = {};
  bool get enabled => _server != null;
  Future<void> start(
    String pairing,
    Set<String> allowed,
    Future<void> Function(Json) apply,
  ) async {
    if (enabled) {
      return;
    }
    secret = pairing;
    origins = allowed;
    _server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      4002,
      shared: false,
    );
    _server!.listen((request) {
      unawaited(_handle(request, apply));
    });
  }

  Future<void> _handle(
    HttpRequest request,
    Future<void> Function(Json) apply,
  ) async {
    final response = request.response;
    try {
      final origin = request.headers.value('Origin');
      if (origin == null || !origins.contains(origin)) {
        response.statusCode = 403;
        return;
      }
      response.headers.set('Access-Control-Allow-Origin', origin);
      response.headers.set('Vary', 'Origin');
      response.headers.set(
        'Access-Control-Allow-Methods',
        'GET, POST, OPTIONS',
      );
      response.headers.set(
        'Access-Control-Allow-Headers',
        'Content-Type, X-GlukWave-Pair',
      );
      if (request.method == 'OPTIONS') {
        response.statusCode = 204;
        return;
      }
      response.headers.contentType = ContentType.json;
      if (request.uri.path == '/health' && request.method == 'GET') {
        response.write(jsonEncode({'status': 'ok', 'app': 'GlukWave'}));
        return;
      }
      if (request.uri.path != '/presence' ||
          request.method != 'POST' ||
          request.headers.value('X-GlukWave-Pair') != secret) {
        response.statusCode = 403;
        response.write(
          jsonEncode({
            'error': {'message': 'Pairing required'},
          }),
        );
        return;
      }
      final bytes = <int>[];
      await for (final chunk in request) {
        bytes.addAll(chunk);
        if (bytes.length > 4096) {
          throw const WaveException('Presence payload too large');
        }
      }
      final data = object(jsonDecode(utf8.decode(bytes)));
      if (data['trackId'] != null && data['trackId'] is! String ||
          data['playing'] is! bool ||
          number(data['position']) < 0) {
        throw const WaveException('Invalid presence state');
      }
      await apply(data);
      response.write(jsonEncode({'ok': true}));
    } catch (error) {
      response.statusCode = 400;
      response.write(
        jsonEncode({
          'error': {'message': error.toString()},
        }),
      );
    } finally {
      await response.close();
    }
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }
}
