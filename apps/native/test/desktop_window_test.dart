import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'native_auth_desktop_test.dart' as fixtures;
import 'package:glukwave/services/desktop.dart';

class ClickDispatch extends DesktopShell {
  int mainClicks = 0, quickClicks = 0;
  ClickDispatch(super.audio);
  @override
  Future<void> toggleMain() async {
    mainClicks++;
  }

  @override
  Future<void> toggleQuick() async {
    quickClicks++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Tray click modes preserve full and mini bounds and restore frame',
    (tester) async {
      final c = (await tester.runAsync(fixtures.setup))!;
      final native = <MethodCall>[];
      var visible = true, maximized = false, minimized = false;
      var bounds = <String, double>{
        'x': 70,
        'y': 80,
        'width': 1280,
        'height': 860,
      };
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('window_manager'),
        (call) async {
          native.add(call);
          switch (call.method) {
            case 'isVisible':
              return visible;
            case 'isMaximized':
              return maximized;
            case 'isMinimized':
              return minimized;
            case 'getBounds':
              return {...bounds};
            case 'setBounds':
              final values = Map<String, dynamic>.from(call.arguments as Map);
              for (final key in bounds.keys) {
                if (values[key] is num) {
                  bounds[key] = (values[key] as num).toDouble();
                }
              }
            case 'show':
              visible = true;
            case 'hide':
              visible = false;
            case 'maximize':
              maximized = true;
            case 'unmaximize':
              maximized = false;
            case 'restore':
              minimized = false;
          }
          return true;
        },
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('tray_manager'),
        (call) async => call.method == 'getBounds'
            ? {'x': 900.0, 'y': 740.0, 'width': 24.0, 'height': 24.0}
            : true,
      );
      c.desktop.initialized = true;
      await tester.runAsync(c.desktop.toggleMini);
      expect(c.desktop.mini, isTrue);
      expect(
        native.where((call) => call.method == 'setAsFrameless'),
        isNotEmpty,
      );
      expect(
        native.lastWhere((call) => call.method == 'setOpacity').arguments,
        {'opacity': .94},
      );
      final miniBounds = {...bounds};
      await tester.runAsync(c.desktop.toggleQuick);
      expect(c.desktop.quick, isTrue);
      expect(c.desktop.mini, isFalse);
      await tester.runAsync(c.desktop.dismissQuick);
      expect(c.desktop.mini, isTrue);
      expect(bounds, miniBounds);
      await tester.runAsync(c.desktop.showMain);
      expect(c.desktop.mini, isFalse);
      expect(c.desktop.quick, isFalse);
      expect(bounds, {'x': 70.0, 'y': 80.0, 'width': 1280.0, 'height': 860.0});
      expect(
        native.lastWhere((call) => call.method == 'setTitleBarStyle').arguments,
        {'titleBarStyle': 'normal', 'windowButtonVisibility': true},
      );

      // Windows reports a sentinel position for a minimized window. It must
      // never replace the remembered normal bounds or reveal the main app.
      minimized = true;
      bounds = {'x': -32000, 'y': -32000, 'width': 1280, 'height': 860};
      await tester.runAsync(c.desktop.toggleQuick);
      expect(c.desktop.quick, isTrue);
      expect(minimized, isFalse);
      await tester.runAsync(c.desktop.dismissQuick);
      expect(visible, isFalse);
      expect(bounds, {'x': 70.0, 'y': 80.0, 'width': 1280.0, 'height': 860.0});
      await tester.runAsync(c.desktop.showMain);

      // A missing initial snapshot still gets valid monitor-centered bounds.
      final fresh = DesktopShell(c.audio)..initialized = true;
      minimized = true;
      bounds = {'x': -32000, 'y': -32000, 'width': 1280, 'height': 860};
      await tester.runAsync(fresh.toggleQuick);
      await tester.runAsync(fresh.dismissQuick);
      expect(bounds['x'], greaterThan(-30000));
      expect(bounds['y'], greaterThan(-30000));
      expect(bounds['width'], greaterThan(0));
      fresh.dispose();

      // Two left releases inside Windows' double-click interval toggle the app,
      // without also opening the single-click quick panel.
      final dispatch = ClickDispatch(c.audio);
      dispatch.onTrayIconMouseDown();
      await tester.pump(const Duration(milliseconds: 50));
      dispatch.onTrayIconMouseDown();
      await tester.pump(const Duration(seconds: 1));
      expect(dispatch.mainClicks, 1);
      expect(dispatch.quickClicks, 0);
      dispatch.onTrayIconMouseDown();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(dispatch.quickClicks, 1);
      dispatch.dispose();
      c.dispose();
      await tester.runAsync(c.audio.release);
      c.api.dio.close(force: true);
      messenger.setMockMethodCallHandler(
        const MethodChannel('window_manager'),
        null,
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('tray_manager'),
        null,
      );
    },
  );
}
