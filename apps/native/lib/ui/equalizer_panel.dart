import 'dart:async';
import 'dart:convert';
import '../l10n/audio_design_strings.dart';
import 'dart:io';
import '../l10n/parity_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/controller.dart';
import '../core/equalizer.dart';
import '../core/models.dart';
import '../l10n/wave_localizations.dart';
import 'widgets.dart';
import 'settings_edit.dart';

class EqualizerPanel extends StatelessWidget {
  final WaveController controller;
  const EqualizerPanel({super.key, required this.controller});
  @override
  Widget build(BuildContext context) {
    final c = controller,
        v = waveVisuals(context),
        eq = c.customization.equalizer;
    void change(Json values) => unawaited(
      c.customize({'equalizer': values}).catchError((Object e) {
        c.tell(e.toString());
      }),
    );
    final status = !c.audio.equalizerSupported
        ? 'eq.unsupported'
        : c.audio.equalizerStatus == 'failed'
        ? 'eq.failed'
        : c.audio.equalizerStatus == 'ready'
        ? 'eq.hardware'
        : 'eq.waiting';
    return SettingsEditBoundary(
      store: c.appearanceStore,
      child: Surface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              key: const Key('equalizer-enabled'),
              contentPadding: EdgeInsets.zero,
              title: Text(
                wt('eq.title', context: context),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  Platform.isWindows && status == 'eq.hardware'
                      ? pt(context, 'Windows DSP')
                      : wt(
                          status,
                          context: context,
                          values: {'p0': c.audio.hardwareBandCount},
                        ),
                  style: TextStyle(color: v.muted, height: 1.5, fontSize: 12),
                ),
              ),
              value: eq.enabled,
              onChanged: c.audio.equalizerSupported
                  ? (value) => change({'enabled': value})
                  : null,
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final preset in equalizerPresets.entries)
                  ActionChip(
                    key: Key('equalizer-${preset.key}'),
                    label: Text(_presetLabel(context, preset.key)),
                    onPressed: () => change(preset.value.toJson()),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              wt('eq.curve', context: context),
              style: TextStyle(color: v.muted, fontSize: 11, height: 1.5),
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var band = 0; band < equalizerFrequencies.length; band++)
                    SizedBox(
                      width: 54,
                      child: Column(
                        children: [
                          Text(
                            '${eq.bands[band] > 0 ? '+' : ''}${eq.bands[band].toStringAsFixed(1)}',
                            style: TextStyle(color: v.muted, fontSize: 10),
                          ),
                          SizedBox(
                            height: 145,
                            child: RotatedBox(
                              quarterTurns: 3,
                              child: Slider(
                                key: Key('equalizer-band-$band'),
                                value: eq.bands[band],
                                min: -12,
                                max: 12,
                                divisions: 48,
                                semanticFormatterCallback: (value) =>
                                    '${equalizerFrequencies[band].round()} Hz, ${value.toStringAsFixed(1)} dB',
                                onChanged: (value) => change({
                                  'bands': [...eq.bands]..[band] = value,
                                }),
                              ),
                            ),
                          ),
                          Text(
                            equalizerFrequencies[band] >= 1000
                                ? '${(equalizerFrequencies[band] / 1000).round()}k'
                                : '${equalizerFrequencies[band].round()}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 36),
            Row(
              children: [
                Expanded(
                  child: Text(
                    wt('eq.preamp', context: context),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  '${eq.preamp.toStringAsFixed(1)} dB',
                  style: TextStyle(color: v.muted, fontSize: 12),
                ),
              ],
            ),
            Slider(
              key: const Key('equalizer-preamp'),
              value: eq.preamp,
              min: -12,
              max: 12,
              divisions: 48,
              semanticFormatterCallback: (value) =>
                  '${value.toStringAsFixed(1)} dB',
              onChanged: (value) => change({'preamp': value}),
            ),
            const Divider(height: 32),
            Row(
              children: [
                Expanded(
                  child: Text(
                    wt('eq.speed', context: context),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  '${c.room != null ? '1.00' : c.customization.playbackRate.toStringAsFixed(2)}×',
                  style: TextStyle(color: v.muted, fontSize: 12),
                ),
              ],
            ),
            Slider(
              key: const Key('playback-rate'),
              min: .5,
              max: 2,
              divisions: 30,
              value: c.room != null ? 1 : c.customization.playbackRate,
              semanticFormatterCallback: (value) =>
                  '${value.toStringAsFixed(2)}×',
              onChanged: c.room != null
                  ? null
                  : (value) => unawaited(
                      c.customize({'playbackRate': value}).catchError((
                        Object e,
                      ) {
                        c.tell(e.toString());
                      }),
                    ),
            ),
            if (c.room != null)
              Text(
                wt('eq.roomSpeed', context: context),
                style: TextStyle(color: v.muted, fontSize: 12, height: 1.5),
              ),
          ],
        ),
      ),
    );
  }

  static String _presetLabel(BuildContext context, String key) {
    switch (key) {
      case 'flat':
        return wt('eq.flat', context: context);
      case 'warm':
        return wt('eq.warm', context: context);
      case 'vocal':
        return wt('eq.vocal', context: context);
      case 'bass':
        return wt('eq.bass', context: context);
      case 'bright':
        return wt('eq.bright', context: context);
      default:
        return key;
    }
  }
}

class CompactEqualizerPanel extends StatefulWidget {
  final WaveController controller;
  final VoidCallback onClose;
  const CompactEqualizerPanel({
    super.key,
    required this.controller,
    required this.onClose,
  });
  @override
  State<CompactEqualizerPanel> createState() => _CompactEqualizerPanelState();
}

class _CompactEqualizerPanelState extends State<CompactEqualizerPanel> {
  WaveEqualizer? saved;
  @override
  void initState() {
    super.initState();
    try {
      final raw = widget.controller.preferences.getString(
        'eq-curve:${widget.controller.user?.id}',
      );
      if (raw != null) {
        saved = const WaveEqualizer().merge(object(jsonDecode(raw)));
      }
    } catch (_) {}
  }

