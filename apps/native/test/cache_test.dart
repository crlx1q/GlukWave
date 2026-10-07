import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glukwave/core/api.dart';
import 'package:glukwave/core/models.dart';
import 'package:glukwave/services/cache.dart';

class DownloadApi extends WaveApi {
  bool slow = false;
  DownloadApi() : super('http://127.0.0.1:4000');
  @override
  Future<void> download(
    WaveTrack track,
    File target, {
    void Function(double)? progress,
    CancelToken? cancelToken,
  }) async {
    if (slow) {
      await Future.any([
        Future<void>.delayed(const Duration(seconds: 10)),
        cancelToken!.whenCancel,
      ]);
      if (cancelToken.isCancelled) {
        throw const WaveException('Cancelled', 'cancelled');
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await target.writeAsBytes(List.filled(600 * 1024, 42));
    progress?.call(1);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  WaveTrack track(String id) => WaveTrack({
    'id': id,
    'title': id,
    'playback': {'kind': 'audio', 'offline': true},
  });
  late Directory directory;
  late DownloadApi api;
  late MusicCache cache;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('glukwave-cache-test-');
    api = DownloadApi();
    cache = MusicCache(api)
      ..directory = directory
      ..limitMB = 1;
  });
  tearDown(() async {
    cache.activeId = null;
    await cache.clear(includingDownloads: true);
    cache.dispose();
    api.dio.close(force: true);
    await directory.delete(recursive: true);
  });
  test('Concurrent downloads commit quota and manifest atomically', () async {
    await Future.wait([cache.save(track('one')), cache.save(track('two'))]);
    expect(cache.bytes, lessThanOrEqualTo(1024 * 1024));
    expect(cache.entries.length, 1);
    final manifest = object(
      jsonDecode(await File('${directory.path}/manifest.json').readAsString()),
    );
    expect(manifest.keys.toSet(), cache.entries.keys.toSet());
  });
  test('Pinned downloads are preserved when quota is exhausted', () async {
    await cache.save(track('one'), manual: true);
    await expectLater(cache.save(track('two')), throwsA(isA<WaveException>()));
    expect(cache.contains('one'), isTrue);
    expect(cache.contains('two'), isFalse);
  });
  test(
    'Concurrent LRU accesses and manual pinning cannot lose metadata',
    () async {
      await cache.save(track('one'));
      await Future.wait([
        cache.fileFor('one'),
        cache.save(track('one'), manual: true),
        cache.fileFor('one'),
      ]);
      expect(object(cache.entries['one'])['manual'], isTrue);
      expect(
        jsonDecode(
          await File('${directory.path}/manifest.json').readAsString(),
        ),
        cache.entries,
      );
    },
  );
  test(
    'Clearing private files cancels downloads and leaves no audio',
    () async {
      api.slow = true;
      final pending = cache.save(track('one'));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await cache.clear(includingDownloads: true);
      await pending;
      expect(cache.entries, isEmpty);
      expect(
        directory.listSync().where(
          (entry) =>
              entry.path.endsWith('.audio') || entry.path.endsWith('.part'),
        ),
        isEmpty,
      );
    },
  );
}
