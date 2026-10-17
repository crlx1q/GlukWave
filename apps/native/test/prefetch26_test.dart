import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glukwave/core/api.dart';
import 'package:glukwave/core/models.dart';
import 'package:glukwave/services/audio.dart';
import 'package:glukwave/services/cache.dart';
import 'audio_lifecycle_test.dart' as fixture;

class PrefetchCache extends fixture.PlaybackCache {
  final prepared = <String>[], cancelled = <String>[];
  final pending = <String, Completer<void>>{};
  PrefetchCache(super.api);
  @override
  Future<void> prefetch(WaveTrack track) async {
    prepared.add(track.id);
    await (pending[track.id] = Completer<void>()).future;
  }

  @override
  void cancelPrefetch(String id) {
    cancelled.add(id);
  }

  void finish() {
    for (final item in pending.values) {
      if (!item.isCompleted) item.complete();
    }
  }
}

class ControlledDownload extends WaveApi {
  final ready = Completer<void>(), finish = Completer<void>();
  CancelToken? cancellation;
  int downloads = 0;
  ControlledDownload() : super('http://127.0.0.1:4000');
  @override
  Future<void> download(
    WaveTrack track,
    File target, {
    void Function(double)? progress,
    CancelToken? cancelToken,
  }) async {
    downloads++;
    cancellation = cancelToken;
    if (!ready.isCompleted) ready.complete();
    await Future.any([finish.future, cancelToken!.whenCancel]);
    if (cancelToken.isCancelled) {
      throw const WaveException('cancelled', 'cancelled');
    }
    await target.writeAsBytes([73, 68, 51, ...List.filled(2048, 42)]);
  }
}

Future<void> tick() => Future<void>.delayed(const Duration(milliseconds: 20));
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'prepares two successors in order and cancels obsolete queue work without skipping playback',
    () async {
      final api = fixture.PlaybackApi(),
          cache = PrefetchCache(api),
          output = fixture.NativeOutput();
      final audio = WaveAudioHandler(api, cache, output: output),
          tracks = ['a', 'b', 'c', 'd'].map(fixture.external).toList();
      try {
        await audio.playTrack(tracks.first, list: tracks);
        await tick();
        expect(cache.prepared, ['b']);
        cache.pending['b']!.complete();
        await tick();
        expect(cache.prepared, ['b', 'c']);
        expect(api.requests.where((r) => r.contains('/d/')), isEmpty);
        audio.replaceQueue([tracks.first, tracks.last]);
        await tick();
        expect(cache.cancelled, contains('c'));
        expect(cache.prepared, ['b', 'c', 'd']);
        cache.pending['c']!.complete();
        await tick();
        expect(audio.current?.id, 'a');
        expect(output.active, true);
        expect(output.loaded.length, 1);
        expect(cache.prepared.where((id) => id == 'c').length, 1);
      } finally {
        cache.finish();
        audio.prepareNext = false;
        await audio.release();
        cache.dispose();
        api.diagnostics.dispose();
        api.dio.close(force: true);
      }
    },
  );
  test(
    'manual save adopts prepared download and survives speculative cancellation',
    () async {
      final root = await Directory.systemTemp.createTemp('prefetch26-manual-'),
          api = ControlledDownload(),
          cache = MusicCache(api)..directory = root;
      final track = WaveTrack({
        ...fixture.external('pin').json,
        'playback': {'kind': 'audio', 'offline': true},
      });
      try {
        final prepared = cache.prefetch(track);
        await api.ready.future;
        final manual = cache.save(track, manual: true);
        cache.cancelPrefetch(track.id);
        expect(api.cancellation!.isCancelled, false);
        api.finish.complete();
        await Future.wait([prepared, manual]);
        expect(api.downloads, 1);
        expect(cache.contains(track.id), true);
        expect(object(cache.entries[track.id])['manual'], true);
      } finally {
        await cache.clear(includingDownloads: true);
        cache.dispose();
        api.diagnostics.dispose();
        api.dio.close(force: true);
        await root.delete(recursive: true);
      }
    },
  );
  test(
    'obsolete speculative audio is canceled and never committed to offline storage',
    () async {
      final root = await Directory.systemTemp.createTemp('prefetch26-cancel-'),
          api = ControlledDownload(),
          cache = MusicCache(api)..directory = root;
      final track = WaveTrack({
        ...fixture.external('obsolete').json,
        'playback': {'kind': 'audio', 'offline': true},
      });
      try {
        final prepared = cache.prefetch(track);
        await api.ready.future;
        cache.cancelPrefetch(track.id);
        await prepared;
        expect(api.cancellation!.isCancelled, true);
        expect(cache.contains(track.id), false);
        expect(
          root.listSync().where(
            (e) => e.path.endsWith('.part') || e.path.endsWith('.audio'),
          ),
          isEmpty,
        );
      } finally {
        await cache.clear(includingDownloads: true);
        cache.dispose();
        api.diagnostics.dispose();
        api.dio.close(force: true);
        await root.delete(recursive: true);
      }
    },
  );
}
