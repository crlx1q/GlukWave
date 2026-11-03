import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glukwave/core/api.dart';
import 'package:glukwave/core/controller.dart';
import 'package:glukwave/core/models.dart';
import 'package:glukwave/core/native_auth_polling.dart';
import 'package:glukwave/services/audio.dart';
import 'package:glukwave/services/cache.dart';

// This one test exercises a real loopback server. Widget binding's default
// HttpClient deliberately returns400 for every URL, including localhost.
class _LoopbackHttpOverrides extends HttpOverrides {}

class ControllerAuthApi extends WaveApi {
  final logins = <Completer<Json>>[];
  final browser = Completer<Json>();
  ControllerAuthApi() : super('http://127.0.0.1:4012');
  @override
  Future<Json> call(
    String path, {
    String method = 'GET',
    dynamic data,
    Json? query,
  }) {
    if (path == '/api/auth/native') return browser.future;
    if (path == '/api/auth/login') {
      final result = Completer<Json>();
      logins.add(result);
      return result.future;
    }
    return Future.value({});
  }
}

class ControllerAuthFixture extends WaveController {
  final accepted = <String>[];
  final opened = <String>[];
  ControllerAuthFixture(ControllerAuthApi api) : this._(api, MusicCache(api));
  ControllerAuthFixture._(ControllerAuthApi api, MusicCache cache)
    : super(api, cache, WaveAudioHandler(api, cache));
  @override
  Future<void> acceptSession(Json data) async =>
      accepted.add(data['token'] as String);
  @override
  Future<void> openUrl(String value) async => opened.add(value);
}

