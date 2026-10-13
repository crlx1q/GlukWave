import 'package:flutter/material.dart';
import '../core/controller.dart';
import 'motion_icons.dart';
import 'native19_strings.dart';
import 'widgets.dart';

/// Compact music destinations, rather than a second row of toolbar buttons.
class CollectionDestination extends StatelessWidget {
  final String title, subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final bool prominent;
  const CollectionDestination({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.prominent = false,
  });
  @override
  Widget build(BuildContext context) {
    final v = waveVisuals(context);
    return WavePress(
      child: Material(
        color: prominent ? v.accentSoft : v.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(v.corners(19)),
          side: BorderSide(color: v.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
            child: Row(
              children: [
                Container(
                  width: 43,
                  height: 43,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: v.background.withValues(alpha: .5),
                    borderRadius: BorderRadius.circular(v.corners(13)),
                  ),
                  child: WaveControlIcon(
                    icon,
                    size: 23,
                    color: prominent ? v.accent : v.ink,
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: v.muted,
                          fontSize: 11,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                WaveControlIcon(
                  Icons.chevron_right_rounded,
                  size: 17,
                  color: v.muted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class NativeEnergyPanel extends StatelessWidget {
  final WaveController controller;
  const NativeEnergyPanel({super.key, required this.controller});
  @override
  Widget build(BuildContext context) {
    final c = controller, v = waveVisuals(context);
    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              WaveControlIcon(Icons.battery_saver_outlined, color: v.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  nativeText(
                    context,
                    MediaQuery.sizeOf(context).width < 360
                        ? 'energyCompact'
                        : 'energy',
                  ),
                  key: const Key('energy-heading'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (c.energySaving)
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: v.accent,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            nativeText(context, 'energyDetail'),
            style: TextStyle(color: v.muted, fontSize: 12, height: 1.6),
          ),
          const SizedBox(height: 17),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final mode in ['auto', 'on', 'off'])
                ChoiceChip(
                  key: Key('energy-mode-$mode'),
                  label: Text(nativeText(context, mode)),
                  selected: c.energyMode == mode,
                  showCheckmark: false,
                  onSelected: (_) => c.setEnergyMode(mode),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class NativeOfflineNotice extends StatelessWidget {
  final VoidCallback onSaved, onRetry;
  const NativeOfflineNotice({
    super.key,
    required this.onSaved,
    required this.onRetry,
  });
  @override
  Widget build(BuildContext context) {
    final v = waveVisuals(context);
    return Material(
      color: v.accentSoft.withValues(alpha: .6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            WaveControlIcon(Icons.wifi_off_rounded, size: 17, color: v.muted),
            const SizedBox(width: 10),
            Expanded(
              child: InkWell(
                onTap: onSaved,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nativeText(context, 'offline'),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      nativeText(context, 'offlineDetail'),
                      style: TextStyle(fontSize: 10, color: v.muted),
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              key: const Key('offline-retry'),
              tooltip: nativeText(context, 'reconnect'),
              onPressed: onRetry,
              icon: const WaveControlIcon(Icons.refresh_rounded, size: 19),
            ),
          ],
        ),
      ),
    );
  }
}
