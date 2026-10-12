import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:glukwave/core/api.dart';
import 'package:glukwave/core/models.dart';

class RealHttp extends HttpOverrides {}

void main() {
  test(
    'real native HTTP accepts Unicode device names and polls audio through a transient edge failure',
    () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        var playbackCalls = 0, deniedCalls = 0, postCalls = 0;
        final waits = <int>[];
        final api = WaveApi(
          'http://127.0.0.1:${server.port}',
          playbackDelay: (duration) async => waits.add(duration.inMilliseconds),
        );
        api.deviceName = 'GlukWave · Windows — Алишер';
        final names = <String>[];
        server.listen((request) async {
          names.add(
            Uri.decodeComponent(
              request.headers.value('x-glukwave-device-name')!,
            ),
          );
          request.response.headers.contentType = ContentType.json;
          Object body = {};
          if (request.uri.path == '/api/config') {
            body = {'ok': true};
          } else if (request.uri.path == '/api/tracks/song/playback') {
            expect(request.headers.value('x-glukwave-playback-wait'), 'poll');
            playbackCalls++;
            if (playbackCalls == 1) {
              request.response.statusCode = 504;
            } else if (playbackCalls == 2) {
              request.response.statusCode = 202;
              request.response.headers.set('Retry-After', '99');
              body = {'pending': true};
            } else {
              body = {
                'playback': {'kind': 'audio', 'url': '/api/audio/song'},
              };
            }
          } else if (request.method == 'POST') {
            postCalls++;
            request.response.statusCode = 504;
          } else {
            deniedCalls++;
            request.response.statusCode = 401;
            body = {
              'error': {'code': 'AUTH_REQUIRED', 'message': 'Please sign in'},
            };
          }
          request.response.write(jsonEncode(body));
          await request.response.close();
        });
        try {
          expect((await api.call('/api/config'))['ok'], true);
          final result = await api.resolvePlayback(WaveTrack({'id': 'song'}));
          expect(result.playback['url'], '/api/audio/song');
          expect(playbackCalls, 3);
          expect(waits, [600, 4000]);
          expect(names.every((name) => name == api.deviceName), true);
          await expectLater(
            api.call('/api/tracks/denied/playback'),
            throwsA(
              isA<WaveException>().having((e) => e.status, 'status', 401),
            ),
          );
          expect(deniedCalls, 1);
          await expectLater(
            api.call('/api/rooms', method: 'POST', data: {}),
            throwsA(
              isA<WaveException>().having((e) => e.status, 'status', 504),
            ),
          );
          expect(postCalls, 1);
          expect((await api.call('/api/config'))['ok'], true);
        } finally {
          api.diagnostics.dispose();
          api.dio.close(force: true);
          await server.close(force: true);
        }
      }, RealHttp());
    },
  );
}
