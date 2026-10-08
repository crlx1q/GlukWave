import '../l10n/wave_localizations.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:ffi' hide Size;
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:tray_manager/tray_manager.dart';
import 'package:uuid/uuid.dart';
import 'package:win32/win32.dart';
import 'package:window_manager/window_manager.dart';
import '../core/models.dart';
import 'audio.dart';

// Discord's documented, local IPC framing. No Discord user token is requested.
class DiscordPresence extends ChangeNotifier {
  int _pipe = INVALID_HANDLE_VALUE;
  Timer? _timer;
  List<int> _buffer = [];
  String _statusKey = 'native.25363da343';
  String? _externalStatus;
  String get status => _externalStatus ?? wt(_statusKey);
  bool ready = false;
  Future<void> connect(String clientId) async {
    close();
    if (!Platform.isWindows || clientId.isEmpty) {
      _externalStatus = null;
      _statusKey = clientId.isEmpty ? 'native.15b20dde3a' : 'native.a984270377';
      notifyListeners();
      return;
    }
    for (var i = 0; i < 10; i++) {
      final name = r'\\?\pipe\discord-ipc-' + i.toString();
      final path = name.toNativeUtf16();
      _pipe = CreateFile(
        path,
        GENERIC_READ | GENERIC_WRITE,
        0,
        nullptr,
        OPEN_EXISTING,
        0,
        NULL,
      );
      calloc.free(path);
      if (_pipe != INVALID_HANDLE_VALUE) break;
    }
    if (_pipe == INVALID_HANDLE_VALUE) {
      _externalStatus = null;
      _statusKey = 'native.6bde881273';
      notifyListeners();
      return;
    }
    _externalStatus = null;
    _statusKey = 'native.5d84405321';
    _write(0, {'v': 1, 'client_id': clientId});
    _timer = Timer.periodic(const Duration(milliseconds: 350), (_) => _read());
    notifyListeners();
  }

  void _write(int opcode, Json payload) {
    if (_pipe == INVALID_HANDLE_VALUE) return;
    final json = utf8.encode(jsonEncode(payload));
    final packet = Uint8List(json.length + 8);
    final header = ByteData.sublistView(packet);
    header.setUint32(0, opcode, Endian.little);
    header.setUint32(4, json.length, Endian.little);
    packet.setAll(8, json);
    final memory = calloc<Uint8>(packet.length), count = calloc<Uint32>();
    try {
      memory.asTypedList(packet.length).setAll(0, packet);
      if (WriteFile(_pipe, memory, packet.length, count, nullptr) == 0) {
        close();
        _externalStatus = null;
        _statusKey = 'native.8d9b2503b6';
        notifyListeners();
      }
    } finally {
      calloc.free(memory);
      calloc.free(count);
    }
  }

  void _read() {
    if (_pipe == INVALID_HANDLE_VALUE) return;
    final available = calloc<Uint32>(), count = calloc<Uint32>();
    try {
      if (PeekNamedPipe(_pipe, nullptr, 0, nullptr, available, nullptr) == 0) {
        close();
        _externalStatus = null;
        _statusKey = 'native.ac8bdece49';
        notifyListeners();
        return;
      }
      final length = available.value;
      if (length == 0) return;
      if (length > 1024 * 1024) {
        close();
        return;
      }
      final memory = calloc<Uint8>(length);
      try {
        if (ReadFile(_pipe, memory, length, count, nullptr) == 0) {
          close();
          return;
        }
        _buffer.addAll(memory.asTypedList(count.value));
      } finally {
        calloc.free(memory);
      }
      while (_buffer.length >= 8) {
        final bytes = Uint8List.fromList(_buffer);
        final header = ByteData.sublistView(bytes);
        final opcode = header.getUint32(0, Endian.little),
            size = header.getUint32(4, Endian.little);
        if (size > 1024 * 1024) {
          close();
          return;
        }
        if (_buffer.length < 8 + size) break;
        final data = object(
          jsonDecode(utf8.decode(bytes.sublist(8, 8 + size))),
        );
        _buffer = _buffer.sublist(8 + size);
        if (opcode == 3) _write(4, data);
        if (opcode == 2) {
          close();
          _externalStatus = null;
          _statusKey = 'native.f34acd6e4a';
        }
        if (data['evt'] == 'READY') {
          ready = true;
          _externalStatus = null;
          _statusKey = 'native.52bc821a01';
        }
        if (data['evt'] == 'ERROR') {
          _externalStatus = object(data['data'])['message'] as String?;
          _statusKey = 'native.7d5b9d9122';
        }
        notifyListeners();
      }
    } catch (_) {
      close();
      _externalStatus = null;
      _statusKey = 'native.cc94d41c5f';
      notifyListeners();
    } finally {
      calloc.free(available);
      calloc.free(count);
    }
  }

