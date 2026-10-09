import '../l10n/wave_localizations.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/controller.dart';
import '../core/models.dart';
import '../services/ambience.dart';
import 'widgets.dart';
import 'player.dart';
import 'appearance_panel.dart';

List<String> get lofiScenes => [
  wt('native.b3d81a3f8b'),
  wt('native.2400e502b3'),
  wt('native.4589c6cdad'),
  wt('native.635c3de27b'),
];

class LofiPage extends StatefulWidget {
  final WaveController controller;
  final void Function(WaveTrack)? onMore;
  const LofiPage({super.key, required this.controller, this.onMore});
  @override
  State<LofiPage> createState() => _LofiPageState();
}

class _LofiPageState extends State<LofiPage>
    with SingleTickerProviderStateMixin {
  WaveController get c => widget.controller;
  late final AnimationController motion = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 90),
  );
  final RainAmbience rain = RainAmbience();
  final ValueNotifier<double> sceneTime = ValueNotifier(0);
  Duration _lastFrame = Duration.zero;
  Timer? _clock;
  DateTime now = DateTime.now();
  late int scene;
  late String atmosphere;
  late double rainLevel;
  bool zen = false;
  bool _visible = false;
  @override
  void initState() {
    super.initState();
    motion.addListener(() {
      final elapsed = motion.lastElapsedDuration ?? Duration.zero;
      if ((elapsed - _lastFrame).inMilliseconds < 42) return;
      _lastFrame = elapsed;
      sceneTime.value = motion.value * 90;
    });
    scene = (c.preferences.getInt('lofiScene') ?? 0).clamp(0, 3);
    atmosphere = c.preferences.getString('lofiAtmosphere') ?? 'glow';
    if (!['none', 'glow', 'rain'].contains(atmosphere)) atmosphere = 'glow';
    rainLevel = (c.preferences.getDouble('lofiRain') ?? 0).clamp(0, 1);
    if (rainLevel > 0) unawaited(_rain(rainLevel));
  }

  Future<void> _rain(double level) async {
    try {
      await rain.setLevel(level);
    } catch (_) {
      if (mounted) {
        setState(() => rainLevel = 0);
        c.tell(wt('native.bcc3751765', context: context));
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = TickerMode.of(context);
    if (_visible != visible) {
      _visible = visible;
      _clock?.cancel();
      _clock = visible
          ? Timer.periodic(const Duration(seconds: 10), (_) {
              if (mounted) setState(() => now = DateTime.now());
            })
          : null;
      now = DateTime.now();
    }
    if (waveVisuals(context).reducedMotion ||
        MediaQuery.disableAnimationsOf(context) ||
        !visible) {
      motion.stop();
    } else if (!motion.isAnimating) {
      motion.repeat();
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    motion.dispose();
    sceneTime.dispose();
    unawaited(rain.dispose());
    super.dispose();
  }

  void _scene(int value) {
    setState(() => scene = value);
    unawaited(c.preferences.setInt('lofiScene', value));
  }

  void _atmosphere(String value) {
    setState(() => atmosphere = value);
    unawaited(c.preferences.setString('lofiAtmosphere', value));
  }

  @override
  Widget build(BuildContext context) {
    final v = waveVisuals(context), width = MediaQuery.sizeOf(context).width;
    final timestamp = WaveStrings.of(context).time(now);
    return Scaffold(
      appBar: zen
          ? null
          : AppBar(
              title: Text(
                wt('native.847e19da38', context: context),
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              backgroundColor: v.background,
              elevation: 0,
              scrolledUnderElevation: 0,
              actions: [
                IconButton(
                  tooltip: wt('native.d206f1bed0', context: context),
                  icon: const Icon(Icons.palette_outlined),
                  onPressed: () {
                    if (c.appearanceStore != null) showLofiAppearance(context);
                  },
                ),
              ],
            ),
      body: SafeArea(
        top: !zen,
        bottom: !zen,
        child: zen
            ? stage(timestamp, true)
            : SingleChildScrollView(
                padding: EdgeInsets.all(width < 600 ? 20 : 36),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1100),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        PageHeading(
                          wt('native.1d03ab1de9', context: context),
                          wt('native.711dd88a87', context: context),
                        ),
                        SizedBox(
                          height: width < 600 ? 425 : 520,
                          child: stage(timestamp, false),
                        ),
                        const SizedBox(height: 25),
                        Text(
                          wt('native.6182f364dd', context: context),
                          style: TextStyle(
                            color: v.muted,
                            fontSize: 9,
                            letterSpacing: 1.6,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (var i = 0; i < lofiScenes.length; i++)
                              ChoiceChip(
                                key: Key('lofi-scene-$i'),
                                label: Text(lofiScenes[i]),
                                selected: scene == i,
                                onSelected: (_) => _scene(i),
                              ),
                          ],
                        ),
                        const SizedBox(height: 23),
                        Text(
                          wt('native.3acf87bef9', context: context),
                          style: TextStyle(
                            color: v.muted,
                            fontSize: 9,
                            letterSpacing: 1.6,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final choice in {
                              'none': wt('native.dae7e05e24', context: context),
                              'glow': wt('native.4883983984', context: context),
                              'rain': wt('native.aad03f21ab', context: context),
                            }.entries)
                              ChoiceChip(
                                key: Key('lofi-atmos-${choice.key}'),
                                label: Text(choice.value),
                                selected: atmosphere == choice.key,
                                onSelected: (_) => _atmosphere(choice.key),
                              ),
                          ],
                        ),
                        const SizedBox(height: 23),
                        Surface(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                wt('native.d049e3f66b', context: context),
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                wt('native.32c2235be0', context: context),
                                style: TextStyle(color: v.muted, fontSize: 11),
                              ),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.water_drop_outlined,
                                    size: 20,
                                  ),
                                  Expanded(
                                    child: Slider(
                                      key: const Key('lofi-rain-level'),
                                      value: rainLevel,
                                      onChanged: (value) {
                                        setState(() => rainLevel = value);
                                        unawaited(_rain(value));
                                      },
                                      onChangeEnd: (value) => unawaited(
                                        c.preferences.setDouble(
                                          'lofiRain',
                                          value,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '${(rainLevel * 100).round()}%',
                                    style: TextStyle(
                                      color: v.muted,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        if (c.audio.viewCurrent != null) ...[
                          const SizedBox(height: 22),
                          MiniPlayer(
                            controller: c,
                            onOpen: () => openPlayer(context),
                          ),
                        ],
                        const SizedBox(height: 20),
                        Text(
                          wt('native.d4958d914e', context: context),
                          style: TextStyle(color: v.muted, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  void showLofiAppearance(BuildContext context) => _openAppearance(context);

  Widget stage(String timestamp, bool full) {
    final v = waveVisuals(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(full ? 0 : waveRadius(context, 24)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: CustomPaint(painter: LofiLandscapePainter(scene)),
          ),
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: sceneTime,
              builder: (_, child) => CustomPaint(
                painter: LofiAtmospherePainter(
                  scene,
                  atmosphere,
                  sceneTime.value,
                  v.reducedMotion || MediaQuery.disableAnimationsOf(context),
                ),
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x33203028),
                  Color(0x00203028),
                  Color(0xbb15271f),
                ],
                stops: [0, .4, 1],
              ),
            ),
          ),
          Positioned(
            top: 17,
            left: 20,
            right: 10,
            child: Row(
              children: [
                Text(
                  wt('native.88d40c97f5', context: context),
                  style: TextStyle(
                    fontSize: 8,
                    letterSpacing: 1.5,
                    color: const Color(0xffefede3).withValues(alpha: .8),
                  ),
                ),
                const Spacer(),
                IconButton(
                  key: const Key('lofi-zen'),
                  tooltip: zen
                      ? wt('native.201adfd2e2', context: context)
                      : wt('native.b22adb46b6', context: context),
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0x44302f2c),
                  ),
                  icon: Icon(
                    zen
                        ? Icons.close_fullscreen_rounded
                        : Icons.open_in_full_rounded,
                    color: const Color(0xffefede3),
                    size: 19,
                  ),
                  onPressed: () => setState(() => zen = !zen),
                ),
              ],
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  timestamp,
                  key: const Key('lofi-clock'),
                  style: const TextStyle(
                    color: Color(0xffefede3),
                    fontSize: 68,
                    fontWeight: FontWeight.w300,
                    letterSpacing: -4,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  wt('native.370bd25ead', context: context),
                  style: TextStyle(
                    fontSize: 8,
                    letterSpacing: 2,
                    color: const Color(0xffefede3).withValues(alpha: .65),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 25,
            right: 25,
            bottom: 25,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  lofiScenes[scene],
                  style: const TextStyle(
                    color: Color(0xffefede3),
                    fontSize: 23,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  wt('native.7237c9b62a', context: context),
                  style: TextStyle(
                    color: const Color(0xffefede3).withValues(alpha: .7),
                    fontSize: 10,
                  ),
                ),
                if (full && c.audio.viewCurrent != null) ...[
                  const SizedBox(height: 22),
                  MiniPlayer(controller: c, onOpen: () => openPlayer(context)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> openPlayer(BuildContext context) => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        body: SafeArea(
          child: PlayerPage(
            controller: c,
            onMore:
                widget.onMore ??
                (track) => showModalBottomSheet<void>(
                  context: context,
                  builder: (sheet) => SafeArea(
                    child: Wrap(
                      children: [
                        if (c.online && c.loggedIn)
                          ListTile(
                            leading: const Icon(Icons.favorite_border_rounded),
                            title: Text(
                              c.likedIds.contains(track.id)
                                  ? wt('native.2c89e1f83b', context: context)
                                  : wt('native.5633e5c745', context: context),
                            ),
                            onTap: () {
                              Navigator.pop(sheet);
                              unawaited(
                                c
                                    .like(track)
                                    .catchError(
                                      (Object e) => c.tell(e.toString()),
                                    ),
                              );
                            },
                          ),
                        if (track.offline)
                          ListTile(
                            leading: const Icon(Icons.download_rounded),
                            title: Text(
                              wt('native.1acf0afe60', context: context),
                            ),
                            onTap: () {
                              Navigator.pop(sheet);
                              unawaited(
                                c.cache
                                    .save(track, manual: true)
                                    .catchError(
                                      (Object e) => c.tell(e.toString()),
                                    ),
                              );
                            },
                          ),
                        if (track.sourceUrl.isNotEmpty)
                          ListTile(
                            leading: const Icon(Icons.open_in_new_rounded),
                            title: Text(
                              wt(
                                'native.22618d4822',
                                values: {'p0': (track.sourceName)},
                                context: context,
                              ),
                            ),
                            onTap: () {
                              Navigator.pop(sheet);
                              unawaited(
                                c
                                    .openUrl(track.sourceUrl)
                                    .catchError(
                                      (Object e) => c.tell(e.toString()),
                                    ),
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                ),
          ),
        ),
      ),
    ),
  );

  Future<void> _openAppearance(BuildContext context) async {
    final store = c.appearanceStore;
    if (store != null) await showAppearance(context, store);
  }
}

class _SceneRandom {
  int seed = 36;
  double next() {
    seed = (seed * 1664525 + 1013904223) & 0xffffffff;
    return seed / 4294967296;
  }
}

/// Port of the user's final HTML canvas scene; no downloaded scenery required.
class LofiLandscapePainter extends CustomPainter {
  final int scene;
  const LofiLandscapePainter(this.scene);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 480, size.height / 280);
    final random = _SceneRandom();
    final snow = scene == 2, sea = scene == 1, night = scene == 3;
    final paint = Paint();
    const rect = Rect.fromLTWH(0, 0, 480, 280);
    paint.shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      stops: const [0, .6, 1],
      colors: [
        snow
            ? const Color(0xffa7b9be)
            : night
            ? const Color(0xff283a4c)
            : const Color(0xff7c9c82),
        snow
            ? const Color(0xffd2d3c6)
            : night
            ? const Color(0xff70837e)
            : const Color(0xffc4c6a1),
        const Color(0xff293f3c),
      ],
    ).createShader(rect);
    canvas.drawRect(rect, paint);
    paint.shader = null;
    canvas.drawCircle(
      const Offset(339, 62),
      20,
      paint..color = night ? const Color(0xffe3d9b4) : const Color(0xffd8d7ac),
    );
    for (var layer = 0; layer < 3; layer++) {
      final path = Path()..moveTo(0, 155 + layer * 10.0);
      for (var x = 0; x <= 480; x += 4) {
        final y =
            120 +
            layer * 16 -
            math.sin(x * .012 + layer) * 33 -
            math.cos(x * .025 + layer * 4) * 13;
        path.lineTo(x.toDouble(), (y / 2).round() * 2.0);
      }
      path
        ..lineTo(480, 280)
        ..lineTo(0, 280)
        ..close();
      canvas.drawPath(
        path,
        paint
          ..color = const [
            Color(0xff6a877a),
            Color(0xff4c7064),
            Color(0xff36584f),
          ][layer],
      );
    }
    canvas.drawRect(
      const Rect.fromLTWH(0, 166, 480, 114),
      paint
        ..color = snow
            ? const Color(0xff899e9a)
            : night
            ? const Color(0xff425e62)
            : const Color(0xff6e9182),
    );
    for (var i = 0; i < 410; i++) {
      final x = random.next() * 480, y = 166 + random.next() * 114;
      canvas.drawRect(
        Rect.fromLTWH(
          x.floorToDouble(),
          y.floorToDouble(),
          (2 + random.next() * (y - 150) / 4).floorToDouble(),
          1,
        ),
        paint
          ..color = const [
            Color(0x70afbd9a),
            Color(0x33365e56),
            Color(0x50d0d3ae),
            Color(0x8838685e),
          ][i % 4],
      );
    }
    void tree(double x, double y, double scale, Color color) {
      paint.color = color;
      canvas.drawRect(
        Rect.fromLTWH(
          x.floorToDouble(),
          y.floorToDouble(),
          math.max(2, scale * .055).floorToDouble(),
          scale.floorToDouble(),
        ),
        paint,
      );
      for (var j = 0; j < 6; j++) {
        final at = y + j * scale * .1;
        canvas.drawPath(
          Path()
            ..moveTo(x + scale * .02, at - scale * .5)
            ..lineTo(x - scale * (.15 + j * .02), at + scale * .18)
            ..lineTo(x + scale * (.19 + j * .02), at + scale * .18)
            ..close(),
          paint,
        );
      }
    }

    if (!sea) {
      for (var i = 0; i < 19; i++) {
        tree(
          random.next() * 220 - 40,
          118 + random.next() * 38,
          30 + random.next() * 60,
          snow ? const Color(0xff5d7974) : const Color(0xff31594b),
        );
      }
      for (var i = 0; i < 11; i++) {
        tree(
          350 + random.next() * 160,
          116 + random.next() * 43,
          50 + random.next() * 50,
          snow ? const Color(0xff537470) : const Color(0xff2b4d40),
        );
      }
    }
    canvas.drawPath(
      Path()
        ..moveTo(0, 210)
        ..cubicTo(80, 198, 100, 240, 220, 244)
        ..lineTo(480, 280)
        ..lineTo(0, 280)
        ..close(),
      paint..color = const Color(0xff24483c),
    );
    canvas.drawPath(
      Path()
        ..moveTo(0, 250)
        ..lineTo(105, 232)
        ..lineTo(240, 267)
        ..lineTo(420, 256)
        ..lineTo(480, 280)
        ..lineTo(0, 280)
        ..close(),
      paint..color = const Color(0xff1f3d33),
    );
    if (!sea) {
      tree(26, 135, 155, const Color(0xff1c352e));
      tree(450, 158, 147, const Color(0xff1c352e));
      tree(6, 191, 100, const Color(0xff1a3028));
    }
    for (var i = 0; i < 100; i++) {
      final x = random.next() * 480, y = random.next() * 100 + 180;
      canvas.drawRect(
        Rect.fromLTWH(
          x.floorToDouble(),
          y.floorToDouble(),
          (1 + random.next() * 3).floorToDouble(),
          1,
        ),
        paint..color = snow ? const Color(0x99e6e7d7) : const Color(0x66c2c795),
      );
    }
    if (snow) {
      for (var i = 0; i < 200; i++) {
        canvas.drawRect(
          Rect.fromLTWH(
            (random.next() * 480).floorToDouble(),
            (random.next() * 280).floorToDouble(),
            2,
            2,
          ),
          paint..color = const Color(0xaae3e4d8),
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(LofiLandscapePainter old) => scene != old.scene;
}

class LofiAtmospherePainter extends CustomPainter {
  final int scene;
  final String atmosphere;
  final double seconds;
  final bool reducedMotion;
  const LofiAtmospherePainter(
    this.scene,
    this.atmosphere,
    this.seconds,
    this.reducedMotion,
  );
  @override
  void paint(Canvas canvas, Size size) {
    if (reducedMotion) return;
    final paint = Paint(), t = seconds;
    canvas.save();
    canvas.scale(size.width / 480, size.height / 280);
    for (var i = 0; i < 27; i++) {
      final x = 175 + (i * 137 % 240), y = 176 + i * 2.1;
      paint.color = const Color(
        0xffe7e7b4,
      ).withValues(alpha: (math.sin(t + i) * .5 + .5) * .17);
      canvas.drawRect(
        Rect.fromLTWH(x + math.sin(t + i) * 4, y, (5 + i % 8).toDouble(), 1),
        paint,
      );
    }
    canvas.restore();
    if (atmosphere == 'none') return;
    final wet = atmosphere == 'rain', snow = scene == 2;
    if (wet || snow) {
      paint
        ..color = const Color(0x4ddeE7e1)
        ..strokeWidth = .8;
      for (var i = 0; i < (wet ? 100 : 55); i++) {
        final x = (i * 93.7 + t * (wet ? 38 : 8)) % size.width,
            y = (i * 69.3 + t * (wet ? 260 : 23)) % size.height;
        if (wet) {
          canvas.drawLine(Offset(x, y), Offset(x - 4, y + 13), paint);
        } else {
          canvas.drawCircle(
            Offset(x + math.sin(t + i) * 7, y),
            1 + i % 3 * .4,
            paint
              ..color = const Color(
                0xfff5f3ea,
              ).withValues(alpha: .2 + i % 4 * .14),
          );
        }
      }
    } else {
      for (var i = 0; i < 26; i++) {
        final x = (i * 127.7) % size.width + math.sin(t * .4 + i) * 16,
            y =
                size.height * .3 +
                (i * 79.1) % (size.height * .6) +
                math.cos(t * .6 + i) * 13,
            opacity = math.pow(math.sin(t + i * .8) * .5 + .5, 3) * .7;
        paint.shader = RadialGradient(
          colors: [
            const Color(0xffe1e49c).withValues(alpha: opacity.toDouble()),
            const Color(0x00e1e49c),
          ],
        ).createShader(Rect.fromCircle(center: Offset(x, y), radius: 6));
        canvas.drawCircle(Offset(x, y), 6, paint);
      }
    }
  }

  @override
  bool shouldRepaint(LofiAtmospherePainter old) =>
      scene != old.scene ||
      atmosphere != old.atmosphere ||
      seconds != old.seconds ||
      reducedMotion != old.reducedMotion;
}
