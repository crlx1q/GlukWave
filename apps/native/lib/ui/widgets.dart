import '../l10n/wave_localizations.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/models.dart';
import '../core/controller.dart';
import '../core/artwork.dart';
import '../core/wave_math.dart';
import 'silk_wave.dart';

export 'theme.dart';
import 'theme.dart';

const background = Color(0xffefede3),
    surface = Color(0xfff8f7f1),
    ink = Color(0xff302f2c),
    muted = Color(0xff797772),
    accent = Color(0xffa08369),
    accentSoft = Color(0xffe1dacf),
    line = Color(0x1c302f2c);

/// Dialog-owned editors must remain alive through the closing animation.
/// Navigator's result completes before the route's widgets are unmounted.
Future<T?> showWaveDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = DialogRoute<T>(
    context: context,
    builder: builder,
    themes: InheritedTheme.capture(from: context, to: navigator.context),
  );
  final value = await navigator.push<T>(route);
  await route.completed;
  return value;
}

class Brand extends StatelessWidget {
  final bool animated, compact;
  final double size;
  const Brand({
    super.key,
    this.animated = false,
    this.compact = false,
    this.size = 34,
  });
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      RepaintBoundary(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(waveRadius(context, size * .3)),
          child: Image.asset(
            'assets/logo.${animated && !waveVisuals(context).reducedMotion && !MediaQuery.disableAnimationsOf(context) ? 'gif' : 'png'}',
            width: size,
            height: size,
            cacheWidth: 96,
          ),
        ),
      ),
      if (!compact) const SizedBox(width: 10),
      if (!compact)
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(
                text: 'gluk ',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const TextSpan(
                text: 'wave',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              TextSpan(
                text: '.',
                style: TextStyle(
                  color: waveVisuals(context).accent,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          style: TextStyle(
            fontSize: size * .7,
            color: waveVisuals(context).ink,
            letterSpacing: -1,
          ),
        ),
    ],
  );
}

class PageHeading extends StatelessWidget {
  final String title, subtitle, eyebrow;
  final Widget? action;
  const PageHeading(
    this.title,
    this.subtitle, {
    super.key,
    this.eyebrow = '',
    this.action,
  });
  @override
  Widget build(BuildContext context) {
    final compact =
        MediaQuery.sizeOf(context).width < 700 || waveVisuals(context).compact;
    return Padding(
      padding: const EdgeInsets.only(bottom: 26),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (eyebrow.isNotEmpty && !compact)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 9),
                    child: Text(
                      eyebrow,
                      style: TextStyle(
                        fontSize: 10,
                        color: waveVisuals(context).muted,
                        letterSpacing: 1.8,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: compact ? 27 : 34,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -1.5,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: waveVisuals(context).muted,
                    fontSize: 13,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
          if (action != null && !compact)
            Padding(padding: const EdgeInsets.only(left: 20), child: action!),
        ],
      ),
    );
  }
}

class Surface extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  const Surface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(22),
    this.color,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: waveVisuals(context).compact ? padding * .75 : padding,
    decoration: BoxDecoration(
      color: color ?? waveVisuals(context).surface,
      borderRadius: BorderRadius.circular(waveRadius(context, 22)),
      border: Border.all(color: waveVisuals(context).line),
    ),
    child: child,
  );
}

class EmptyState extends StatelessWidget {
  final String title, text;
  final IconData icon;
  final Widget? action;
  const EmptyState(
    this.title,
    this.text, {
    super.key,
    this.icon = Icons.music_note_outlined,
    this.action,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 46, horizontal: 14),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: waveVisuals(context).accentSoft,
              borderRadius: BorderRadius.circular(waveRadius(context, 24)),
            ),
            child: Icon(icon, size: 32, color: waveVisuals(context).ink),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -.5,
            ),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(color: waveVisuals(context).muted, height: 1.7),
            ),
          ),
          if (action != null)
            Padding(padding: const EdgeInsets.only(top: 22), child: action!),
        ],
      ),
    ),
  );
}

