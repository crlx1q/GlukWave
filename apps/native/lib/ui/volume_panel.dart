import 'package:flutter/material.dart';
import '../core/controller.dart';
import '../l10n/wave_localizations.dart';
import 'widgets.dart';
import 'volume_slider.dart';

Future<void> showWaveVolume(BuildContext context, WaveController c) =>
    showWaveDialog<void>(
      context: context,
      builder: (_) => WaveVolumePanel(controller: c),
    );

class WaveVolumePanel extends StatelessWidget {
  final WaveController controller;
  const WaveVolumePanel({super.key, required this.controller});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (_, child) {
      final c = controller, v = waveVisuals(context);
      return Dialog(
        key: const Key('wave-volume-panel'),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        backgroundColor: v.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(v.corners(18)),
          side: BorderSide(color: v.line),
        ),
        child: ConstrainedBox(
          key: const Key('volume-panel-surface'),
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.volume_up_outlined, size: 19, color: v.accent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        wt('native.621777004a', context: context),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).closeButtonLabel,
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded, size: 19),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        c.activeDeviceName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.5,
                          color: v.muted,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${(c.audio.volume * 100).round()}%',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: v.ink,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                VolumeSlider(
                  key: const Key('expanded-volume-slider'),
                  scope: c.controlScope,
                  onPreview: c.previewVolume,
                  onCancel: c.cancelVolumeEdit,
                  value: c.audio.volume.clamp(0, 1),
                  onChanged: (value) async {
                    try {
                      await c.transport('volume', {'volume': value});
                    } catch (error) {
                      c.tell(error.toString());
                    }
                  },
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final label in ['0', '50', '100%'])
                      Text(
                        label,
                        style: TextStyle(fontSize: 10, color: v.muted),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
