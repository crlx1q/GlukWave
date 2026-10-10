import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glukwave/services/home_widgets.dart';
import 'package:glukwave/l10n/home_widget_strings.dart';
import 'package:glukwave/l10n/wave_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(HomeWidgetBridge.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'cold action is consumed once; unknown commands and foreign arguments do not dispatch',
    () async {
      final commands = <String>[];
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => call.method == 'initialize'
            ? {
                'action': {'command': 'wave', 'scope': 'account-a'},
                'grant': 'private-native-grant',
              }
            : null,
      );
      final bridge = HomeWidgetBridge(
        enabled: true,
        onCommand: (command, scope) async {
          commands.add('$scope:$command');
        },
      );
      await bridge.initialize();
      expect(bridge.grant, 'private-native-grant');
      expect(commands, ['account-a:wave']);
      Future<void> inbound(Object? argument) async {
        await messenger.handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('action', argument),
          ),
          (_) {},
        );
      }

      await inbound({'command': 'deleteAccount', 'scope': 'account-a'});
      await inbound({'command': 'like', 'scope': 45});
      await inbound({'command': 'next', 'scope': 'account-a'});
      expect(commands, ['account-a:wave', 'account-a:next']);
      bridge.dispose();
    },
  );

  test(
    'progress/heartbeat notifications with identical state do not rewrite launcher',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      final bridge = HomeWidgetBridge(
        enabled: true,
        onCommand: (_, __) async {},
      );
      await bridge.initialize();
      final state = <String, Object?>{
        'title': 'Music',
        'playing': true,
        'scope': 'user-a',
      };
      for (var i = 0; i < 60; i++) {
        bridge.update(state);
      }
      await Future<void>.delayed(Duration.zero);
      expect(calls.where((c) => c.method == 'update').length, 1);
      bridge.update({...state, 'playing': false});
      await Future<void>.delayed(Duration.zero);
      expect(calls.where((c) => c.method == 'update').length, 2);
      bridge.dispose();
    },
  );

  test(
    'slow platform write coalesces to newest track and clear drops queued metadata',
    () async {
      final writes = <Object?>[];
      final slow = Completer<void>();
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'update') {
          writes.add(call.arguments);
          if (writes.length == 1) await slow.future;
          return 'write-grant-${writes.length}';
        }
        if (call.method == 'clear') return 'signed-out-grant';
        return null;
      });
      final bridge = HomeWidgetBridge(
        enabled: true,
        onCommand: (_, __) async {},
      );
      await bridge.initialize();
      bridge.update({'title': 'first'});
      await Future<void>.delayed(Duration.zero);
      bridge.update({'title': 'second'});
      bridge.update({'title': 'third'});
      await bridge.clear();
      slow.complete();
      await Future<void>.delayed(Duration.zero);
      expect(bridge.grant, 'signed-out-grant');
      expect(writes, [
        {'title': 'first'},
      ]);
      bridge.update({'title': 'signed out'});
      await Future<void>.delayed(Duration.zero);
      expect(writes.last, {'title': 'signed out'});
      bridge.dispose();
      bridge.update({'title': 'disposed'});
      await Future<void>.delayed(Duration.zero);
      expect(writes.length, 2);
    },
  );

  test('pin only supports the two real provider variants', () async {
    final pinned = <Object?>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'pin') {
        pinned.add(call.arguments);
        return true;
      }
      return null;
    });
    final bridge = HomeWidgetBridge(enabled: true, onCommand: (_, __) async {});
    expect(await bridge.pin('player'), true);
    expect(await bridge.pin('wave'), true);
    expect(await bridge.pin('unknown'), false);
    expect(pinned, [
      {'kind': 'player'},
      {'kind': 'wave'},
    ]);
    bridge.dispose();
  });

  test(
    'all six locales ship every widget instruction and accessibility label',
    () {
      for (final locale in ['en', 'ru', 'kk', 'uk', 'de', 'es']) {
        WaveStrings.current = WaveStrings(locale);
        for (final key in homeWidgetStrings.keys) {
          expect(homeWidgetText(key), isNotEmpty);
          expect(homeWidgetText(key), isNot(key));
        }
      }
      WaveStrings.current = const WaveStrings('en');
    },
  );
}