class Artwork extends StatelessWidget {
  final WaveController controller;
  final String? url;
  final double size, radius;
  final IconData icon;
  const Artwork({
    super.key,
    required this.controller,
    this.url,
    this.size = 46,
    this.radius = 11,
    this.icon = Icons.music_note_rounded,
  });
  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      color: waveVisuals(context).accentSoft,
      child: Center(
        child: Icon(
          icon,
          size: size * .38,
          color: waveVisuals(context).ink.withValues(alpha: .6),
        ),
      ),
    );
    final value = url ?? '';
    final uri = value.isNotEmpty
        ? Uri.tryParse(controller.api.url(value))
        : null;
    Widget image(String address, {bool mayFallback = false}) => Image.network(
      address,
      fit: BoxFit.cover,
      headers: uri!.origin == Uri.parse(controller.api.server).origin
          ? controller.api.headers
          : null,
      cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).ceil().clamp(
        64,
        1024,
      ),
      frameBuilder: (_, image, frame, synchronous) =>
          synchronous || frame != null ? image : const WaveSkeletonBlock(),
      errorBuilder: (_, error, trace) =>
          mayFallback ? image(uri.toString()) : fallback,
    );
    final original = uri?.toString() ?? '';
    final displayed = artworkForDisplay(original, large: size >= 96);
    return ClipRRect(
      borderRadius: BorderRadius.circular(waveRadius(context, radius)),
      child: SizedBox(
        width: size,
        height: size,
        child: uri == null
            ? fallback
            : image(displayed, mayFallback: displayed != original),
      ),
    );
  }
}

/// A real pending request or image frame owns this placeholder's lifetime.
class WaveSkeletonBlock extends StatefulWidget {
  final double? width;
  final double height, radius;
  const WaveSkeletonBlock({
    super.key,
    this.width,
    this.height = 14,
    this.radius = 6,
  });
  @override
  State<WaveSkeletonBlock> createState() => _WaveSkeletonBlockState();
}

class _WaveSkeletonBlockState extends State<WaveSkeletonBlock>
    with SingleTickerProviderStateMixin {
  late final pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still =
        waveVisuals(context).reducedMotion ||
        MediaQuery.disableAnimationsOf(context);
    if (still) {
      pulse.stop();
    } else if (!pulse.isAnimating) {
      pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: AnimatedBuilder(
      animation: pulse,
      builder: (_, child) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: Color.lerp(
            waveVisuals(context).accentSoft,
            waveVisuals(context).line,
            .22 + pulse.value * .28,
          ),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    ),
  );
}

class WaveLoadingList extends StatelessWidget {
  final int rows;
  final String? label;
  const WaveLoadingList({super.key, this.rows = 5, this.label});
  @override
  Widget build(BuildContext context) => Semantics(
    label: label ?? wt('native.e917ac283f', context: context),
    liveRegion: true,
    child: Column(
      children: [
        for (var i = 0; i < rows; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Row(
              children: [
                const WaveSkeletonBlock(width: 46, height: 46, radius: 11),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FractionallySizedBox(
                        widthFactor: i.isEven ? .7 : .55,
                        child: const WaveSkeletonBlock(),
                      ),
                      const SizedBox(height: 8),
                      const WaveSkeletonBlock(width: 90, height: 10),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                const WaveSkeletonBlock(width: 22, height: 18),
              ],
            ),
          ),
      ],
    ),
  );
}

class WaveHero extends StatefulWidget {
  final WaveController? controller;
  final VoidCallback? onPlay;
  final bool reducedMotion;
  final bool empty;
  const WaveHero({
    super.key,
    this.controller,
    this.onPlay,
    this.reducedMotion = false,
    this.empty = false,
  });
  @override
  State<WaveHero> createState() => _WaveHeroState();
}

