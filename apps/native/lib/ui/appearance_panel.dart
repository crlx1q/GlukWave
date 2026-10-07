import 'dart:async';
import 'package:flutter/material.dart';
import '../core/appearance.dart';
import '../services/appearance_store.dart';
import 'widgets.dart';
import 'theme_preview.dart';
import '../l10n/wave_localizations.dart';

Future<void> showAppearance(BuildContext context, AppearanceStore store) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: AppearancePanel(store: store),
      ),
    );

class AppearanceEntry extends StatelessWidget {
  final AppearanceStore store;
  const AppearanceEntry({super.key, required this.store});
  @override
  Widget build(BuildContext context) {
    final v = waveVisuals(context);
    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.palette_outlined, color: v.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  wt('native.90353a9d3d', context: context),
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                ),
              ),
              for (final color in [v.background, v.surface, v.ink, v.accent])
                Container(
                  width: 17,
                  height: 17,
                  margin: const EdgeInsets.only(left: 4),
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(color: v.line),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            wt('native.8ec35b8339', context: context),
            style: TextStyle(color: v.muted, height: 1.6, fontSize: 12),
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            key: const Key('open-appearance'),
            onPressed: () => showAppearance(context, store),
            icon: const Icon(Icons.tune_rounded, size: 18),
            label: Text(wt('native.2691b463f8', context: context)),
          ),
        ],
      ),
    );
  }
}

class AppearancePanel extends StatefulWidget {
  final AppearanceStore store;
  const AppearancePanel({super.key, required this.store});
  @override
  State<AppearancePanel> createState() => _AppearancePanelState();
}

class _AppearancePanelState extends State<AppearancePanel> {
  static const swatches = [
    '#a08369',
    '#b1a2de',
    '#9bb99a',
    '#7ca8bb',
    '#d2939c',
    '#dbb976',
    '#df9978',
  ];
  String? editing;
  void change(Map<String, dynamic> patch) {
    unawaited(widget.store.change(patch));
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.store,
    builder: (context, child) {
      final state = widget.store.current;
      final brightness = switch (state.theme) {
        'dark' => Brightness.dark,
        'system' => MediaQuery.platformBrightnessOf(context),
        _ => Brightness.light,
      };
      // Modal routes capture their opening theme. This panel follows the live
      // selection as well, so a dark/light switch is visible before it closes.
      return Theme(
        data: buildWaveTheme(state, brightness),
        child: Builder(builder: (context) => panel(context, state, brightness)),
      );
    },
  );

