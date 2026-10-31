import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../core/appearance.dart';
import '../core/controller.dart';
import 'widgets.dart';

String studioText(BuildContext context, String key) {
  final ru = Localizations.localeOf(context).languageCode == 'ru';
  const labels = <String, List<String>>{
    'atmosphere': ['Атмосфера', 'Atmosphere'],
    'saving': ['Энергосбережение', 'Power saving'],
    'savingHint': [
      'Без тяжёлых эффектов. Музыка продолжает играть.',
      'Reduce visual work while music keeps playing.',
    ],
    'background': ['Фон мини-плеера', 'Mini-player background'],
    'cover': ['Обложка', 'Artwork'],
    'pixels': ['Пиксели', 'Pixels'],
    'plain': ['Спокойный', 'Plain'],
    'wallpaper': ['Свои обои', 'Your wallpaper'],
    'choose': ['Выбрать изображение / GIF', 'Choose image / GIF'],
    'remove': ['Убрать', 'Remove'],
    'dim': ['Затемнение', 'Dimming'],
    'blur': ['Размытие', 'Blur'],
    'themes': ['Палитры', 'Palettes'],
    'save': ['Сохранить свою тему', 'Save your theme'],
    'name': ['Название темы', 'Theme name'],
    'cancel': ['Отмена', 'Cancel'],
    'done': ['Готово', 'Done'],
    'saved': ['Мои темы', 'Your themes'],
    'love': ['С любовью, GlukWave', 'With love, GlukWave'],
    'loveHint': [
      'Спасибо, что слушаешь с нами',
      'Thank you for listening with us',
    ],
    'amoled': [
      'В AMOLED обои скрыты: фон остаётся абсолютно чёрным.',
      'AMOLED keeps the background truly black; wallpaper is hidden.',
    ],
    'admin': ['Открыть Gluk Wave for Admins', 'Open Gluk Wave for Admins'],
  };
  final pair = labels[key];
  return pair == null ? key : pair[ru ? 0 : 1];
}