class _WaveHeroState extends State<WaveHero>
    with SingleTickerProviderStateMixin {
  late final AnimationController animation = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 90),
  );
  double _energy = 0, _pointerActive = 0, _targetActive = 0;
  Offset _pointer = const Offset(.5, .5),
      _pointerTarget = const Offset(.5, .5),
      _velocity = Offset.zero;
  ScrollPosition? _scroll;
  bool _visible = true;
  Duration _lastFrame = Duration.zero;
  bool get reduced =>
      widget.reducedMotion ||
      waveVisuals(context).reducedMotion ||
      MediaQuery.disableAnimationsOf(context);
  @override
  void initState() {
    super.initState();
    animation.addListener(_tick);
  }

  void _tick() {
    final time = animation.lastElapsedDuration ?? Duration.zero;
    final dt = (time - _lastFrame).inMicroseconds / 1000000;
    final interval = MediaQuery.sizeOf(context).width < 500 ? 1 / 24 : 1 / 30;
    if (dt < interval && dt >= 0) return;
    _lastFrame = time;
    final c = widget.controller, seconds = dt.clamp(0.0, .07);
    final target = c == null
        ? 0.0
        : c.waveforms
              .envelopeFor(c.audio.viewCurrent?.id)
              .at(c.audio.position.inMilliseconds / 1000, c.audio.playing);
    setState(() {
      _energy = reduced ? 0 : easeEnergy(_energy, target, seconds);
      final movement = 1 - math.exp(-seconds * 16);
      final before = _pointer;
      _pointer += (_pointerTarget - _pointer) * movement;
      final targetVelocity = seconds > 0
          ? (_pointer - before) / seconds
          : Offset.zero;
      _velocity += (targetVelocity - _velocity) * (1 - math.exp(-seconds * 8));
      _pointerActive +=
          (_targetActive - _pointerActive) * (1 - math.exp(-seconds * 5));
    });
  }

  void _readPointer(Offset point, double width, double height) {
    if (reduced) return;
    _pointerTarget = Offset(
      (point.dx / width).clamp(0, 1),
      (point.dy / height).clamp(0, 1),
    );
    _targetActive = 1;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scroll = Scrollable.maybeOf(context)?.position;
    if (!identical(scroll, _scroll)) {
      _scroll?.removeListener(_visibility);
      _scroll = scroll;
      _scroll?.addListener(_visibility);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _visibility();
    });
    _motion();
  }

  @override
  void didUpdateWidget(WaveHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    _motion();
  }

  void _motion() {
    if (reduced || !_visible || !TickerMode.of(context)) {
      animation.stop();
    } else if (!animation.isAnimating) {
      animation.repeat();
    }
  }

  void _visibility() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !mounted) return;
    final origin = box.localToGlobal(Offset.zero),
        viewport = MediaQuery.sizeOf(context);
    _visible = origin.dy < viewport.height && origin.dy + box.size.height > 0;
    _motion();
  }

  @override
  void dispose() {
    _scroll?.removeListener(_visibility);
    animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final v = waveVisuals(context);
      final compact = constraints.maxWidth < 600 || v.compact;
      final height = compact ? 224.0 : 310.0;
      return MouseRegion(
        onHover: (event) => _readPointer(
          event.localPosition,
          constraints.maxWidth,
          (context.findRenderObject() as RenderBox).size.height,
        ),
        onExit: (_) => _targetActive = 0,
        child: Listener(
          onPointerMove: (event) => _readPointer(
            event.localPosition,
            constraints.maxWidth,
            (context.findRenderObject() as RenderBox).size.height,
          ),
          onPointerUp: (_) => _targetActive = 0,
          onPointerCancel: (_) => _targetActive = 0,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(
              waveRadius(context, compact ? 20 : 24),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: height),
              child: Stack(
                children: [
                  Positioned.fill(child: Container(color: v.player)),
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: WavePainter(
                          reduced
                              ? bloomPhase
                              : bloomPhase + animation.value * 90,
                          accentColor: v.accent,
                          backgroundColor: v.surface,
                          style: v.waveStyle,
                          energy: reduced ? 0 : _energy,
                          pointer: reduced ? const Offset(.5, .5) : _pointer,
                          pointerActive: reduced ? 0 : _pointerActive,
                          pointerVelocity: reduced ? Offset.zero : _velocity,
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            v.player,
                            v.player.withValues(alpha: .94),
                            v.player.withValues(alpha: 0),
                          ],
                          stops: const [0, .32, 1],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.all(compact ? 22 : 34),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              wt('native.2bf6b84a6f', context: context),
                              style: TextStyle(
                                color: v.onPlayer.withValues(alpha: .66),
                                letterSpacing: 1.8,
                                fontSize: 9,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: compact ? 18 : 28),
                        Text(
                          wt('native.c56877fbe6', context: context),
                          style: TextStyle(
                            fontSize: compact ? 28 : 36,
                            height: 1.1,
                            color: v.onPlayer,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -1,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.empty
                              ? wt('native.c1a1b57faa', context: context)
                              : wt('native.642189648a', context: context),
                          style: TextStyle(
                            color: v.onPlayer.withValues(alpha: .72),
                            fontSize: compact ? 11 : 13,
                            height: 1.7,
                          ),
                        ),
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          onPressed: widget.onPlay,
                          style: FilledButton.styleFrom(
                            backgroundColor: v.onPlayer,
                            foregroundColor: v.player,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 14,
                            ),
                            shape: const StadiumBorder(),
                          ),
                          icon: Icon(
                            widget.empty
                                ? Icons.add_rounded
                                : Icons.play_arrow_rounded,
                            size: 19,
                          ),
                          label: Text(
                            widget.empty
                                ? wt('native.99855bf52d', context: context)
                                : wt('native.5f266e04fe', context: context),
                          ),
                        ),
                        if (!compact) const SizedBox(height: 18),
                        if (!compact)
                          Row(
                            children: [
                              Icon(
                                Icons.graphic_eq,
                                color: waveVisuals(context).accent,
                                size: 16,
                              ),
                              SizedBox(width: 8),
                              Text(
                                wt('native.c4ea2e3005', context: context),
                                style: TextStyle(
                                  color: v.onPlayer.withValues(alpha: .65),
                                  fontSize: 10,
                                ),
                              ),
                              Spacer(),
                              Text(
                                '∞',
                                style: TextStyle(
                                  color: waveVisuals(context).accent,
                                  fontSize: 28,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class WavePainter extends CustomPainter {
  final double phase, energy, pointerActive;
  final Offset pointer;
  final Offset pointerVelocity;
  final Color accentColor, backgroundColor;
  final String style;
  WavePainter(
    this.phase, {
    this.accentColor = accent,
    this.backgroundColor = background,
    this.style = 'silk',
    this.energy = 0,
    this.pointer = const Offset(.5, .5),
    this.pointerVelocity = Offset.zero,
    this.pointerActive = 0,
  });
  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    if (style == 'bloom') {
      final diagonal = math.sqrt(
            size.width * size.width + size.height * size.height,
          ),
          steps = (diagonal / bloomCell).ceil(),
          cosine = math.cos(bloomTurn),
          sine = math.sin(bloomTurn);
      final paint = Paint();
      for (var row = -steps; row < steps; row++) {
        for (var column = -steps; column < steps; column++) {
          final cx = (column + .5) * bloomCell,
              cy = (row + .5) * bloomCell,
              x = cx * cosine - cy * sine,
              y = cx * sine + cy * cosine;
          if (x < -bloomCell ||
              x > size.width + bloomCell ||
              y < -bloomCell ||
              y > size.height + bloomCell) {
            continue;
          }
          final u = x / size.width,
              v = y / size.height,
              dot = bloomDot(
                u,
                v,
                phase,
                energy,
                pointer.dx,
                pointer.dy,
                pointerActive,
                size.width / size.height,
              );
          if (dot.level < .003) continue;
          final mix = .5 + .5 * math.sin(u * 6 + phase * .23);
          double channel(double color, double add) =>
              (color * (.55 + .15 * mix) + .4 * (1 - mix) + add * mix).clamp(
                0,
                1,
              );
          paint.color = Color.from(
            alpha: (dot.presence * (.5 + dot.level * .5)).clamp(0, 1),
            red: channel(accentColor.r, .24),
            green: channel(accentColor.g, .3),
            blue: channel(accentColor.b, .34),
          );
          canvas.drawCircle(Offset(x, y), bloomCell * dot.radius, paint);
        }
      }
      return;
    }
    if (style == 'particles') {
      final columns = (size.width / 5).round().clamp(55, 125), paint = Paint();
      for (var layer = 0; layer < 3; layer++) {
        for (var point = 0; point < columns; point++) {
          for (var band = 0; band < 5; band++) {
            final u = point / (columns - 1),
                x = u * size.width,
                y =
                    size.height * .53 +
                    math.sin(u * 9 + phase * .5 + layer * .7) *
                        size.height *
                        (.15 + energy * .018) +
                    math.cos(u * 14 - phase * .7 + band * .25) *
                        size.height *
                        .055 +
                    (band - 2) * 5 +
                    math.sin(point * 127 + band * 73 + layer) * 7 +
                    (pointer.dy - .5) * pointerActive * 10;
            paint.color = Color.from(
              alpha: .2 + (.5 + .5 * math.sin(point * 27 + band + layer)) * .53,
              red: (accentColor.r + layer * 20 / 255).clamp(0, 1),
              green: (accentColor.g + layer * 20 / 255).clamp(0, 1),
              blue: (accentColor.b + layer * 20 / 255).clamp(0, 1),
            );
            canvas.drawCircle(
              Offset(x, y),
              .45 + (math.sin(point * 13 + band) + 1) * .3 + energy * .3,
              paint,
            );
          }
        }
      }
      return;
    }
    drawSilkWave(
      canvas,
      size,
      phase,
      energy,
      accentColor,
      pointer,
      pointerActive,
      background: backgroundColor,
      velocity: pointerVelocity,
    );
  }

  @override
  bool shouldRepaint(WavePainter oldDelegate) =>
      phase != oldDelegate.phase ||
      accentColor != oldDelegate.accentColor ||
      backgroundColor != oldDelegate.backgroundColor ||
      style != oldDelegate.style ||
      energy != oldDelegate.energy ||
      pointer != oldDelegate.pointer ||
      pointerVelocity != oldDelegate.pointerVelocity ||
      pointerActive != oldDelegate.pointerActive;
}

class TrackRow extends StatelessWidget {
  final WaveController controller;
  final WaveTrack track;
  final VoidCallback? onMore;
  final List<WaveTrack>? queue;
  const TrackRow({
    super.key,
    required this.controller,
    required this.track,
    this.onMore,
    this.queue,
  });
  @override
  Widget build(BuildContext context) {
    final active = controller.audio.viewCurrent?.id == track.id;
    final compact = waveVisuals(context).compact;
    final artworkSize = compact ? 38.0 : 46.0;
    return Material(
      color: active ? waveVisuals(context).surface : Colors.transparent,
      borderRadius: BorderRadius.circular(waveRadius(context, 14)),
      child: InkWell(
        borderRadius: BorderRadius.circular(waveRadius(context, 14)),
        onTap: () => _run(() => controller.play(track, list: queue)),
        child: Padding(
          padding: EdgeInsets.symmetric(
            vertical: compact ? 5 : 9,
            horizontal: 10,
          ),
          child: Row(
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  Artwork(
                    controller: controller,
                    url: track.artwork,
                    size: artworkSize,
                  ),
                  if (active)
                    Container(
                      width: artworkSize,
                      height: artworkSize,
                      decoration: BoxDecoration(
                        color: waveVisuals(context).ink.withValues(alpha: .4),
                        borderRadius: BorderRadius.circular(
                          waveRadius(context, 11),
                        ),
                      ),
                      child: Icon(
                        controller.audio.playing
                            ? Icons.graphic_eq_rounded
                            : Icons.play_arrow_rounded,
                        color: waveVisuals(context).background,
                        size: 21,
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      track.artist.isEmpty ? track.sourceName : track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: waveVisuals(context).muted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (MediaQuery.sizeOf(context).width >= 850)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    track.sourceName,
                    style: TextStyle(
                      color: waveVisuals(context).muted,
                      fontSize: 11,
                    ),
                  ),
                ),
              if (controller.cache.contains(track.id))
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    Icons.offline_pin_outlined,
                    size: 16,
                    color: Color(0xff6d8c74),
                  ),
                ),
              if (track.duration > 0 && MediaQuery.sizeOf(context).width > 400)
                Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: Text(
                    clock(track.duration),
                    style: TextStyle(
                      color: waveVisuals(context).muted,
                      fontSize: 11,
                    ),
                  ),
                ),
              IconButton(
                tooltip: controller.likedIds.contains(track.id)
                    ? wt('native.4ddf34c036', context: context)
                    : wt('native.5633e5c745', context: context),
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                onPressed: controller.online
                    ? () => _run(() => controller.like(track))
                    : null,
                icon: Icon(
                  controller.likedIds.contains(track.id)
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: controller.likedIds.contains(track.id)
                      ? waveVisuals(context).accent
                      : waveVisuals(context).muted,
                  size: 19,
                ),
              ),
              IconButton(
                tooltip: wt('native.30ef88c9b5', context: context),
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                onPressed: onMore,
                icon: Icon(
                  Icons.more_horiz_rounded,
                  size: 20,
                  color: waveVisuals(context).muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      controller.tell(e.toString());
    }
  }
}
