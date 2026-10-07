import '../l10n/wave_localizations.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:ffi' hide Size;
import 'dart:io';
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
  bool mini = false, initialized = false, _quitting = false;
  Rect? _normalBounds;
  bool _normalMaximized = false;
  String? _title;
  DesktopShell(this.audio);
  Future<void> initialize() async {
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
        await windowManager.show();
        await windowManager.focus();
      },
    );
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

  Future<void> toggleMini() async {
    if (!initialized) return;
    if (!mini) {
      _normalMaximized = await windowManager.isMaximized();
      if (_normalMaximized) {
        await windowManager.unmaximize();
      }
      _normalBounds = await windowManager.getBounds();
      await windowManager.setMinimumSize(const Size(370, 105));
      await windowManager.setSize(const Size(420, 140));
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setMaximizable(false);
    } else {
      await windowManager.setAlwaysOnTop(false);
      await windowManager.setMaximizable(true);
      await windowManager.setMinimumSize(const Size(760, 540));
      if (_normalBounds != null) await windowManager.setBounds(_normalBounds!);
      if (_normalMaximized) {
        await windowManager.maximize();
      }
    }
    mini = !mini;
    notifyListeners();
    await windowManager.show();
  }

  @override
  void onWindowClose() {
    if (!_quitting) unawaited(windowManager.hide());
  }

  @override
  void onTrayIconMouseDown() {
    unawaited(windowManager.show());
    unawaited(windowManager.focus());
  }

  @override
  void onTrayIconRightMouseDown() {
    unawaited(trayManager.popUpContextMenu());
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'open':
        onTrayIconMouseDown();
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
    _quitting = true;
    await audio.localCommand('stop');
    await trayManager.destroy();
    await windowManager.destroy();
  }

  @override
  void dispose() {
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
