import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glukwave/core/controller.dart';
import 'package:glukwave/core/models.dart';
import 'package:glukwave/services/audio.dart';
import 'package:glukwave/services/cache.dart';
import 'app_layout_test.dart' show LayoutApi;

class WidgetApi extends LayoutApi {
  Completer<Json>? recommendation;
  @override
  Future<Json> call(
    String path, {
    String method = 'GET',
    dynamic data,
    Json? query,
  }) async {
    if (path == '/api/recommendations') {
      return recommendation?.future ??
          {
            'tracks': [widgetTrack.json],
          };
    }
    return {};
  }
}

final widgetTrack = WaveTrack({
  'id': 'widget-track',
  'title': 'Real recommendation',
  'artist': 'Test',
  'source': 'local',
  'playback': {'kind': 'audio'},
});

class WidgetController extends WaveController {
  final commands = <String>[];
  WidgetController(super.api, super.cache, super.audio);
  @override
  Future<void> transport(String command, [Json data = const {}]) async {
    commands.add(command);
  }

  @override
  Future<void> like(WaveTrack track) async {
    commands.add('like:${track.id}');
  }

  @override
  Future<void> play(WaveTrack track, {List<WaveTrack>? list}) async {
    commands.add('track:${track.id}');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.ryanheise.audio_session'),
          (_) async => null,
        ),
  );
  Future<WidgetController> setup() async {
    final api = WidgetApi(), cache = MusicCache(WidgetApi());
    final audio = WaveAudioHandler(api, cache)..current = widgetTrack;
    final c = WidgetController(api, cache, audio)
      ..user = WaveUser({'id': 'account-a', 'username': 'owner'});
    audio.onWidgetCommand = c.widgetCommand;
    audio.widgetGrant = 'private-widget-grant';
    return c;
  }

  Future<void> cleanup(WidgetController c) async {
    c.dispose();
    await c.audio.release();
    c.api.dio.close(force: true);
  }

  test(
    'media-session widget custom actions use existing account transport and like handlers',
    () async {
      final c = await setup();
      await c.audio.customAction('glukwave.widget', {
        'command': 'next',
        'scope': c.namespace,
        'grant': 'foreign-grant',
      });
      expect(c.commands, isEmpty);
      await c.audio.customAction('glukwave.widget', {
        'command': 'toggle',
        'scope': c.namespace,
        'grant': 'private-widget-grant',
      });
      await c.audio.customAction('glukwave.widget', {
        'command': 'next',
        'scope': c.namespace,
        'grant': 'private-widget-grant',
      });
      await c.audio.customAction('glukwave.widget', {
        'command': 'like',
        'scope': c.namespace,
        'grant': 'private-widget-grant',
      });
      expect(c.commands, ['play', 'next', 'like:widget-track']);
      await cleanup(c);
    },
  );
  test(
    'signed-out, stale account and unknown commands never reach playback',
    () async {
      final c = await setup();
      await c.widgetCommand('next', 'other-account');
      await c.widgetCommand('delete', c.namespace);
      c.user = null;
      await c.widgetCommand('next', c.namespace);
      expect(c.commands, isEmpty);
      await cleanup(c);
    },
  );
  test(
    'room listener cannot skip/start Wave; jam listener may toggle existing output',
    () async {
      final c = await setup();
      c.room = {'id': 'room', 'type': 'jam', 'ownerId': 'other-user'};
      await c.widgetCommand('next', c.namespace);
      await c.widgetCommand('wave', c.namespace);
      await c.widgetCommand('toggle', c.namespace);
      expect(c.commands, ['play']);
      await cleanup(c);
    },
  );
  test(
    'Wave uses backend recommendations; a response after account switch cannot start music',
    () async {
      final c = await setup();
      await c.widgetCommand('wave', c.namespace);
      expect(c.commands, ['track:widget-track']);
      final api = c.api as WidgetApi;
      api.recommendation = Completer<Json>();
      final pending = c.startWave();
      c.user = WaveUser({'id': 'account-b', 'username': 'other'});
      api.recommendation!.complete({
        'tracks': [widgetTrack.json],
      });
      await pending;
      expect(c.commands, ['track:widget-track']);
      await cleanup(c);
    },
  );
}
