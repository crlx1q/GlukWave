import '../l10n/wave_localizations.dart';
import 'dart:async';
import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../core/api.dart';

class WavePush {
  final WaveApi api;
  StreamSubscription<String>? _tokens;
  WavePush(this.api);
  static const key = String.fromEnvironment('FIREBASE_API_KEY');
  static const appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const project = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const sender = String.fromEnvironment('FIREBASE_SENDER_ID');
  bool get configured =>
      (Platform.isAndroid || Platform.isIOS) &&
      key.isNotEmpty &&
      appId.isNotEmpty &&
      project.isNotEmpty &&
      sender.isNotEmpty;
  Future<void> enable() async {
    if (!configured) {
      throw WaveException(wt('native.bcec42f75c'));
    }
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: key,
          appId: appId,
          projectId: project,
          messagingSenderId: sender,
          iosBundleId: 'tech.gluk.glukwave',
        ),
      );
    }
    final authorization = await FirebaseMessaging.instance.requestPermission();
    if (authorization.authorizationStatus == AuthorizationStatus.denied) {
      throw WaveException(wt('native.3e2347f6a4'));
    }
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null) {
      throw WaveException(wt('native.f2c19e16b8'));
    }
    await register(token);
    _tokens ??= FirebaseMessaging.instance.onTokenRefresh.listen(
      (value) => unawaited(register(value).catchError((_) {})),
    );
  }

  Future<void> register(String token) async {
    await api.call(
      '/api/push/device',
      method: 'POST',
      data: {
        'token': token,
        'platform': Platform.isAndroid ? 'android' : 'ios',
      },
    );
  }

  Future<void> disable() async {
    await _tokens?.cancel();
    _tokens = null;
    if (Firebase.apps.isNotEmpty) {
      await FirebaseMessaging.instance.deleteToken();
    }
  }
}
