import 'dart:async';
import 'package:flutter/material.dart';
import '../core/controller.dart';
import '../core/equalizer.dart';
import '../core/models.dart';
import '../l10n/wave_localizations.dart';
import 'widgets.dart';

class EqualizerPanel extends StatelessWidget {
  final WaveController controller;
  const EqualizerPanel({super.key, required this.controller});
  @override
  Widget build(BuildContext context) {
    final c = controller, v = waveVisuals(context), eq = c.customization.equalizer;
    void change(Json values) => unawaited(c.customize({'equalizer': values}).catchError((Object e) { c.tell(e.toString()); }));
    final status = !c.audio.equalizerSupported
        ? 'eq.unsupported'
        : c.audio.equalizerStatus == 'failed'
        ? 'eq.failed'
        : c.audio.equalizerStatus == 'ready'
        ? 'eq.hardware'
        : 'eq.waiting';
    return Surface(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SwitchListTile(
          key: const Key('equalizer-enabled'),
          contentPadding: EdgeInsets.zero,
          title: Text(wt('eq.title', context: context), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
          subtitle: Padding(padding: const EdgeInsets.only(top: 6), child: Text(wt(status, context: context,
              values: {'p0': c.audio.hardwareBandCount}), style: TextStyle(color: v.muted, height: 1.5, fontSize: 12))),
          value: eq.enabled,
          onChanged: c.audio.equalizerSupported ? (value) => change({'enabled': value}) : null,
        ),
        const SizedBox(height: 18),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final preset in equalizerPresets.entries)
            ActionChip(key: Key('equalizer-${preset.key}'), label: Text(_presetLabel(context, preset.key)),
                onPressed: () => change(preset.value.toJson())),
        ]),
        const SizedBox(height: 16),
        Text(wt('eq.curve', context: context), style: TextStyle(color: v.muted, fontSize: 11, height: 1.5)),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (var band = 0; band < equalizerFrequencies.length; band++)
              SizedBox(width: 54, child: Column(children: [
                Text('${eq.bands[band] > 0 ? '+' : ''}${eq.bands[band].toStringAsFixed(1)}',
                    style: TextStyle(color: v.muted, fontSize: 10)),
                SizedBox(height: 145, child: RotatedBox(quarterTurns: 3,
                  child: Slider(key: Key('equalizer-band-$band'), value: eq.bands[band], min: -12, max: 12, divisions: 48,
                    semanticFormatterCallback: (value) => '${equalizerFrequencies[band].round()} Hz, ${value.toStringAsFixed(1)} dB',
                    onChanged: (value) => change({'bands': [...eq.bands]..[band] = value}),
                  ),
                )),
                Text(equalizerFrequencies[band] >= 1000 ? '${(equalizerFrequencies[band] / 1000).round()}k' : '${equalizerFrequencies[band].round()}',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
              ])),
          ]),
        ),
        const Divider(height: 36),
        Row(children: [
          Expanded(child: Text(wt('eq.preamp', context: context), style: const TextStyle(fontWeight: FontWeight.w600))),
          Text('${eq.preamp.toStringAsFixed(1)} dB', style: TextStyle(color: v.muted, fontSize: 12)),
        ]),
        Slider(key: const Key('equalizer-preamp'), value: eq.preamp, min: -12, max: 12, divisions: 48,
            semanticFormatterCallback: (value) => '${value.toStringAsFixed(1)} dB', onChanged: (value) => change({'preamp': value})),
        const Divider(height: 32),
        Row(children: [
          Expanded(child: Text(wt('eq.speed', context: context), style: const TextStyle(fontWeight: FontWeight.w600))),
          Text('${c.room != null ? '1.00' : c.customization.playbackRate.toStringAsFixed(2)}×', style: TextStyle(color: v.muted, fontSize: 12)),
        ]),
        Slider(key: const Key('playback-rate'), min: .5, max: 2, divisions: 30,
          value: c.room != null ? 1 : c.customization.playbackRate,
          semanticFormatterCallback: (value) => '${value.toStringAsFixed(2)}×',
          onChanged: c.room != null ? null : (value) => unawaited(c.customize({'playbackRate': value}).catchError((Object e) { c.tell(e.toString()); }))),
        if (c.room != null) Text(wt('eq.roomSpeed', context: context), style: TextStyle(color: v.muted, fontSize: 12, height: 1.5)),
      ]),
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