  void change(Json patch) => unawaited(
    widget.controller
        .customize({'equalizer': patch})
        .catchError((Object error) => widget.controller.tell(error.toString())),
  );
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final c = widget.controller,
          v = waveVisuals(context),
          eq = c.customization.equalizer,
          available = c.audio.equalizerSupported && c.outputHere,
          preset = equalizerPresets.entries
              .where(
                (p) =>
                    p.value.preamp == eq.preamp &&
                    List.generate(
                      10,
                      (i) => p.value.bands[i] == eq.bands[i],
                    ).every((same) => same),
              )
              .firstOrNull;
      return SettingsEditBoundary(
        store: c.appearanceStore,
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            overlayColor: Colors.transparent,
            overlayShape: SliderComponentShape.noOverlay,
            showValueIndicator: ShowValueIndicator.never,
          ),
          child: Theme(
            data: Theme.of(context).copyWith(
              splashFactory: NoSplash.splashFactory,
              highlightColor: Colors.transparent,
              splashColor: Colors.transparent,
              focusColor: Colors.transparent,
              hoverColor: Colors.transparent,
            ),
            child: Padding(
              padding: const EdgeInsets.all(15),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          wt('eq.title', context: context),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        key: const Key('compact-eq-enabled'),
                        tooltip: wt('eq.title', context: context),
                        isSelected: eq.enabled,
                        onPressed: available
                            ? () => change({'enabled': !eq.enabled})
                            : null,
                        icon: Icon(
                          Icons.power_settings_new_rounded,
                          size: 18,
                          color: eq.enabled ? v.accent : v.muted,
                        ),
                      ),
                      IconButton(
                        tooltip: audioDesignText('reset', context: context),
                        onPressed: () =>
                            change({'bands': List.filled(10, 0), 'preamp': 0}),
                        icon: const Icon(Icons.restart_alt_rounded, size: 17),
                      ),
                      IconButton(
                        tooltip: wt('native.398c7d4f7b', context: context),
                        onPressed: widget.onClose,
                        icon: const Icon(Icons.close_rounded, size: 18),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: _EqualizerPresetMenu(
                          selected:
                              preset?.key ??
                              (saved != null &&
                                      saved!.preamp == eq.preamp &&
                                      List.generate(
                                        10,
                                        (i) => saved!.bands[i] == eq.bands[i],
                                      ).every((same) => same)
                                  ? 'saved'
                                  : 'custom'),
                          saved: saved != null,
                          enabled: available,
                          onSelected: (key) {
                            final p = key == 'saved'
                                ? saved
                                : equalizerPresets[key];
                            if (p != null) {
                              change({...p.toJson(), 'enabled': true});
                            }
                          },
                        ),
                      ),
                      IconButton(
                        tooltip: audioDesignText(
                          'savePreset',
                          context: context,
                        ),
                        onPressed: available
                            ? () {
                                setState(() => saved = eq);
                                unawaited(
                                  c.preferences.setString(
                                    'eq-curve:${c.user?.id}',
                                    jsonEncode(eq.toJson()),
                                  ),
                                );
                              }
                            : null,
                        icon: const Icon(Icons.save_outlined, size: 17),
                      ),
                    ],
                  ),
                  const SizedBox(height: 11),
                  Container(
                    key: const Key('compact-eq-speed-surface'),
                    padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
                    decoration: BoxDecoration(
                      color: v.background,
                      border: Border.all(color: v.line),
                      borderRadius: BorderRadius.circular(v.corners(18)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                wt('eq.speed', context: context),
                                style: TextStyle(fontSize: 10, color: v.muted),
                              ),
                            ),
                            Text(
                              '${(c.room != null ? 1 : c.customization.playbackRate).toStringAsFixed(2)}×',
                              style: const TextStyle(
                                fontSize: 11,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          key: const Key('compact-eq-rate'),
                          min: .5,
                          max: 2,
                          divisions: 30,
                          value: c.room != null
                              ? 1
                              : c.customization.playbackRate,
                          onChanged: c.room != null || !available
                              ? null
                              : (value) => unawaited(
                                  c
                                      .customize({'playbackRate': value})
                                      .catchError(
                                        (Object error) =>
                                            c.tell(error.toString()),
                                      ),
                                ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 11),
                  Container(
                    key: const Key('compact-eq-chart'),
                    height: 166,
                    decoration: BoxDecoration(
                      color: v.accentSoft.withValues(alpha: .35),
                      border: Border.all(color: v.line),
                      borderRadius: BorderRadius.circular(v.corners(18)),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: LayoutBuilder(
                      builder: (context, constraints) => Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned.fill(
                            top: 7,
                            bottom: 21,
                            left: 22,
                            right: 0,
                            child: TweenAnimationBuilder<List<double>>(
                              tween: _BandsTween(end: eq.bands),
                              duration: v.duration((220 / v.speed).round()),
                              curve: Curves.easeOutCubic,
                              builder: (_, bands, _) => CustomPaint(
                                key: const Key('compact-eq-curve'),
                                painter: _EqualizerCurve(bands, v),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(left: 22),
                            child: Row(
                              children: [
                                for (var i = 0; i < 10; i++)
                                  Expanded(
                                    child: Column(
                                      children: [
                                        Expanded(
                                          child: RotatedBox(
                                            quarterTurns: 3,
                                            child: SliderTheme(
                                              data: SliderTheme.of(context)
                                                  .copyWith(
                                                    trackHeight: 1,
                                                    activeTrackColor:
                                                        Colors.transparent,
                                                    inactiveTrackColor:
                                                        Colors.transparent,
                                                    thumbShape:
                                                        const RoundSliderThumbShape(
                                                          enabledThumbRadius:
                                                              3.5,
                                                        ),
                                                    overlayShape:
                                                        SliderComponentShape
                                                            .noOverlay,
                                                    overlayColor:
                                                        Colors.transparent,
                                                    showValueIndicator:
                                                        ShowValueIndicator
                                                            .never,
                                                  ),
                                              child: Slider(
                                                key: Key('compact-eq-band-$i'),
                                                min: -12,
                                                max: 12,
                                                divisions: 48,
                                                value: eq.bands[i],
                                                label:
                                                    '${eq.bands[i].toStringAsFixed(1)} dB',
                                                semanticFormatterCallback:
                                                    (value) =>
                                                        '${equalizerFrequencies[i].round()} Hz, ${value.toStringAsFixed(1)} dB',
                                                onChanged:
                                                    available && eq.enabled
                                                    ? (value) => change({
                                                        'bands': [...eq.bands]
                                                          ..[i] = value,
                                                      })
                                                    : null,
                                              ),
                                            ),
                                          ),
                                        ),
                                        SizedBox(
                                          height: 22,
                                          child: Center(
                                            child: Text(
                                              equalizerFrequencies[i] >= 1000
                                                  ? '${(equalizerFrequencies[i] / 1000).round()}k'
                                                  : '${equalizerFrequencies[i].round()}',
                                              style: TextStyle(
                                                fontSize: 8,
                                                color: v.muted,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          // Keep the dB scale inside the rounded chart without
                          // overlapping the first frequency's thumb.
                          for (final axis in [
                            ('max', '+12', 31.0),
                            ('zero', '0', (constraints.maxHeight - 14) / 2),
                            ('min', '−12', constraints.maxHeight - 45),
                          ])
                            Positioned(
                              left: 0,
                              top: axis.$3 - 10,
                              width: 22,
                              height: 20,
                              child: IgnorePointer(
                                child: Center(
                                  child: Text(
                                    axis.$2,
                                    key: Key('compact-eq-db-${axis.$1}'),
                                    semanticsLabel: '${axis.$2} dB',
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: v.muted,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text(
                        wt('eq.preamp', context: context),
                        style: TextStyle(fontSize: 10, color: v.muted),
                      ),
                      Expanded(
                        child: Slider(
                          key: const Key('compact-eq-preamp'),
                          min: -12,
                          max: 12,
                          divisions: 48,
                          value: eq.preamp,
                          onChanged: available && eq.enabled
                              ? (value) => change({'preamp': value})
                              : null,
                        ),
                      ),
                      Text(
                        '${eq.preamp.toStringAsFixed(1)} dB',
                        style: TextStyle(
                          fontSize: 10,
                          color: v.muted,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  if (c.room != null || !available)
                    Text(
                      wt(
                        c.room != null ? 'eq.roomSpeed' : 'eq.waiting',
                        context: context,
                      ),
                      style: TextStyle(
                        fontSize: 10,
                        color: v.muted,
                        height: 1.4,
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

class _EqualizerCurve extends CustomPainter {
  final List<double> bands;
  final WaveVisuals v;
  _EqualizerCurve(this.bands, this.v);
  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = v.line
      ..strokeWidth = .6;
    for (var i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), pen);
    }
    for (var i = 0; i < 10; i++) {
      final x = size.width * (i + .5) / 10;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), pen);
    }
    final curve = Path();
    for (var i = 0; i < 10; i++) {
      final x = size.width * (i + .5) / 10,
          y = 24 + (size.height - 48) * (.5 - bands[i] / 24);
      if (i == 0) {
        curve.moveTo(x, y);
      } else {
        curve.lineTo(x, y);
      }
    }
    canvas.drawPath(
      curve,
      Paint()
        ..color = v.accent.withValues(alpha: .65)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(_EqualizerCurve old) =>
      old.bands != bands || old.v.accent != v.accent;
}

class _BandsTween extends Tween<List<double>> {
  _BandsTween({super.end});
  @override
  List<double> lerp(double t) =>
      List.generate(10, (i) => begin![i] + (end![i] - begin![i]) * t);
}

class _EqualizerPresetMenu extends StatefulWidget {
  final String selected;
  final bool saved, enabled;
  final ValueChanged<String> onSelected;
  const _EqualizerPresetMenu({
    required this.selected,
    required this.saved,
    required this.enabled,
    required this.onSelected,
  });
  @override
  State<_EqualizerPresetMenu> createState() => _EqualizerPresetMenuState();
}

class _EqualizerPresetMenuState extends State<_EqualizerPresetMenu> {
  bool keyboardFocus = false;
  final triggerFocus = FocusNode();
  final optionFocus = <String, FocusNode>{};
  @override
  void dispose() {
    triggerFocus.dispose();
    for (final node in optionFocus.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = waveVisuals(context),
        labels = <String, String>{
          for (final p in equalizerPresets.keys)
            p: EqualizerPanel._presetLabel(context, p),
          if (widget.saved)
            'saved': audioDesignText('savedPreset', context: context),
        };
    BorderSide focus(Set<WidgetState> states) => BorderSide(color: v.line);
    return Focus(
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent && !keyboardFocus) {
          setState(() => keyboardFocus = true);
        }
        return KeyEventResult.ignored;
      },
      child: Listener(
        onPointerDown: (_) {
          if (keyboardFocus) setState(() => keyboardFocus = false);
        },
        child: LayoutBuilder(
          builder: (context, box) => MenuAnchor(
            childFocusNode: triggerFocus,
            onOpen: () => WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                (optionFocus[widget.selected] ?? optionFocus[labels.keys.first])
                    ?.requestFocus();
              }
            }),
            style: MenuStyle(
              backgroundColor: WidgetStatePropertyAll(v.surface),
              surfaceTintColor: const WidgetStatePropertyAll(
                Colors.transparent,
              ),
              minimumSize: WidgetStatePropertyAll(Size(box.maxWidth, 0)),
              maximumSize: WidgetStatePropertyAll(Size(box.maxWidth, 300)),
              padding: const WidgetStatePropertyAll(EdgeInsets.all(5)),
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(v.corners(18)),
                  side: BorderSide(color: v.line),
                ),
              ),
            ),
            menuChildren: [
              for (final item in labels.entries)
                Focus(
                  onKeyEvent: (_, event) {
                    if (event is KeyDownEvent && !keyboardFocus) {
                      setState(() => keyboardFocus = true);
                    }
                    return KeyEventResult.ignored;
                  },
                  child: MenuItemButton(
                    key: Key('compact-eq-preset-${item.key}'),
                    focusNode: optionFocus.putIfAbsent(item.key, FocusNode.new),
                    style: ButtonStyle(
                      overlayColor: const WidgetStatePropertyAll(
                        Colors.transparent,
                      ),
                      backgroundColor: WidgetStateProperty.resolveWith(
                        (states) =>
                            states.contains(WidgetState.hovered) ||
                                states.contains(WidgetState.focused) &&
                                    keyboardFocus
                            ? v.line
                            : Colors.transparent,
                      ),
                      side: const WidgetStatePropertyAll(BorderSide.none),
                      shape: WidgetStatePropertyAll(
                        RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(v.corners(7)),
                        ),
                      ),
                      padding: const WidgetStatePropertyAll(
                        EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      ),
                      textStyle: WidgetStatePropertyAll(
                        Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontSize: 12,
                          color: v.ink,
                        ),
                      ),
                    ),
                    trailingIcon: item.key == widget.selected
                        ? Icon(Icons.check_rounded, size: 14, color: v.accent)
                        : null,
                    onPressed: () => widget.onSelected(item.key),
                    child: Text(
                      item.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
            ],
            builder: (context, menu, _) => OutlinedButton(
              key: const Key('compact-eq-presets'),
              focusNode: triggerFocus,
              style: ButtonStyle(
                overlayColor: const WidgetStatePropertyAll(Colors.transparent),
                backgroundColor: WidgetStateProperty.resolveWith(
                  (states) =>
                      states.contains(WidgetState.focused) && keyboardFocus
                      ? Color.alphaBlend(v.line, v.background)
                      : v.background,
                ),
                side: WidgetStateProperty.resolveWith(focus),
                shape: WidgetStatePropertyAll(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(v.corners(18)),
                  ),
                ),
                padding: const WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
                minimumSize: const WidgetStatePropertyAll(Size(0, 38)),
              ),
              onPressed: widget.enabled
                  ? () => menu.isOpen ? menu.close() : menu.open()
                  : null,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      labels[widget.selected] ??
                          wt('eq.curve', context: context),
                      style: TextStyle(color: v.ink, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