  void update(
    WaveTrack? track,
    bool playing,
    double position,
    String appUrl, {
    Json? room,
  }) {
    if (!ready) return;
    Json? activity;
    if (track != null && playing) {
      final start =
          DateTime.now().millisecondsSinceEpoch ~/ 1000 - position.floor();
      activity = {
        'type': 2,
        'details': track.title,
        'state': track.artist,
        'timestamps': {
          'start': start,
          if (track.duration > 0) 'end': start + track.duration.floor(),
        },
        'assets': {
          'large_image': track.artwork.startsWith('https://')
              ? track.artwork
              : 'glukwave',
          'large_text': 'GlukWave',
        },
        'buttons': [
          {
            'label': wt('native.c746e31388'),
            'url': '$appUrl/?track=${Uri.encodeComponent(track.id)}',
          },
          if (room != null)
            {
              'label': wt('native.200ba6b661'),
              'url':
                  '$appUrl/?room=${Uri.encodeComponent(room['inviteCode'] as String)}',
            },
        ],
      };
    }
    _write(1, {
      'cmd': 'SET_ACTIVITY',
      'args': {'pid': pid, 'activity': activity},
      'nonce': const Uuid().v4(),
    });
  }

  void close() {
    _timer?.cancel();
    _timer = null;
    if (_pipe != INVALID_HANDLE_VALUE) CloseHandle(_pipe);
    _pipe = INVALID_HANDLE_VALUE;
    ready = false;
    _buffer = [];
  }

  @override
  void dispose() {
    close();
    super.dispose();
  }
}

