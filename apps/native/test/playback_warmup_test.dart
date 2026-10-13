import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:glukwave/core/api.dart';
import 'package:glukwave/core/models.dart';

class PreparedApi extends WaveApi {
  PreparedApi() : super('http://127.0.0.1:4000');
  int calls = 0;
  Future<Json> Function(String)? result;
  @override
  Future<Json> call(
    String path, {
    String method = 'GET',
    dynamic data,
    Json? query,
  }) async {
    calls++;
    return result?.call(path) ??
        {
          'playback': {'kind': 'audio', 'url': '/prepared'},
        };
  }
}

void main() {
  test('native preparation shares work and keeps current metadata', () async {
    final api = PreparedApi()..token = 'a', pending = Completer<Json>();
    api.result = (_) => pending.future;
    final first = api.resolvePlayback(
      WaveTrack({'id': 'same', 'title': 'Old'}),
    );
    final second = api.resolvePlayback(
      WaveTrack({'id': 'same', 'title': 'Updated'}),
    );
    expect(api.calls, 1);
    pending.complete({
      'playback': {'kind': 'audio', 'url': '/same'},
    });
    expect((await first).title, 'Old');
    expect((await second).title, 'Updated');
    await api.resolvePlayback(WaveTrack({'id': 'same'}));
    expect(api.calls, 1);
    await api.resolvePlayback(WaveTrack({'id': 'same'}), fresh: true);
    expect(api.calls, 2);
    api.diagnostics.dispose();
    api.dio.close(force: true);
  });
  test(
    'native preparation drops rejected descriptors and scopes cache to account and server',
    () async {
      final api = PreparedApi()..token = 'a';
      api.result = (_) async => {
        'playback': {'kind': 'audio'},
      };
      await expectLater(
        api.resolvePlayback(WaveTrack({'id': 'same'})),
        throwsA(isA<WaveException>()),
      );
      api.result = (_) async => {
        'playback': {'kind': 'audio', 'url': '/a'},
      };
      expect(
        (await api.resolvePlayback(WaveTrack({'id': 'same'}))).playback['url'],
        '/a',
      );
      expect(api.calls, 2);
      api.token = 'b';
      api.result = (_) async => {
        'playback': {'kind': 'audio', 'url': '/b'},
      };
      expect(
        (await api.resolvePlayback(WaveTrack({'id': 'same'}))).playback['url'],
        '/b',
      );
      api.server = 'http://127.0.0.1:4001';
      await api.resolvePlayback(WaveTrack({'id': 'same'}));
      expect(api.calls, 4);
      for (final id in ['two', 'three', 'four']) {
        await api.resolvePlayback(WaveTrack({'id': id}));
      }
      await api.resolvePlayback(WaveTrack({'id': 'same'}));
      expect(api.calls, 8);
      api.diagnostics.dispose();
      api.dio.close(force: true);
    },
  );
}
