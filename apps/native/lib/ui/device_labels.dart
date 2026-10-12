import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'widgets.dart';
import '../core/models.dart';
import '../l10n/wave_localizations.dart';

String deviceKindLabel(Json device, {BuildContext? context}) =>
    wt(switch (device['kind'] ?? device['clientKind']) {
      'web' => 'devices.web',
      'windows' => 'devices.windows',
      'android' => 'devices.android',
      'ios' => 'devices.ios',
      _ => 'devices.desktop',
    }, context: context);

IconData deviceKindIcon(Json device) =>
    switch (device['kind'] ?? device['clientKind']) {
      'web' => Icons.web_asset_rounded,
      'android' || 'ios' => Icons.smartphone_rounded,
      _ => Icons.desktop_windows_outlined,
    };

String activityDate(dynamic value, BuildContext context) {
  final date = value is num
      ? DateTime.fromMillisecondsSinceEpoch(value.toInt()).toLocal()
      : value is String
      ? DateTime.tryParse(value)?.toLocal()
      : null;
  if (date == null) return '';
  final material = MaterialLocalizations.of(context);
  return '${material.formatCompactDate(date)} · ${material.formatTimeOfDay(TimeOfDay.fromDateTime(date))}';
}

/// Named browser marks are intentionally distinct from a generic globe.
class DevicePlatformIcon extends StatelessWidget {
  final Json device;
  final double size;
  final Color? color;
  const DevicePlatformIcon({
    super.key,
    required this.device,
    this.size = 22,
    this.color,
  });
  @override
  Widget build(BuildContext context) {
    final name =
        '${device['name'] ?? device['deviceName'] ?? ''} ${device['browser'] ?? ''}'
            .toLowerCase();
    final kind = device['kind'] ?? device['clientKind'];
    if (kind == 'web' && name.contains('chrome')) {
      return Semantics(
        label: 'Chrome',
        child: SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _BrowserPainter(color ?? waveVisuals(context).muted),
          ),
        ),
      );
    }
    return Icon(
      kind == 'web'
          ? name.contains('safari')
                ? Icons.explore_outlined
                : name.contains('edge')
                ? Icons.public_rounded
                : Icons.web_asset_rounded
          : deviceKindIcon(device),
      size: size,
      color: color,
    );
  }
}

class _BrowserPainter extends CustomPainter {
  final Color color;
  const _BrowserPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero), r = size.shortestSide * .43;
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(c, r, p);
    canvas.drawCircle(c, r * .43, p);
    for (var i = 0; i < 3; i++) {
      final angle = -math.pi / 2 + i * math.pi * 2 / 3;
      canvas.drawLine(
        c + Offset(math.cos(angle), math.sin(angle)) * r * .43,
        c + Offset(math.cos(angle + .7), math.sin(angle + .7)) * r,
        p,
      );
    }
  }

  @override
  bool shouldRepaint(_BrowserPainter old) => old.color != color;
}

/// A tiny repaint-only waveform stops when paused, backgrounded or offscreen.
class ListeningWave extends StatefulWidget {
  final bool playing;
  final double size;
  final Color? color;
  const ListeningWave({
    super.key,
    required this.playing,
    this.size = 18,
    this.color,
  });
  @override
  State<ListeningWave> createState() => _ListeningWaveState();
}

class _ListeningWaveState extends State<ListeningWave>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final clock = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );
  bool visible = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void sync() {
    if (widget.playing &&
        visible &&
        TickerMode.of(context) &&
        !waveVisuals(context).reducedMotion &&
        !MediaQuery.disableAnimationsOf(context)) {
      if (!clock.isAnimating) clock.repeat();
    } else {
      clock.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    sync();
  }

  @override
  void didUpdateWidget(ListeningWave old) {
    super.didUpdateWidget(old);
    sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    visible = state == AppLifecycleState.resumed;
    sync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: SizedBox(
      width: widget.size,
      height: widget.size,
      child: CustomPaint(
        key: const Key('listening-wave'),
        painter: _WavePainter(
          clock,
          widget.playing,
          widget.color ?? waveVisuals(context).accent,
        ),
      ),
    ),
  );
}

class _WavePainter extends CustomPainter {
  final Animation<double> clock;
  final bool playing;
  final Color color;
  _WavePainter(this.clock, this.playing, this.color) : super(repaint: clock);
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = size.width / 10
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 5; i++) {
      final h = playing
          ? .22 +
                .62 * (.5 + .5 * math.sin(clock.value * math.pi * 2 + i * 1.7))
          : .22 + (i == 2 ? .2 : 0);
      final x = size.width * (.1 + i * .2);
      canvas.drawLine(
        Offset(x, size.height * (1 - h) / 2),
        Offset(x, size.height * (1 + h) / 2),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.playing != playing || old.color != color;
}