class DesktopShell extends ChangeNotifier with WindowListener, TrayListener {
  final WaveAudioHandler audio;
  bool mini = false, quick = false, initialized = false, _quitting = false;
  Rect? _normalBounds;
  bool _normalMaximized = false;
  bool _mainVisibleBeforeQuick = false, _quickReady = false;
  bool _miniBeforeQuick = false;
  bool _changingWindow = false;
  int _boundsRead = 0;
  Rect? _miniBoundsBeforeQuick;
  Timer? _trayClick;
  Future<void> _windowWrites = Future.value();
  String? _title;
  DesktopShell(this.audio);
  Future<void> initialize({bool startMinimized = false}) async {
    if (!Platform.isWindows) return;
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        size: Size(1280, 860),
        minimumSize: Size(760, 540),
        center: true,
        title: 'GlukWave',
        backgroundColor: Color(0xffefede3),
      ),
      () async {
        if (!startMinimized) {
          await windowManager.show();
          await windowManager.focus();
        }
      },
    );
    final initialBounds = await windowManager.getBounds();
    _normalBounds = _validNormalBounds(initialBounds)
        ? initialBounds
        : _centeredMainBounds();
    windowManager.addListener(this);
    trayManager.addListener(this);
    await trayManager.setIcon(
      p.join(
        p.dirname(Platform.resolvedExecutable),
        'data',
        'flutter_assets',
        'assets',
        'app_icon.ico',
      ),
    );
    await windowManager.setPreventClose(true);
    initialized = true;
    await localize();
  }

  Future<void> localize() async {
    if (!initialized) return;
    await trayManager.setToolTip(wt('native.adc9a38302'));
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'open', label: wt('native.c82b849d9a')),
          MenuItem(key: 'play', label: wt('native.3f60cf701d')),
          MenuItem(key: 'next', label: wt('native.c97fa8b29b')),
          MenuItem(key: 'mini', label: wt('native.e5ee886686')),
          MenuItem.separator(),
          MenuItem(key: 'quit', label: wt('native.026abb1e0a')),
        ],
      ),
    );
  }

  Future<void> updateTitle() async {
    if (!initialized) return;
    final value = audio.player.playing && audio.current != null
        ? '${audio.current!.title} — ${audio.current!.artist}'
        : 'GlukWave';
    if (_title == value) return;
    _title = value;
    await windowManager.setTitle(value);
    await trayManager.setToolTip(
      value.substring(0, value.length.clamp(0, 120)),
    );
  }

  Future<void> _serialize(Future<void> Function() action) {
    final operation = _windowWrites.catchError((_) {}).then((_) async {
      _changingWindow = true;
      try {
        await action();
      } finally {
        _changingWindow = false;
      }
    });
    _windowWrites = operation;
    return operation;
  }

  void _background(Future<void> operation) => unawaited(
    operation.catchError(
      (Object error) => audio.onError?.call(error.toString()),
    ),
  );

  Future<void> _rememberMain() async {
    if (mini || quick) return;
    if (await windowManager.isMinimized()) {
      _normalBounds ??= _centeredMainBounds();
      return;
    }
    _normalMaximized = await windowManager.isMaximized();
    if (_normalMaximized) await windowManager.unmaximize();
    final bounds = await windowManager.getBounds();
    if (_validNormalBounds(bounds)) _normalBounds = bounds;
    _normalBounds ??= _centeredMainBounds();
  }

  bool _validNormalBounds(Rect bounds) =>
      bounds.left.isFinite &&
      bounds.top.isFinite &&
      bounds.width.isFinite &&
      bounds.height.isFinite &&
      bounds.width >= 760 &&
      bounds.height >= 540 &&
      bounds.left > -30000 &&
      bounds.top > -30000;

  Rect _centeredMainBounds() {
    final work = _displayPlacement().work;
    return Rect.fromCenter(
      center: work.center,
      width: math.min(1280, work.width - 24),
      height: math.min(860, work.height - 24),
    );
  }

  Future<void> _captureMainBounds() async {
    if (mini || quick || _changingWindow) return;
    final request = ++_boundsRead;
    if (await windowManager.isMinimized()) return;
    final maximized = await windowManager.isMaximized();
    if (request != _boundsRead || mini || quick || _changingWindow) return;
    _normalMaximized = maximized;
    if (maximized) return;
    final bounds = await windowManager.getBounds();
    if (request == _boundsRead &&
        !mini &&
        !quick &&
        !_changingWindow &&
        _validNormalBounds(bounds)) {
      _normalBounds = bounds;
    }
  }

  Future<void> _restoreMain() async {
    _quickReady = false;
    mini = quick = false;
    await windowManager.setOpacity(1);
    await windowManager.setTitleBarStyle(TitleBarStyle.normal);
    await windowManager.setAlwaysOnTop(false);
    await windowManager.setSkipTaskbar(false);
    await windowManager.setResizable(true);
    await windowManager.setMaximizable(true);
    await windowManager.setMinimumSize(const Size(760, 540));
    if (_normalBounds != null) await windowManager.setBounds(_normalBounds!);
    if (_normalMaximized) await windowManager.maximize();
    notifyListeners();
  }

  Future<void> showMain() => _serialize(() async {
    if (!initialized) return;
    if (mini || quick) await _restoreMain();
    await windowManager.show();
    if (await windowManager.isMinimized()) await windowManager.restore();
    await windowManager.focus();
  });

  Future<void> toggleMain() => _serialize(() async {
    if (!initialized) return;
    if (mini || quick) {
      await _restoreMain();
      await windowManager.show();
      await windowManager.focus();
    } else if (await windowManager.isVisible() &&
        !await windowManager.isMinimized()) {
      await windowManager.hide();
    } else {
      await windowManager.show();
      if (await windowManager.isMinimized()) await windowManager.restore();
      await windowManager.focus();
    }
  });

  Future<void> toggleMini() => _serialize(() async {
    if (!initialized) return;
    if (!mini) {
      await _rememberMain();
      if (await windowManager.isMinimized()) await windowManager.restore();
      _quickReady = false;
      quick = false;
      await windowManager.setMinimumSize(const Size(330, 116));
      await windowManager.setAsFrameless();
      await windowManager.setSize(const Size(410, 116));
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setSkipTaskbar(true);
      await windowManager.setOpacity(.94);
      await windowManager.setResizable(false);
      await windowManager.setMaximizable(false);
      if (_normalBounds != null) {
        final placement = await _cornerBounds(const Size(410, 116));
        await windowManager.setBounds(placement);
      }
      mini = true;
    } else {
      await _restoreMain();
    }
    notifyListeners();
    await windowManager.show();
  });

  /// Tray bounds and monitor work area are converted with the same Flutter DPI.
  /// This keeps the popup above a bottom taskbar and inside side-taskbar screens.
  ({Rect work, Offset anchor}) _displayPlacement() {
    final ratio = windowManager.getDevicePixelRatio();
    final cursor = calloc<POINT>(), info = calloc<MONITORINFO>();
    Rect work;
    Offset anchor;
    try {
      GetCursorPos(cursor);
      anchor = Offset(cursor.ref.x / ratio, cursor.ref.y / ratio);
      final monitor = MonitorFromPoint(cursor.ref, MONITOR_DEFAULTTONEAREST);
      info.ref.cbSize = sizeOf<MONITORINFO>();
      if (GetMonitorInfo(monitor, info) != 0) {
        final area = info.ref.rcWork;
        work = Rect.fromLTRB(
          area.left / ratio,
          area.top / ratio,
          area.right / ratio,
          area.bottom / ratio,
        );
      } else {
        work = _normalBounds ?? const Rect.fromLTWH(0, 0, 1280, 860);
      }
    } finally {
      calloc.free(cursor);
      calloc.free(info);
    }
    return (work: work, anchor: anchor);
  }

  Future<Rect> _cornerBounds(Size requested) async {
    final display = _displayPlacement(), work = display.work;
    var anchor = display.anchor;
    final tray = await trayManager.getBounds();
    if (tray != null && !tray.isEmpty) anchor = tray.center;
    final width = math.min(requested.width, work.width - 20);
    final height = math.min(requested.height, work.height - 20);
    return Rect.fromLTWH(
      (anchor.dx - width / 2).clamp(work.left + 10, work.right - width - 10),
      (anchor.dy - height - 12).clamp(work.top + 10, work.bottom - height - 10),
      width,
      height,
    );
  }

  Future<void> toggleQuick() => _serialize(() async {
    if (!initialized) return;
    if (quick) {
      await _dismissQuick();
      return;
    }
    _miniBeforeQuick = mini;
    _miniBoundsBeforeQuick = mini ? await windowManager.getBounds() : null;
    final minimized = await windowManager.isMinimized();
    _mainVisibleBeforeQuick =
        !mini && !minimized && await windowManager.isVisible();
    await _rememberMain();
    if (minimized) await windowManager.restore();
    mini = false;
    await windowManager.setMinimumSize(const Size(300, 330));
    await windowManager.setAsFrameless();
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setSkipTaskbar(true);
    await windowManager.setOpacity(1);
    await windowManager.setResizable(false);
    await windowManager.setMaximizable(false);
    await windowManager.setBounds(await _cornerBounds(const Size(360, 420)));
    quick = true;
    notifyListeners();
    await windowManager.show();
    await windowManager.focus();
    _quickReady = true;
  });

  Future<void> _dismissQuick() async {
    if (!quick) return;
    await windowManager.hide();
    if (_miniBeforeQuick) {
      _quickReady = false;
      quick = false;
      mini = true;
      await windowManager.setMinimumSize(const Size(330, 116));
      await windowManager.setOpacity(.94);
      if (_miniBoundsBeforeQuick != null) {
        await windowManager.setBounds(_miniBoundsBeforeQuick!);
      }
      notifyListeners();
      await windowManager.show();
      return;
    }
    await _restoreMain();
    if (_mainVisibleBeforeQuick) await windowManager.show();
  }

  Future<void> dismissQuick() => _serialize(_dismissQuick);

  Future<void> drag() async {
    if (initialized) await windowManager.startDragging();
  }

  @override
  void onWindowClose() {
    if (!_quitting) _background(windowManager.hide());
  }

  @override
  void onWindowBlur() {
    if (quick && _quickReady) _background(dismissQuick());
  }

  @override
  void onWindowMove() => _background(_captureMainBounds());

  @override
  void onWindowResize() => _background(_captureMainBounds());

  @override
  void onTrayIconMouseDown() {
    if (_trayClick?.isActive == true) {
      _trayClick!.cancel();
      _trayClick = null;
      _background(toggleMain());
      return;
    }
    final interval = Platform.isWindows ? GetDoubleClickTime() : 400;
    _trayClick = Timer(Duration(milliseconds: interval), () {
      _trayClick = null;
      _background(toggleQuick());
    });
  }

  @override
  void onTrayIconRightMouseDown() {
    unawaited(trayManager.popUpContextMenu());
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'open':
        _background(showMain());
      case 'play':
        unawaited(
          (audio.player.playing ? audio.pause() : audio.play()).catchError((
            Object error,
          ) {
            audio.onError?.call(error.toString());
          }),
        );
      case 'next':
        unawaited(
          audio.skipToNext().catchError((Object error) {
            audio.onError?.call(error.toString());
          }),
        );
      case 'mini':
        unawaited(toggleMini());
      case 'quit':
        unawaited(quit());
    }
  }

  Future<void> quit() async {
    _trayClick?.cancel();
    _quitting = true;
    await audio.localCommand('stop');
    await trayManager.destroy();
    await windowManager.destroy();
  }

  @override
  void dispose() {
    _trayClick?.cancel();
    if (initialized) {
      windowManager.removeListener(this);
      trayManager.removeListener(this);
    }
    super.dispose();
  }
}

Future<List<Json>> discoverServers({int port = 4001}) async {
  final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  socket.broadcastEnabled = true;
  final found = <String, Json>{};
  final subscription = socket.listen((event) {
    if (event != RawSocketEvent.read) return;
    final packet = socket.receive();
    if (packet == null) return;
    try {
      final data = object(jsonDecode(utf8.decode(packet.data)));
      if (data['name'] == 'GlukWave' &&
          data['version'] == 1 &&
          data['port'] is int &&
          data['port'] > 0 &&
          data['port'] < 65536) {
        final address = 'http://${packet.address.address}:${data['port']}';
        found[address] = {...data, 'url': address};
      }
    } catch (_) {
      /* Ignore traffic that is not a discovery response. */
    }
  });
  socket.send(
    utf8.encode('GLUKWAVE_DISCOVER_V1'),
    InternetAddress('255.255.255.255'),
    port,
  );
  await Future<void>.delayed(const Duration(seconds: 3));
  await subscription.cancel();
  socket.close();
  return found.values.toList();
}
