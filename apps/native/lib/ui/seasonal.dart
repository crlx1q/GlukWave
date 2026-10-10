import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/appearance.dart';
import '../services/appearance_store.dart';
import '../l10n/season_strings.dart';
import 'widgets.dart';

class SeasonalBackdrop extends StatelessWidget {
  final WaveSeasonalEffects settings;
  final Widget child;
  const SeasonalBackdrop({
    super.key,
    required this.settings,
    required this.child,
  });
  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      child,
      if (settings.enabled)
        Positioned.fill(child: SeasonalAtmosphere(settings: settings)),
    ],
  );
}

class SeasonalAtmosphere extends StatefulWidget {
  final WaveSeasonalEffects settings;
  final bool preview;
  const SeasonalAtmosphere({
    super.key,
    required this.settings,
    this.preview = false,
  });
  @override
  State<SeasonalAtmosphere> createState() => _SeasonalAtmosphereState();
}

class _SeasonalAtmosphereState extends State<SeasonalAtmosphere>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final clock = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 60),
  );
  bool visible = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    sync();
  }

  @override
  void didUpdateWidget(SeasonalAtmosphere oldWidget) {
    super.didUpdateWidget(oldWidget);
    sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    setState(() => visible = state == AppLifecycleState.resumed);
    sync();
  }

  bool get moving =>
      widget.settings.enabled &&
      visible &&
      TickerMode.of(context) &&
      !waveVisuals(context).reducedMotion &&
      !MediaQuery.disableAnimationsOf(context);
  void sync() {
    if (moving) {
      if (!clock.isAnimating) clock.repeat();
    } else {
      clock.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!visible || (!widget.preview && !moving)) {
      return const SizedBox.shrink();
    }
    final v = waveVisuals(context);
    return IgnorePointer(
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: ClipRect(
            child: CustomPaint(
              key: const Key('seasonal-atmosphere'),
              painter: SeasonalPainter(
                clock: clock,
                mode: widget.settings.resolve(),
                intensity: widget.settings.intensity,
                dark: v.brightness == Brightness.dark,
                amoled: v.background.toARGB32() == 0xff000000,
                preview: widget.preview,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SeasonalPainter extends CustomPainter {
  final Animation<double> clock;
  final String mode, intensity;
  final bool dark, amoled, preview;
  SeasonalPainter({
    required this.clock,
    required this.mode,
    required this.intensity,
    required this.dark,
    required this.amoled,
    required this.preview,
  }) : super(repaint: clock);
  double seed(int i, int n) {
    final x = math.sin(i * 128.13 + n * 37.77) * 43758.5453;
    return x - x.floor();
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final count = preview
        ? 16
        : size.width < 600
        ? 24
        : 40;
    final amount = (intensity == 'normal' ? 0.76 : 0.37);
    final time = clock.value * 60;
    if (mode == 'sun') {
      final warm = dark ? const Color(0xffedc890) : const Color(0xffd9a976);
      final radius = math.max(size.width, size.height) * .6;
      for (var i = 0; i < 3; i++) {
        final phase = time * math.pi / 30 + i * 2.1;
        final center = Offset(
          size.width * ([.12, .82, .56][i] + math.sin(phase) * .025),
          size.height * ([.14, .32, .94][i] + math.cos(phase) * .03),
        );
        final paint = Paint()
          ..shader = RadialGradient(
            colors: [
              warm.withValues(alpha: amount * .08),
              warm.withValues(alpha: amount * .036),
              warm.withValues(alpha: 0),
            ],
            stops: const [0, .45, 1],
          ).createShader(Rect.fromCircle(center: center, radius: radius));
        canvas.drawRect(Offset.zero & size, paint);
      }
      return;
    }
    for (var i = 0; i < count; i++) {
      final x = seed(i, 1) * size.width,
          y =
              ((seed(i, 2) * size.height +
                      time *
                          (mode == 'rain'
                              ? 34
                              : mode == 'leaves'
                              ? 10
                              : 8)) %
                  (size.height + 28)) -
              14,
          phase = time * .35 + seed(i, 3) * 6.28,
          r = 2.2 + seed(i, 4) * 2.6;
      final paint = Paint()
        ..color = (dark ? const Color(0xffedf6ff) : const Color(0xff536e83))
            .withValues(alpha: amount * (.5 + seed(i, 5) * .35));
      if (mode == 'snow') {
        canvas.drawCircle(Offset(x + math.sin(phase) * 12, y), r, paint);
      } else if (mode == 'rain') {
        paint
          ..color = (dark ? const Color(0xffa9d8ee) : const Color(0xff486f88))
              .withValues(alpha: amount * .7)
          ..strokeWidth = 1.45;
        canvas.drawLine(Offset(x, y), Offset(x - 3, y + 11 + r * 2.4), paint);
      } else if (mode == 'leaves') {
        canvas.save();
        canvas.translate(x + math.sin(phase) * 18, y);
        canvas.rotate(phase);
        paint.color = [
          dark ? const Color(0xffe0ad70) : const Color(0xff99622e),
          dark ? const Color(0xffc4bd85) : const Color(0xff6f7b42),
          dark ? const Color(0xffdb986e) : const Color(0xffaf6944),
        ][i % 3].withValues(alpha: amount * .7);
        canvas.drawOval(
          Rect.fromCenter(center: Offset.zero, width: r * 3.6, height: r * 1.6),
          paint,
        );
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(SeasonalPainter old) =>
      old.mode != mode ||
      old.intensity != intensity ||
      old.dark != dark ||
      old.amoled != amoled ||
      old.preview != preview ||
      old.clock != clock;
}

class SeasonalSettings extends StatelessWidget {
  final AppearanceStore store;
  const SeasonalSettings({super.key, required this.store});
  @override
  Widget build(BuildContext context) {
    final season = store.current.seasonalEffects, v = waveVisuals(context);
    void change(Map<String, dynamic> patch) {
      store.change({'seasonalEffects': patch});
    }

    String text(String key) => seasonText(key, context: context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 32),
        SwitchListTile(
          key: const Key('seasonal-toggle'),
          contentPadding: EdgeInsets.zero,
          title: Text(
            text('title'),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: Text(
            text('caption'),
            style: TextStyle(color: v.muted, fontSize: 12, height: 1.5),
          ),
          value: season.enabled,
          onChanged: (enabled) => change({'enabled': enabled}),
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: ColoredBox(
            color: v.accentSoft,
            child: SizedBox(
              height: 104,
              width: double.infinity,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: SeasonalAtmosphere(settings: season, preview: true),
                  ),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          text('preview'),
                          style: TextStyle(color: v.muted, fontSize: 11),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          text(season.resolve()),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final mode in ['auto', 'snow', 'rain', 'leaves', 'sun'])
              ChoiceChip(
                key: Key('season-$mode'),
                selected: season.mode == mode,
                label: Text(text(mode)),
                avatar: Icon(switch (mode) {
                  'auto' => Icons.calendar_month_outlined,
                  'snow' => Icons.ac_unit_rounded,
                  'rain' => Icons.water_drop_outlined,
                  'leaves' => Icons.eco_outlined,
                  _ => Icons.wb_sunny_outlined,
                }, size: 16),
                onSelected: (_) => change({'mode': mode}),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              text('intensity'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            for (final intensity in ['subtle', 'normal'])
              ChoiceChip(
                key: Key('season-$intensity'),
                selected: season.intensity == intensity,
                label: Text(text(intensity)),
                onSelected: (_) => change({'intensity': intensity}),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          text('motionHint'),
          style: TextStyle(color: v.muted, fontSize: 12, height: 1.5),
        ),
      ],
    );
  }
}