class StudioAppearance extends StatelessWidget {
  final WaveController controller;
  const StudioAppearance({super.key, required this.controller});
  Future<void> _run(Future<void> Function() work) async {
    try {
      await work();
    } catch (e) {
      controller.tell(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = controller,
        v = waveVisuals(context),
        state = c.customization,
        w = state.wallpaper;
    void change(Map<String, dynamic> patch) =>
        unawaited(_run(() => c.customize(patch)));
    return DefaultTextStyle.merge(
      style: TextStyle(color: v.ink),
      child: ListTileTheme(
        textColor: v.ink,
        iconColor: v.muted,
        child: Surface(
          key: const Key('studio-appearance'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                studioText(context, 'atmosphere'),
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SwitchListTile(
                key: const Key('studio-power-saving'),
                contentPadding: EdgeInsets.zero,
                title: Text(
                  studioText(context, 'saving'),
                  style: TextStyle(color: v.ink),
                ),
                subtitle: Text(
                  studioText(context, 'savingHint'),
                  style: TextStyle(fontSize: 12, color: v.muted),
                ),
                value: state.powerSaving,
                onChanged: (value) => change({'powerSaving': value}),
              ),
              const Divider(height: 28),
              Text(
                studioText(context, 'background'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  for (final type in ['cover', 'pixels', 'plain'])
                    ChoiceChip(
                      label: Text(studioText(context, type)),
                      selected: state.appearance.miniBackground == type,
                      onSelected: (_) => change({
                        'appearance': {'miniBackground': type},
                      }),
                    ),
                ],
              ),
              const Divider(height: 28),
              Text(
                studioText(context, 'themes'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              if (c.user?.plan == 'free')
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    Localizations.localeOf(context).languageCode == 'ru'
                        ? 'Полные палитры доступны в Unbound. Основную тему и акцент можно менять бесплатно.'
                        : 'Full palettes are available with Unbound. Theme modes and accents remain free.',
                    style: TextStyle(color: v.muted, fontSize: 11, height: 1.5),
                  ),
                ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) => Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final preset in studioPalettes)
                      SizedBox(
                        width: (constraints.maxWidth - 24) / 4,
                        child: InkWell(
                          key: Key('studio-preset-${preset.id}'),
                          onTap: () => change({
                            'theme': preset.mode,
                            'appearance': {
                              preset.mode: preset.colors.toJson(),
                              'coverAccent': false,
                            },
                          }),
                          borderRadius: BorderRadius.circular(9),
                          child: Container(
                            height: 66,
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: hexColor(preset.colors.bg),
                              borderRadius: BorderRadius.circular(9),
                              border: Border.all(
                                color: hexColor(
                                  preset.colors.accent,
                                ).withValues(alpha: .55),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    for (final hex in [
                                      preset.colors.surface,
                                      preset.colors.accent,
                                      preset.colors.ink,
                                    ])
                                      Container(
                                        width: 9,
                                        height: 9,
                                        margin: const EdgeInsets.only(right: 2),
                                        decoration: BoxDecoration(
                                          color: hexColor(hex),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                  ],
                                ),
                                const Spacer(),
                                Text(
                                  preset.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: hexColor(preset.colors.ink),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                key: const Key('studio-save-theme'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: v.ink,
                  disabledForegroundColor: v.muted,
                ),
                onPressed: state.savedThemes.length >= 12
                    ? null
                    : () async {
                        final field = TextEditingController();
                        final name = await showWaveDialog<String>(
                          context: context,
                          builder: (dialog) => AlertDialog(
                            title: Text(studioText(context, 'name')),
                            content: TextField(
                              controller: field,
                              maxLength: 40,
                              autofocus: true,
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(dialog),
                                child: Text(studioText(context, 'cancel')),
                              ),
                              FilledButton(
                                onPressed: () =>
                                    Navigator.pop(dialog, field.text.trim()),
                                child: Text(studioText(context, 'done')),
                              ),
                            ],
                          ),
                        );
                        field.dispose();
                        if (name == null || name.isEmpty) return;
                        final mode = state.theme == 'light' ? 'light' : 'dark',
                            palette = mode == 'light'
                                ? state.appearance.light
                                : state.appearance.dark;
                        change({
                          'savedThemes': [
                            ...state.savedThemes,
                            {
                              'id':
                                  'custom-${DateTime.now().microsecondsSinceEpoch}',
                              'name': name,
                              'mode': mode,
                              'colors': palette.toJson(),
                            },
                          ],
                        });
                      },
                icon: Icon(
                  Icons.add_rounded,
                  size: 17,
                  color: state.savedThemes.length >= 12 ? v.muted : v.ink,
                ),
                label: Text(
                  studioText(context, 'save'),
                  style: TextStyle(
                    color: state.savedThemes.length >= 12 ? v.muted : v.ink,
                  ),
                ),
              ),
              if (state.savedThemes.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  studioText(context, 'saved'),
                  style: TextStyle(color: v.muted, fontSize: 11),
                ),
                for (final theme in state.savedThemes)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      theme['name'].toString(),
                      style: TextStyle(color: v.ink),
                    ),
                    leading: CircleAvatar(
                      radius: 9,
                      backgroundColor: hexColor(theme['colors']['accent']),
                    ),
                    onTap: () => change({
                      'theme': theme['mode'],
                      'appearance': {
                        theme['mode']: theme['colors'],
                        'coverAccent': false,
                      },
                    }),
                    trailing: IconButton(
                      tooltip: studioText(context, 'remove'),
                      icon: const Icon(Icons.close_rounded, size: 16),
                      onPressed: () => change({
                        'savedThemes': state.savedThemes
                            .where((item) => item['id'] != theme['id'])
                            .toList(),
                      }),
                    ),
                  ),
              ],
              const Divider(height: 28),
              Text(
                studioText(context, 'wallpaper'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                key: const Key('studio-wallpaper-upload'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: v.ink,
                  disabledForegroundColor: v.muted,
                ),
                onPressed: c.online ? () => _run(c.uploadWallpaper) : null,
                icon: Icon(
                  Icons.wallpaper_rounded,
                  size: 18,
                  color: c.online ? v.ink : v.muted,
                ),
                label: Text(
                  studioText(context, 'choose'),
                  style: TextStyle(color: c.online ? v.ink : v.muted),
                ),
              ),
              if ((w['url']?.toString() ?? '').isNotEmpty) ...[
                TextButton(
                  onPressed: () => change({
                    'wallpaper': {'url': ''},
                  }),
                  child: Text(studioText(context, 'remove')),
                ),
                for (final item in [('dim', .9, 90), ('blur', 24.0, 24)])
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${studioText(context, item.$1)} · ${item.$1 == 'dim' ? ((w[item.$1] as num) * 100).round() : (w[item.$1] as num).round()}${item.$1 == 'dim' ? '%' : ' px'}',
                        style: TextStyle(fontSize: 12, color: v.muted),
                      ),
                      Slider(
                        value: (w[item.$1] as num).toDouble(),
                        max: item.$2,
                        divisions: item.$3,
                        onChanged: (value) => change({
                          'wallpaper': {item.$1: value},
                        }),
                      ),
                    ],
                  ),
              ],
              if (state.theme == 'amoled')
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    studioText(context, 'amoled'),
                    style: TextStyle(color: v.muted, fontSize: 11, height: 1.5),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class StudioWallpaper extends StatelessWidget {
  final WaveController controller;
  final Widget child;
  const StudioWallpaper({
    super.key,
    required this.controller,
    required this.child,
  });
  @override
  Widget build(BuildContext context) {
    final c = controller,
        state = c.customization,
        w = state.wallpaper,
        url = w['url']?.toString() ?? '';
    if (url.isEmpty || state.theme == 'amoled' || c.energySaving) return child;
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(
                sigmaX: (w['blur'] as num).toDouble(),
                sigmaY: (w['blur'] as num).toDouble(),
              ),
              child: Image.network(
                c.api.url(url),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    ColoredBox(color: waveVisuals(context).background),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: ColoredBox(
              color: Colors.black.withValues(
                alpha: (w['dim'] as num).toDouble(),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class MiniAtmosphere extends StatefulWidget {
  final WaveController controller;
  const MiniAtmosphere({super.key, required this.controller});
  @override
  State<MiniAtmosphere> createState() => _MiniAtmosphereState();
}

class _MiniAtmosphereState extends State<MiniAtmosphere>
    with SingleTickerProviderStateMixin {
  late final AnimationController clock = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  );
  @override
  void dispose() {
    clock.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(MiniAtmosphere old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final c = widget.controller,
        animate =
            c.customization.appearance.miniBackground == 'pixels' &&
            !c.energySaving &&
            !waveVisuals(context).reducedMotion &&
            c.audio.playing;
    if (animate && !clock.isAnimating) {
      clock.repeat();
    } else if (!animate) {
      clock.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    _sync();
    final c = widget.controller,
        v = waveVisuals(context),
        kind = c.customization.appearance.miniBackground,
        url = c.audio.viewCurrent?.artwork ?? '';
    if (kind == 'plain' || c.energySaving) return const SizedBox.shrink();
    return IgnorePointer(
      child: kind == 'cover' && url.isNotEmpty
          ? Opacity(
              opacity: .13,
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                child: Artwork(controller: c, url: url, size: 160, radius: 0),
              ),
            )
          : kind == 'pixels'
          ? AnimatedBuilder(
              animation: clock,
              builder: (_, __) => CustomPaint(
                painter: _PixelAtmosphere(v.accent, clock.value),
                size: Size.infinite,
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}

class _PixelAtmosphere extends CustomPainter {
  final Color tone;
  final double time;
  const _PixelAtmosphere(this.tone, this.time);
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint();
    for (var x = 0.0; x < size.width; x += 12) {
      final base =
          size.height * (.62 + .15 * math.sin(x * .014 + time * math.pi * 2));
      for (var row = 0; row < 3; row++) {
        p.color = tone.withValues(alpha: .035 + row * .02);
        canvas.drawRect(Rect.fromLTWH(x, base + row * 12, 7, 7), p);
      }
    }
  }

  @override
  bool shouldRepaint(_PixelAtmosphere old) =>
      old.time != time || old.tone != tone;
}

class AboutHeartbeat extends StatefulWidget {
  const AboutHeartbeat({super.key});
  @override
  State<AboutHeartbeat> createState() => _AboutHeartbeatState();
}

class _AboutHeartbeatState extends State<AboutHeartbeat>
    with SingleTickerProviderStateMixin {
  late final AnimationController clock = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );
  bool active = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (waveVisuals(context).reducedMotion) {
      clock.stop();
    } else if (!clock.isAnimating) {
      clock.repeat();
    }
  }

  @override
  void dispose() {
    clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = waveVisuals(context);
    return Semantics(
      button: true,
      label: studioText(context, 'love'),
      child: InkWell(
        key: const Key('about-heartbeat'),
        onTap: () => setState(() => active = !active),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: clock,
                builder: (_, __) {
                  final t = clock.value,
                      pulse =
                          math.exp(-math.pow((t - .14) / .05, 2)) +
                          .65 * math.exp(-math.pow((t - .3) / .055, 2));
                  return Transform.scale(
                    scale:
                        1 + (v.reducedMotion ? 0 : pulse * (active ? .2 : .08)),
                    child: Icon(
                      Icons.favorite_rounded,
                      size: 22,
                      color: v.accent,
                    ),
                  );
                },
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      studioText(context, 'love'),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      studioText(context, 'loveHint'),
                      style: TextStyle(color: v.muted, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
