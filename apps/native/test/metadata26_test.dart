import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:glukwave/core/api.dart';
import 'package:glukwave/core/models.dart';
import 'package:glukwave/core/parity.dart';
import 'package:glukwave/services/metadata_cache.dart';
import 'package:glukwave/services/diagnostics.dart';

class MetadataApi extends WaveApi {
  int calls = 0;
  Completer<Json>? response;
  WaveException? failure;
  MetadataApi() : super('http://127.0.0.1:4000');
  @override
  Future<Json> call(
    String path, {
    String method = 'GET',
    dynamic data,
    Json? query,
  }) async {
    calls++;
    if (failure != null) throw failure!;
    return response?.future ??
        {
          'tracks': [
            {'id': 'own'},
          ],
        };
  }
}

class DiscoveryApi extends MetadataApi {
  final friends = Completer<Json>();
  @override
  Future<Json> call(
    String path, {
    String method = 'GET',
    dynamic data,
    Json? query,
  }) async {
    if (path == '/api/friends') return friends.future;
    return path == '/api/recommendations'
        ? {
            'tracks': [
              {'id': 'ready', 'title': 'Already ready'},
            ],
          }
        : {};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'ready home recommendations do not wait for a stalled optional friends service',
    () async {
      final api = DiscoveryApi(), parity = WaveParity(api);
      try {
        final pending = parity.load();
        await Future<void>.delayed(Duration.zero);
        expect(parity.tracks.single.id, 'ready');
        expect(parity.loading, false);
        api.friends.complete({'friends': []});
        await pending;
      } finally {
        parity.dispose();
        api.diagnostics.dispose();
        api.dio.close(force: true);
      }
    },
  );
  late Directory root;
  late MetadataApi api;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('metadata26-');
    api = MetadataApi()..token = 'one';
    await api.openMetadata(root, 'owner');
  });
  tearDown(() async {
    await api.metadata.flush();
    api.diagnostics.dispose();
    api.dio.close(force: true);
    await root.delete(recursive: true);
  });
  test(
    'coalesced read restores immediately after process restart, with canonical query keys',
    () async {
      api.response = Completer<Json>();
      final first = api.cachedCall(
        '/api/search',
        query: {'q': 'own', 'source': 'all'},
      );
      final second = api.cachedCall(
        '/api/search',
        query: {'source': 'all', 'q': 'own'},
      );
      expect(api.calls, 1);
      api.response!.complete({
        'tracks': [
          {'id': 'own'},
        ],
      });
      await Future.wait([first, second]);
      await api.metadata.flush();
      final restored = MetadataCache();
      await restored.open(root, 'owner');
      expect(
        object(
          (restored.peek(
                    MetadataCache.key('/api/search', {
                      'q': 'own',
                      'source': 'all',
                    }),
                  )!['tracks']
                  as List)
              .first,
        )['id'],
        'own',
      );
      await restored.open(root, 'other');
      expect(
        restored.peek(
          MetadataCache.key('/api/search', {'q': 'own', 'source': 'all'}),
        ),
        isNull,
      );
    },
  );
  test(
    'temporary outage uses saved data, denied access evicts both memory and disk',
    () async {
      await api.cachedCall('/api/home');
      api.failure = const WaveException('offline', 'NETWORK');
      expect(
        (await api.cachedCall('/api/home', force: true))['tracks'],
        isNotEmpty,
      );
      api.failure = const WaveException('denied', 'AUTH_REQUIRED', 401);
      await expectLater(
        api.cachedCall('/api/home', force: true),
        throwsA(isA<WaveException>()),
      );
      expect(api.peekMetadata('/api/home'), isNull);
      await api.metadata.flush();
      final restored = MetadataCache();
      await restored.open(root, 'owner');
      expect(restored.peek(MetadataCache.key('/api/home')), isNull);
    },
  );
  test(
    'late response from previous account is rejected and never enters new snapshot',
    () async {
      api.response = Completer<Json>();
      final pending = api.cachedCall('/api/home');
      final rejected = expectLater(
        pending,
        throwsA(
          isA<WaveException>().having((e) => e.code, 'code', 'STALE_REQUEST'),
        ),
      );
      api.token = 'two';
      await api.openMetadata(root, 'other');
      api.response!.complete({'private': 'previous account'});
      await rejected;
      expect(api.peekMetadata('/api/home'), isNull);
      await api.metadata.flush();
      final restored = MetadataCache();
      await restored.open(root, 'other');
      expect(restored.peek(MetadataCache.key('/api/home')), isNull);
    },
  );
  test(
    'snapshot quota stays bounded and corrupt optional metadata cannot block opening',
    () async {
      for (var i = 0; i < 55; i++) {
        api.metadata.put('key$i', {'text': 'a' * 60000});
      }
      await api.metadata.flush();
      final files = await root
          .list()
          .where((f) => f.path.endsWith('.json'))
          .toList();
      expect(
        await (files.single as File).length(),
        lessThanOrEqualTo(MetadataCache.maxBytes),
      );
      await (files.single as File).writeAsString('{broken');
      await api.openMetadata(root, 'owner');
      expect(api.peekMetadata('/api/home'), isNull);
    },
  );
  test(
    'local exception stack keeps useful frame with credentials and user paths scrubbed',
    () async {
      final log = WaveDiagnostics(() => api.server, () => {});
      await log.enableLocalLog(root);
      log.record(
        'failure',
        kind: 'framework',
        stack: StackTrace.fromString(
          'frame C:/Users/private/app.dart:12 token=secret Bearer private-value',
        ),
      );
      await log.flushLocal();
      final text = await File(
        '${root.path}/logs/glukwave.jsonl',
      ).readAsString();
      expect(text, contains('app.dart:12'));
      expect(text, contains('[redacted]'));
      expect(text, isNot(contains('private-value')));
      expect(text, isNot(contains('C:/Users/private')));
      expect(jsonDecode(text.trim().split('\n').last)['kind'], 'framework');
      log.dispose();
    },
  );
}
