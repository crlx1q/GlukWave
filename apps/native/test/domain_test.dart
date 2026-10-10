import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:glukwave/core/api.dart';
import 'package:glukwave/core/models.dart';

void main() {
  test(
    'Duration uses hours at the exact boundary and guards invalid values',
    () {
      expect(clock(-1), '0:00');
      expect(clock(double.nan), '0:00');
      expect(clock(double.infinity), '0:00');
      expect(clock(0), '0:00');
      expect(clock(59.999), '0:59');
      expect(clock(60), '1:00');
      expect(clock(3599.999), '59:59');
      expect(clock(3600), '1:00:00');
      expect(clock(4800), '1:20:00');
      expect(clock(7200), '2:00:00');
      expect(clock(360000), '100:00:00');
      expect(lrcClock(4800.25), '80:00.250');
      expect(lrcClock(9.5), '00:09.500');
      expect(lrcClock(double.nan), '00:00.000');
    },
  );
  test('Room access comes from the owner or explicit control grant', () {
    final room = {
      'ownerId': 'owner',
      'members': [
        {'userId': 'guest', 'canControl': false},
        {'userId': 'dj', 'canControl': true},
      ],
    };
    expect(mayControlRoom(room, 'owner'), isTrue);
    expect(mayControlRoom(room, 'dj'), isTrue);
    expect(mayControlRoom(room, 'guest'), isFalse);
    expect(mayControlRoom(room, 'stranger'), isFalse);
  });
  test(
    'Authoritative timeline projects only while playing and clamps to duration',
    () {
      const state = PlaybackSnapshot(
        position: 30,
        playing: true,
        updatedAt: 100000,
        revision: 4,
      );
      expect(state.projectedPosition(104500), 34.5);
      expect(state.projectedPosition(104500, duration: 32), 32);
      expect(state.projectedPosition(99000), 30);
      const paused = PlaybackSnapshot(
        position: 30,
        playing: false,
        updatedAt: 100000,
      );
      expect(paused.projectedPosition(140000), 30);
      expect(PlaybackSnapshot.fromJson(state.toJson()).revision, 4);
    },
  );
  test('External metadata does not become downloadable music', () {
    final external = WaveTrack({
      'id': 'spotify-1',
      'source': 'spotify',
      'playback': {'kind': 'spotify', 'offline': true},
    });
    // Metadata can enter the queue for server resolution, but cannot enter
    // the offline cache or directly authorize an audio URL.
    expect(external.playable, isTrue);
    expect(external.offline, isFalse);
    final local = WaveTrack({
      'id': 'audio-1',
      'playback': {'kind': 'audio', 'offline': true},
    });
    expect(local.playable, isTrue);
    expect(local.offline, isTrue);
    expect(
      WaveTrack({
        'id': 'shared',
        'playback': {'kind': 'audio', 'offline': false},
      }).offline,
      isFalse,
    );
  });
  test('Synchronized lyrics choose the preceding timed line', () {
    final lines = [
      {'time': 4, 'text': 'one'},
      {'time': 9.5, 'text': 'two'},
    ];
    expect(activeLyric(lines, 0), -1);
    expect(activeLyric(lines, 9.4), 0);
    expect(activeLyric(lines, 9.5), 1);
  });
  test('Server addresses reject credentials, paths and invalid schemes', () {
    expect(
      WaveApi.validateServer(' http://127.0.0.1:4000/ '),
      'http://127.0.0.1:4000',
    );
    expect(
      () => WaveApi.validateServer('file:///private'),
      throwsA(isA<WaveException>()),
    );
    expect(
      () => WaveApi.validateServer('https://secret:pass@wave.gluk.tech'),
      throwsA(isA<WaveException>()),
    );
    expect(
      () => WaveApi.validateServer('https://wave.gluk.tech/path'),
      throwsA(isA<WaveException>()),
    );
  });
  test(
    'Native API sends bearer separately and preserves server errors',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      String? bearer, client, language;
      final subscription = server.listen((request) async {
        bearer = request.headers.value('authorization');
        client = request.headers.value('x-glukwave-client');
        language = request.headers.value('accept-language');
        request.response.headers.contentType = ContentType.json;
        if (request.uri.path == '/api/private') {
          request.response.statusCode = 403;
          request.response.write(
            jsonEncode({
              'error': {'code': 'forbidden', 'message': 'Нет доступа'},
            }),
          );
        } else {
          request.response.write(
            jsonEncode({
              'user': {'id': 'one'},
            }),
          );
        }
        await request.response.close();
      });
      final api = WaveApi('http://127.0.0.1:${server.port}')
        ..language = 'de'
        ..token = 'opaque-native-session';
      try {
        final result = await api.call('/api/auth/me');
        expect(object(result['user'])['id'], 'one');
        expect(bearer, 'Bearer opaque-native-session');
        expect(client, 'native');
        expect(language, 'de');
        await api.localeMetadata('kk');
        expect(language, 'kk');
        expect(api.language, 'de');
        expect(
          api.url('/api/media/id'),
          isNot(contains('opaque-native-session')),
        );
        await expectLater(
          api.call('/api/private'),
          throwsA(
            isA<WaveException>().having(
              (error) => error.code,
              'code',
              'forbidden',
            ),
          ),
        );
      } finally {
        api.dio.close(force: true);
        await subscription.cancel();
        await server.close(force: true);
      }
    },
  );
}
