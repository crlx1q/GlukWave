import 'l10n/wave_localizations.dart';
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'core/api.dart';
import 'core/controller.dart';
import 'services/audio.dart';
import 'services/cache.dart';
import 'services/windows_equalizer.dart';
import 'ui/app.dart';
import 'ui/auth_visuals.dart';
import 'ui/widgets.dart';

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const WaveBootstrapApp());
  WaveApi? startupApi;
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString('assets/licenses/Nunito-OFL.txt');
    yield LicenseEntryWithLineBreaks(['Nunito'], text);
    final manrope = await rootBundle.loadString(
      'assets/licenses/Manrope-OFL.txt',
    );
    yield LicenseEntryWithLineBreaks(['Manrope'], manrope);
    final adapter = await rootBundle.loadString('assets/licenses/just_audio_media_kit-UNLICENSE.txt');
    yield LicenseEntryWithLineBreaks(['just_audio_media_kit adapter'], adapter);
  });
  try {
    if (Platform.isWindows) {
      JustAudioMediaKit.ensureInitialized(windows: true, linux: false);
      JustAudioMediaKit.title = 'GlukWave';
      WaveWindowsAudio.register();
    }
    const server = String.fromEnvironment('GLUKWAVE_SERVER');
    final api = WaveApi(
      server.isNotEmpty
          ? server
          : !kDebugMode
          ? 'https://wave.gluk.tech'
          : Platform.isAndroid
          ? 'http://10.0.2.2:4000'
          : 'http://127.0.0.1:4000',
    );
    startupApi = api;
    FlutterError.onError = (details) {
      api.diagnostics.report(
        details.exception,
        kind: 'framework',
        stack: details.stack,
      );
      FlutterError.presentError(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      api.diagnostics.report(error, kind: 'runtime', stack: stack);
      return true;
    };
    final cache = MusicCache(api);
    final handler = await AudioService.init<WaveAudioHandler>(
      builder: () => WaveAudioHandler(api, cache),
      config: AudioServiceConfig(
        androidNotificationChannelId: 'tech.gluk.glukwave.audio',
        androidNotificationChannelName: wt('native.5de203e8f1'),
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
        androidNotificationIcon: 'drawable/ic_notification',
      ),
    );
    final controller = WaveController(
      api,
      cache,
      handler,
      startMinimized: arguments.contains('--start-minimized'),
    );
    runApp(GlukWaveApp(controller: controller));
    await controller.initialize();
  } catch (error, trace) {
    startupApi?.diagnostics.report(
      error,
      kind: 'background',
      stack: trace,
      code: 'STARTUP',
    );
    debugPrint('GlukWave startup: $error\n$trace');
    runApp(
      MaterialApp(
        theme: waveTheme,
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.graphic_eq_rounded, size: 64, color: accent),
                  const SizedBox(height: 20),
                  Text(
                    wt('native.76427de2d8'),
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  Text(wt('native.85e221a3e3'), textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