Future<void> closeAuthFixture(ControllerAuthFixture c) async {
  c.dispose();
  await c.audio.release();
  c.api.dio.close(force: true);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.ryanheise.audio_session'),
          (_) async => null,
        ),
  );
  test(
    'An older credential response cannot replace a newer login on the same server',
    () async {
      final api = ControllerAuthApi(), c = ControllerAuthFixture(api);
      try {
        final old = c.authenticate('old-user', 'never-sent-to-a-network');
        final oldCancelled = expectLater(
          old,
          throwsA(
            isA<WaveException>().having(
              (e) => e.code,
              'code',
              'AUTH_CANCELLED',
            ),
          ),
        );
        final latest = c.authenticate('new-user', 'never-sent-to-a-network');
        api.logins.first.complete({'token': 'old-session'});
        await oldCancelled;
        api.logins.last.complete({'token': 'current-session'});
        await latest;
        expect(c.accepted, ['current-session']);
      } finally {
        await closeAuthFixture(c);
      }
    },
  );
  test(
    'Cancelling during challenge creation cannot reopen the browser afterward',
    () async {
      final api = ControllerAuthApi(), c = ControllerAuthFixture(api);
      try {
        final pending = c.browserLogin(method: 'email');
        final cancelled = expectLater(
          pending,
          throwsA(
            isA<WaveException>().having(
              (e) => e.code,
              'code',
              'AUTH_CANCELLED',
            ),
          ),
        );
        c.cancelAuth = true;
        api.browser.complete({
          'id': 'old-challenge',
          'secret': 'isolated-test-secret',
          'url': 'https://example.invalid/never-opened',
          'expiresAt': DateTime.now()
              .add(const Duration(minutes: 1))
              .millisecondsSinceEpoch,
        });
        await cancelled;
        expect(c.opened, isEmpty);
        expect(c.accepted, isEmpty);
      } finally {
        await closeAuthFixture(c);
      }
    },
  );
  test(
    'One browser approval survives temporary failures without another approval',
    () async {
      var now = DateTime.utc(2026), reads = 0;
      final delays = <Duration>[];
      final flow = NativeAuthPolling(
        now: () => now,
        delay: (pause) async {
          delays.add(pause);
          now = now.add(pause);
        },
      );
      final result = await flow.wait(
        expires: now.add(const Duration(minutes: 2)),
        current: () => true,
        read: (cancel, timeout) async {
          expect(timeout, lessThanOrEqualTo(const Duration(seconds: 10)));
          reads++;
          if (reads == 1) {
            throw const WaveException('Connection lost', 'network');
          }
          if (reads == 2) {
            throw const WaveException('Gateway unavailable', 'HTTP', 503);
          }
          if (reads == 3) return {'status': 'pending'};
          return {'status': 'approved', 'token': 'same-claim-session'};
        },
      );
      expect(result['token'], 'same-claim-session');
      expect(reads, 4);
      expect(delays, [
        const Duration(seconds: 3),
        const Duration(seconds: 5),
        const Duration(seconds: 2),
      ]);
    },
  );

  test(
    'Invalid secret or rejected approval is terminal, never retried',
    () async {
      var reads = 0;
      final flow = NativeAuthPolling(delay: (_) async => fail('No retry'));
      await expectLater(
        flow.wait(
          expires: DateTime.now().add(const Duration(minutes: 1)),
          current: () => true,
          read: (_, __) async {
            reads++;
            throw const WaveException(
              'Unknown challenge',
              'CHALLENGE_NOT_FOUND',
              404,
            );
          },
        ),
        throwsA(isA<WaveException>().having((e) => e.status, 'status', 404)),
      );
      expect(reads, 1);
    },
  );

  test(
    'Transient retries are bounded by the actual challenge expiry',
    () async {
      var now = DateTime.utc(2026), reads = 0;
      final expires = now.add(const Duration(seconds: 6));
      final flow = NativeAuthPolling(
        now: () => now,
        delay: (pause) async => now = now.add(pause),
      );
      await expectLater(
        flow.wait(
          expires: expires,
          current: () => true,
          read: (_, timeout) async {
            reads++;
            expect(timeout, lessThanOrEqualTo(expires.difference(now)));
            throw const WaveException('Offline', 'network');
          },
        ),
        throwsA(
          isA<WaveException>().having(
            (e) => e.code,
            'code',
            'CHALLENGE_EXPIRED',
          ),
        ),
      );
      expect(reads, 2);
      expect(now, expires);
    },
  );

  test(
    'Cancellation aborts an in-flight read and cannot return its approval',
    () async {
      final entered = Completer<CancelToken>();
      final flow = NativeAuthPolling();
      final pending = flow.wait(
        expires: DateTime.now().add(const Duration(minutes: 1)),
        current: () => true,
        read: (cancel, _) async {
          entered.complete(cancel);
          await cancel.whenCancel;
          throw const WaveException('Cancelled', 'network');
        },
      );
      final expectation = expectLater(
        pending,
        throwsA(
          isA<WaveException>().having((e) => e.code, 'code', 'AUTH_CANCELLED'),
        ),
      );
      final cancellation = await entered.future;
      flow.cancel();
      await expectation;
      expect(cancellation.isCancelled, true);
    },
  );

  test(
    'A response from an old account/flow is discarded before accepting a session',
    () async {
      final response = Completer<Json>();
      var current = true;
      final flow = NativeAuthPolling();
      final pending = flow.wait(
        expires: DateTime.now().add(const Duration(minutes: 1)),
        current: () => current,
        read: (_, __) => response.future,
      );
      final expectation = expectLater(
        pending,
        throwsA(
          isA<WaveException>().having((e) => e.code, 'code', 'AUTH_CANCELLED'),
        ),
      );
      current = false;
      response.complete({'status': 'approved', 'token': 'old-account'});
      await expectation;
    },
  );

  test(
    'Real HTTP status reads retain native identity and the same recovery claim',
    () => HttpOverrides.runWithHttpOverrides(() async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requests = <HttpRequest>[];
      final api = WaveApi('http://127.0.0.1:${server.port}')
        ..deviceId = 'android-installation'
        ..surfaceId = 'android-surface'
        ..clientKind = 'android';
      const claim = '550e8400-e29b-41d4-a716-446655440000';
      final subscription = server.listen((request) async {
        requests.add(request);
        request.response.headers.contentType = ContentType.json;
        if (requests.length == 1) {
          request.response.statusCode = 503;
          request.response.write(
            '{"error":{"code":"TEMPORARY","message":"Retry status"}}',
          );
        } else {
          request.response.write(
            '{"status":"approved","token":"one-confirmed-session"}',
          );
        }
        await request.response.close();
      });
      var now = DateTime.now();
      try {
        final result =
            await NativeAuthPolling(
              now: () => now,
              delay: (pause) async {
                now = now.add(pause);
              },
            ).wait(
              expires: now.add(const Duration(minutes: 1)),
              current: () => true,
              read: (cancellation, timeout) => api.pollNativeAuth(
                '/api/auth/native/challenge',
                secret: 'one-challenge-secret',
                claim: claim,
                cancellation: cancellation,
                timeout: timeout,
              ),
            );
        expect(result['token'], 'one-confirmed-session');
        expect(requests, hasLength(2));
        for (final request in requests) {
          expect(request.method, 'GET');
          expect(request.uri.queryParameters['secret'], 'one-challenge-secret');
          expect(request.headers.value('X-GlukWave-Auth-Claim'), claim);
          expect(request.headers.value('X-GlukWave-Client'), 'native');
          expect(
            request.headers.value('X-GlukWave-Device'),
            'android-installation',
          );
          expect(
            request.headers.value('X-GlukWave-Surface'),
            'android-surface',
          );
          expect(request.headers.value('X-GlukWave-Kind'), 'android');
        }
      } finally {
        api.diagnostics.dispose();
        api.dio.close(force: true);
        await subscription.cancel();
        await server.close(force: true);
      }
    }, _LoopbackHttpOverrides()),
  );
}