  Widget panel(
    BuildContext context,
    WaveCustomization state,
    Brightness brightness,
  ) {
    final v = waveVisuals(context), appearance = state.appearance;
    final mode = editing ?? (brightness == Brightness.dark ? 'dark' : 'light');
    final palette = mode == 'dark' ? appearance.dark : appearance.light;
    void appearanceChange(String key, dynamic value) => change({
      'appearance': {key: value},
    });
    void colorChange(String key, String value) => change({
      'appearance': {
        mode: {key: value},
      },
    });
    final available =
        MediaQuery.sizeOf(context).height -
        MediaQuery.viewInsetsOf(context).bottom -
        MediaQuery.paddingOf(context).top;
    return SizedBox(
      height: (available * .92).clamp(240.0, 850.0),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Material(
            color: v.background,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(v.radius),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 15, 12, 10),
                  child: Row(
                    children: [
                      Icon(Icons.palette_outlined, color: v.accent, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          wt('native.d206f1bed0', context: context),
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: wt('native.387f1c0b62', context: context),
                        onPressed: () => Navigator.maybePop(context),
                        icon: const Icon(Icons.close_rounded, size: 20),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    key: const Key('appearance-scroll'),
                    padding: EdgeInsets.fromLTRB(
                      v.compact ? 16 : 22,
                      0,
                      v.compact ? 16 : 22,
                      18,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DropdownButtonFormField<String>(
                          key: const Key('language-selector'),
                          initialValue: state.language,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: wt('language.title', context: context),
                            prefixIcon: const Icon(Icons.language_rounded),
                          ),
                          items: [
                            DropdownMenuItem(
                              value: 'auto',
                              child: Text(
                                wt('language.auto', context: context),
                              ),
                            ),
                            for (final language in languageNames.entries)
                              DropdownMenuItem(
                                value: language.key,
                                child: Text(language.value),
                              ),
                          ],
                          onChanged: (value) {
                            if (value != null) change({'language': value});
                          },
                        ),
                        const SizedBox(height: 7),
                        Text(
                          wt('language.hint', context: context),
                          style: TextStyle(
                            color: v.muted,
                            fontSize: 11,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 22),
                        Text(
                          wt('native.09e4ba36d6', context: context),
                          style: TextStyle(color: v.muted, fontSize: 12),
                        ),
                        const SizedBox(height: 18),
                        Wrap(
                          spacing: 7,
                          runSpacing: 7,
                          children: [
                            for (final item in {
                              'light': wt(
                                'native.8080010c5e',
                                context: context,
                              ),
                              'dark': wt('native.bd16b23470', context: context),
                              'system': wt(
                                'native.afeb19400d',
                                context: context,
                              ),
                            }.entries)
                              ThemePreview(
                                key: Key('theme-${item.key}'),
                                label: item.value,
                                selected: state.theme == item.key,
                                palette: item.key == 'dark'
                                    ? appearance.dark
                                    : appearance.light,
                                icon: item.key == 'dark'
                                    ? Icons.nightlight_outlined
                                    : item.key == 'system'
                                    ? Icons.brightness_auto_outlined
                                    : Icons.light_mode_outlined,
                                onTap: () => change({'theme': item.key}),
                              ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Surface(
                          padding: const EdgeInsets.all(15),
                          child: Row(
                            children: [
                              Container(
                                width: v.compact ? 40 : 48,
                                height: v.compact ? 40 : 48,
                                decoration: BoxDecoration(
                                  color: v.accentSoft,
                                  borderRadius: BorderRadius.circular(
                                    v.corners(13),
                                  ),
                                ),
                                child: Icon(
                                  Icons.graphic_eq_rounded,
                                  color: v.accent,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      wt('native.5a187c8ad3', context: context),
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      wt('native.d3b55f5ca6', context: context),
                                      style: TextStyle(
                                        color: v.muted,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.favorite_rounded,
                                color: v.accent,
                                size: 21,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 22),
                        Text(
                          wt('native.7d4c797c67', context: context),
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          wt('native.ed80bb3e14', context: context),
                          style: TextStyle(
                            color: v.muted,
                            fontSize: 11,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          children: [
                            for (final item in {
                              'light': wt(
                                'native.06bd854145',
                                context: context,
                              ),
                              'dark': wt('native.0f3b835082', context: context),
                            }.entries)
                              ChoiceChip(
                                key: Key('palette-${item.key}'),
                                selected: mode == item.key,
                                label: Text(item.value),
                                onSelected: (_) =>
                                    setState(() => editing = item.key),
                              ),
                          ],
                        ),
                        const SizedBox(height: 17),
                        Text(
                          wt('native.2dd965ee95', context: context),
                          style: TextStyle(color: v.muted, fontSize: 11),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            for (final hex in swatches)
                              Semantics(
                                label: wt(
                                  'native.fed5befeb5',
                                  values: {'p0': (hex)},
                                  context: context,
                                ),
                                selected: palette.accent == hex,
                                button: true,
                                child: Tooltip(
                                  message: hex,
                                  child: InkResponse(
                                    key: Key('accent-$hex'),
                                    radius: 24,
                                    onTap: () => colorChange('accent', hex),
                                    child: Container(
                                      width: 32,
                                      height: 32,
                                      decoration: BoxDecoration(
                                        color: hexColor(hex),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: palette.accent == hex
                                              ? v.ink
                                              : v.line,
                                          width: palette.accent == hex
                                              ? 2.5
                                              : 1,
                                        ),
                                      ),
                                      child: palette.accent == hex
                                          ? Icon(
                                              Icons.check_rounded,
                                              size: 16,
                                              color:
                                                  hexColor(
                                                        hex,
                                                      ).computeLuminance() >
                                                      .4
                                                  ? Colors.black87
                                                  : Colors.white,
                                            )
                                          : null,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _ColorEditor(
                          key: ValueKey('accent-editor-$mode'),
                          label: wt('native.984126b8b7', context: context),
                          value: palette.accent,
                          onChanged: (hex) => colorChange('accent', hex),
                        ),
                        const SizedBox(height: 6),
                        ExpansionTile(
                          key: const Key('all-colors'),
                          tilePadding: EdgeInsets.zero,
                          childrenPadding: const EdgeInsets.only(bottom: 10),
                          title: Text(
                            wt('native.9cbcd3b318', context: context),
                            style: TextStyle(fontSize: 13),
                          ),
                          subtitle: Text(
                            wt('native.64e081e829', context: context),
                            style: TextStyle(color: v.muted, fontSize: 10),
                          ),
                          children: [
                            for (final item in {
                              'bg': (
                                wt('native.b59390bb25', context: context),
                                palette.bg,
                              ),
                              'surface': (
                                wt('native.4ab17a04f4', context: context),
                                palette.surface,
                              ),
                              'ink': (
                                wt('native.93970437e2', context: context),
                                palette.ink,
                              ),
                            }.entries)
                              Padding(
                                padding: const EdgeInsets.only(top: 9),
                                child: _ColorEditor(
                                  key: ValueKey('${item.key}-editor-$mode'),
                                  label: item.value.$1,
                                  value: item.value.$2,
                                  onChanged: (hex) =>
                                      colorChange(item.key, hex),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _slider(
                          context,
                          wt('native.99204a3cf5', context: context),
                          '${appearance.radius.round()} px',
                          appearance.radius,
                          8,
                          38,
                          30,
                          (n) => appearanceChange('radius', n),
                          'radius-slider',
                        ),
                        _slider(
                          context,
                          wt('native.7831d42ea5', context: context),
                          '${localizedNumber(appearance.speed, decimalDigits: 1, context: context)}×',
                          appearance.speed,
                          .3,
                          2,
                          17,
                          (n) => appearanceChange('speed', n),
                          'speed-slider',
                        ),
                        const SizedBox(height: 5),
                        _toggle(
                          context,
                          wt('native.830603aad3', context: context),
                          wt('native.60efac2834', context: context),
                          !state.reducedMotion,
                          (enabled) => change({'reducedMotion': !enabled}),
                          'motion-toggle',
                        ),
                        _toggle(
                          context,
                          wt('native.666e0f796a', context: context),
                          wt('native.007c5fcecf', context: context),
                          appearance.blur,
                          (n) => appearanceChange('blur', n),
                          'blur-toggle',
                        ),
                        _toggle(
                          context,
                          wt('native.bff051ace0', context: context),
                          wt('native.f770c17775', context: context),
                          appearance.compact,
                          (n) => appearanceChange('compact', n),
                          'compact-toggle',
                        ),
                        _toggle(
                          context,
                          wt('native.2988f5fbfc', context: context),
                          wt('native.5c948d22d9', context: context),
                          appearance.cover3d,
                          (n) => appearanceChange('cover3d', n),
                          'cover3d-toggle',
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          children: [
                            for (final item in {
                              'vinyl': wt(
                                'native.8c021dafec',
                                context: context,
                              ),
                              'cd': 'CD',
                            }.entries)
                              ChoiceChip(
                                key: Key('cover-${item.key}'),
                                selected: appearance.coverKind == item.key,
                                label: Text(item.value),
                                onSelected: (_) =>
                                    appearanceChange('coverKind', item.key),
                              ),
                          ],
                        ),
                        const SizedBox(height: 17),
                        Text(
                          wt('native.2aa64630e3', context: context),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 9),
                        Wrap(
                          spacing: 8,
                          children: [
                            for (final item in {
                              'silk': wt('native.064f067d84', context: context),
                              'particles': wt(
                                'native.e6d802e5aa',
                                context: context,
                              ),
                              'bloom': 'Bloom',
                            }.entries)
                              ChoiceChip(
                                key: Key('wave-${item.key}'),
                                selected: appearance.waveStyle == item.key,
                                label: Text(item.value),
                                onSelected: (_) =>
                                    appearanceChange('waveStyle', item.key),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Uses the same painter as the home screen, not a separate
                        // illustrative approximation of the selected wave style.
                        ClipRRect(
                          borderRadius: BorderRadius.circular(v.corners(16)),
                          child: ColoredBox(
                            color: v.player,
                            child: SizedBox(
                              height: 76,
                              width: double.infinity,
                              child: RepaintBoundary(
                                child: CustomPaint(
                                  painter: WavePainter(
                                    .3,
                                    accentColor: v.accent,
                                    style: appearance.waveStyle,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        TextButton.icon(
                          key: const Key('reset-appearance'),
                          onPressed: () => change(state.resetPalette(mode)),
                          icon: const Icon(Icons.restart_alt_rounded, size: 18),
                          label: Text(
                            wt(
                              'native.ebcd6e8521',
                              values: {
                                'p0': (mode == 'dark'
                                    ? wt('native.b8c9d2cd6f', context: context)
                                    : wt(
                                        'native.eb5820813d',
                                        context: context,
                                      )),
                              },
                              context: context,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              widget.store.pending
                                  ? Icons.cloud_upload_outlined
                                  : widget.store.authenticated
                                  ? Icons.cloud_done_outlined
                                  : Icons.phone_android_rounded,
                              size: 16,
                              color: v.muted,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                widget.store.lastError != null
                                    ? wt('native.5cc6512b7e', context: context)
                                    : widget.store.pending
                                    ? wt('native.ef6585b509', context: context)
                                    : widget.store.authenticated
                                    ? wt('native.456801dbda', context: context)
                                    : wt('native.1f17fc01da', context: context),
                                style: TextStyle(
                                  color: v.muted,
                                  height: 1.5,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                            if (widget.store.pending)
                              IconButton(
                                tooltip: wt(
                                  'native.bb18fa6d01',
                                  context: context,
                                ),
                                onPressed: () =>
                                    unawaited(widget.store.flush()),
                                icon: const Icon(
                                  Icons.refresh_rounded,
                                  size: 17,
                                ),
                              ),
                          ],
                        ),
                        SizedBox(
                          height: MediaQuery.paddingOf(context).bottom + 4,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _slider(
    BuildContext context,
    String title,
    String value,
    double position,
    double min,
    double max,
    int divisions,
    ValueChanged<double> onChanged,
    String key,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ),
            Text(
              value,
              style: TextStyle(color: waveVisuals(context).muted, fontSize: 12),
            ),
          ],
        ),
        Slider(
          key: Key(key),
          value: position,
          min: min,
          max: max,
          divisions: divisions,
          label: value,
          onChanged: onChanged,
        ),
      ],
    ),
  );

  Widget _toggle(
    BuildContext context,
    String title,
    String subtitle,
    bool enabled,
    ValueChanged<bool> onChanged,
    String key,
  ) => Row(
    children: [
      Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: TextStyle(
                  color: waveVisuals(context).muted,
                  fontSize: 10,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(width: 8),
      Switch(key: Key(key), value: enabled, onChanged: onChanged),
    ],
  );
}

class _ColorEditor extends StatefulWidget {
  final String label, value;
  final ValueChanged<String> onChanged;
  const _ColorEditor({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });
  @override
  State<_ColorEditor> createState() => _ColorEditorState();
}

class _ColorEditorState extends State<_ColorEditor> {
  late final text = TextEditingController(text: widget.value);
  final focus = FocusNode();
  String? error;
  @override
  void didUpdateWidget(_ColorEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && !focus.hasFocus) {
      text.text = widget.value;
    }
  }

  void submit(String value) {
    try {
      final hex = normalizeHex(value);
      setState(() => error = null);
      text.text = hex;
      widget.onChanged(hex);
    } on FormatException {
      setState(() => error = wt('native.dd0ee1385e', context: context));
    }
  }

  @override
  void dispose() {
    text.dispose();
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: text,
    focusNode: focus,
    autocorrect: false,
    enableSuggestions: false,
    maxLength: 7,
    decoration: InputDecoration(
      labelText: widget.label,
      errorText: error,
      counterText: '',
      prefixIcon: Padding(
        padding: const EdgeInsets.all(13),
        child: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: hexColor(widget.value),
            shape: BoxShape.circle,
            border: Border.all(color: waveVisuals(context).line),
          ),
        ),
      ),
      suffixIcon: IconButton(
        tooltip: wt('native.405576c78f', context: context),
        onPressed: () => submit(text.text),
        icon: const Icon(Icons.check_rounded, size: 19),
      ),
    ),
    onSubmitted: submit,
    onChanged: (value) {
      if (RegExp(r'^#?[0-9a-fA-F]{6}$').hasMatch(value)) {
        setState(() => error = null);
        widget.onChanged(normalizeHex(value));
      }
    },
  );
}
