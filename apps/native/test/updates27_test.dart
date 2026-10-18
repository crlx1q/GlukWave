import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:glukwave/core/api.dart';
import 'package:glukwave/services/app_updates.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'version ordering includes native build and semantic prerelease precedence',
    () {
      for (final pair in [
        ['1.2.1', '1.2.0'],
        ['1.0.0+27', '1.0.0+26'],
        ['2.0.0', '1.99.99'],
        ['1.0.0', '1.0.0-rc.9'],
        ['1.0.0-rc.10', '1.0.0-rc.9'],
      ]) {
        expect(compareAppVersions(pair[0], pair[1]), greaterThan(0));
        expect(compareAppVersions(pair[1], pair[0]), lessThan(0));
      }
      expect(compareAppVersions('1.2.0', '1.2.0+0'), 0);
      expect(
        () => compareAppVersions('../installer', '1.0.0'),
        throwsFormatException,
      );
    },
  );
  test(
    'updates coalesce, check once per day, verify the actual package and never install corrupt bytes',
    () async {
      HttpOverrides.global = null;
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance(),
          directory = await Directory.systemTemp.createTemp('gw27-updates-');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final bytes = List<int>.generate(2048, (i) => i % 251);
      final hash = (await Sha256().hash(
        bytes,
      )).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      var checks = 0, downloads = 0, installs = 0, corrupt = false;
      server.listen((request) async {
        if (request.uri.path == '/api/releases') {
          checks++;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'releases': [
                {
                  'platform': 'windows',
                  'version': '1.0.0+27',
                  'format': 'installer',
                  'available': true,
                  'bytes': bytes.length,
                  'sha256': hash,
                  'url': '/api/downloads/windows',
                },
              ],
            }),
          );
        } else {
          downloads++;
          request.response.headers.set('X-Content-SHA256', hash);
          request.response.add(corrupt ? List.filled(bytes.length, 0) : bytes);
        }
        await request.response.close();
      });
      var now = DateTime(2026, 10, 18);
      final api = WaveApi('http://127.0.0.1:${server.port}');
      AppUpdater make() => AppUpdater(
        api,
        currentVersion: '1.0.0+26',
        platform: 'windows',
        clock: () => now,
        installer: (file, platform) async {
          expect(await file.readAsBytes(), bytes);
          installs++;
        },
      );
      final first = make();
      await first.initialize(preferences, directory);
      try {
        await Future.wait([first.check(), first.check()]);
        expect(checks, 1);
        expect(first.visible, isTrue);
        final second = make();
        await second.initialize(preferences, directory);
        await second.check();
        expect(checks, 1);
        expect(second.release?.version, '1.0.0+27');
        second.dispose();
        corrupt = true;
        await first.download();
        expect(first.phase, UpdatePhase.error);
        await first.install();
        expect(installs, 0);
        corrupt = false;
        await first.download();
        expect(first.phase, UpdatePhase.ready);
        expect(downloads, 2);
        await first.install();
        expect(installs, 1);
        now = now.add(const Duration(days: 1));
        await first.check();
        expect(checks, 2);
      } finally {
        first.dispose();
        api.diagnostics.dispose();
        await server.close(force: true);
        await directory.delete(recursive: true);
      }
    },
  );
  test(
    'manifest rejects cross-origin URLs, wrong platform and portable ZIP installers',
    () {
      final row = {
        'platform': 'windows',
        'version': '1.0.0+27',
        'format': 'installer',
        'available': true,
        'bytes': 2048,
        'sha256': 'a' * 64,
        'url': '/api/downloads/windows',
      };
      expect(AppRelease.parse(row, 'windows'), isNotNull);
      for (final patch in [
        {'url': 'https://evil.test/app.exe'},
        {'format': 'portable'},
        {'bytes': 1024 * 1024 * 1024},
        {'sha256': 'invalid'},
        {'platform': 'android'},
      ]) {
        expect(AppRelease.parse({...row, ...patch}, 'windows'), isNull);
      }
    },
  );
  test(
    'cancelling an in-flight update removes the partial and origin changes cannot install it',
    () async {
      HttpOverrides.global = null;
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final directory = await Directory.systemTemp.createTemp(
        'gw27-update-cancel-',
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final bytes = List<int>.generate(4096, (i) => i % 251);
      final hash = (await Sha256().hash(
        bytes,
      )).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      final started = Completer<void>(), releaseBody = Completer<void>();
      var firstBody = true, installs = 0;
      server.listen((request) async {
        try {
          if (request.uri.path == '/api/releases') {
            request.response.headers.contentType = ContentType.json;
            request.response.write(
              jsonEncode({
                'releases': [
                  {
                    'platform': 'windows',
                    'version': '1.0.0+27',
                    'format': 'installer',
                    'available': true,
                    'bytes': bytes.length,
                    'sha256': hash,
                    'url': '/api/downloads/windows',
                  },
                ],
              }),
            );
          } else if (firstBody) {
            firstBody = false;
            request.response.add(bytes.sublist(0, 1024));
            await request.response.flush();
            started.complete();
            await releaseBody.future;
            request.response.add(bytes.sublist(1024));
          } else {
            request.response.add(bytes);
          }
          await request.response.close();
        } catch (_) {
          /* The client deliberately interrupts the first response. */
        }
      });
      final api = WaveApi('http://127.0.0.1:${server.port}');
      final updater = AppUpdater(
        api,
        currentVersion: '1.0.0+26',
        platform: 'windows',
        installer: (_, platform) async {
          installs++;
        },
      );
      try {
        await updater.initialize(preferences, directory);
        await updater.check();
        final pending = updater.download();
        await started.future;
        updater.cancel();
        releaseBody.complete();
        await pending;
        expect(updater.phase, UpdatePhase.available);
        expect(
          await directory
              .list(recursive: true)
              .where((file) => file.path.endsWith('.partial'))
              .isEmpty,
          isTrue,
        );
        await updater.download();
        expect(updater.phase, UpdatePhase.ready);
        api.server = 'https://other.test';
        expect(updater.visible, isFalse);
        await updater.install();
        expect(installs, 0);
      } finally {
        if (!releaseBody.isCompleted) releaseBody.complete();
        updater.dispose();
        api.diagnostics.dispose();
        await server.close(force: true);
        await directory.delete(recursive: true);
      }
    },
  );
}
