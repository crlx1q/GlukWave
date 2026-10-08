import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';

String scrubDiagnostic(Object? input, [int limit = 2000]) {
  var value = '${input ?? ''}';
  if (value.length > 12000) value = value.substring(0, 12000);
  value = value
      .replaceAll(
        RegExp(r'''\bBearer\s+[^\s,;"']+''', caseSensitive: false),
        'Bearer [redacted]',
      )
      .replaceAllMapped(
        RegExp(
          r'''(["']?(?:password|passwd|token|secret|authorization|cookie|api[_-]?key|captchaToken)["']?\s*[:=]\s*)(?:"[^"\r\n]*"|'[^'\r\n]*'|[^\s,;}"']+)''',
          caseSensitive: false,
        ),
        (match) => '${match[1]}[redacted]',
      )
      .replaceAll(
        RegExp(
          r'''(?:mongodb(?:\+srv)?|postgres(?:ql)?|redis)://[^\s<>"')]+''',
          caseSensitive: false,
        ),
        '[connection]',
      )
      .replaceAll(RegExp(r'\b(?:cmp_live_|sk_live_)[\w-]+'), '[redacted]')
      .replaceAll(
        RegExp(
          r'\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b',
          caseSensitive: false,
        ),
        '[email]',
      )
      .replaceAll(
        RegExp(
          r'(?:[A-Z]:[\\/]Users[\\/]|/Users/|/home/)[^\s\\/]+',
          caseSensitive: false,
        ),
        '[user-path]',
      )
      .replaceAllMapped(
        RegExp(r'''https?://[^\s<>"')]+''', caseSensitive: false),
        (match) {
          final uri = Uri.tryParse(match[0]!);
          return uri == null
              ? '[url]'
              : '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}${uri.path}';
        },
      )
      .replaceAll(RegExp(r'\?[^\s)\]]+'), '?[redacted]')
      .replaceAll(RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]'), '');
  return value.length > limit ? value.substring(0, limit) : value;
}

/// Bounded, memory-only queue. Reporting never uses the main API interceptor.
class WaveDiagnostics {
  final String Function() origin;
  final Map<String, String> Function() headers;
  final Dio _transport = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
    ),
  );
  final List<Map<String, dynamic>> _queue = [];
  final Map<String, DateTime> _seen = {};
  Timer? _timer;
  bool _sending = false, _disposed = false;
  int _delay = 30;
  String? _scope;
  WaveDiagnostics(this.origin, this.headers);
  String get _platform => Platform.isAndroid
      ? 'android'
      : Platform.isWindows
      ? 'windows'
      : Platform.isIOS
      ? 'ios'
      : 'windows';
  void report(
    Object error, {
    String kind = 'background',
    StackTrace? stack,
    String? code,
    int? status,
  }) {
    if (_disposed) return;
    final message = scrubDiagnostic(error);
    final key = '$kind:$message';
    if (_seen[key]?.isAfter(
          DateTime.now().subtract(const Duration(minutes: 1)),
        ) ==
        true) {
      return;
    }
    if (_seen.length >= 100) _seen.remove(_seen.keys.first);
    _seen[key] = DateTime.now();
    // Changing accounts/server must never transmit an old session's queue.
    final scope = '${origin()}:${headers()['Authorization'] ?? ''}';
    if (_scope != scope) {
      _queue.clear();
      _scope = scope;
    }
    if (_queue.length >= 30) _queue.removeAt(0);
    _queue.add({
      'platform': _platform,
      'kind': kind,
      'message': message,
      'stack': scrubDiagnostic(stack, 8000),
      'version': '1.0.0+3',
      if (code != null) 'code': scrubDiagnostic(code, 100),
      if (status != null && status >= 0 && status <= 599) 'status': status,
    });
    _schedule(1);
  }

  void _schedule(int seconds) {
    if (_disposed || _timer != null || _queue.isEmpty) return;
    _timer = Timer(Duration(seconds: seconds), () {
      _timer = null;
      unawaited(flush());
    });
  }

  Future<void> flush() async {
    if (_sending || _disposed || _queue.isEmpty) return;
    if (_scope != '${origin()}:${headers()['Authorization'] ?? ''}') {
      _queue.clear();
      return;
    }
    _sending = true;
    final events = _queue.take(10).toList();
    try {
      final result = await _transport.post<dynamic>(
        '${origin()}/api/diagnostics/events',
        data: {'events': events},
        options: Options(headers: headers(), validateStatus: (_) => true),
      );
      if (result.statusCode == 202 ||
          result.statusCode == 400 ||
          result.statusCode == 413) {
        for (final event in events) {
          _queue.remove(event);
        }
        _delay = 30;
      } else {
        _delay = (_delay * 2).clamp(30, 300);
      }
    } catch (_) {
      _delay = (_delay * 2).clamp(30, 300);
    } finally {
      _sending = false;
      _schedule(_delay);
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _queue.clear();
    _transport.close(force: true);
  }
}
