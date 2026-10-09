import 'motion_icons.dart';
import 'package:flutter/material.dart';
import '../core/controller.dart';
import '../core/models.dart';
import '../l10n/wave_localizations.dart';
import 'widgets.dart';
import 'volume_slider.dart';
import 'device_labels.dart';

String installationId(Json device) =>
    (device['deviceId'] ?? device['id'] ?? '').toString();

class ConnectPanel extends StatelessWidget {
  final WaveController controller;
  final Future<void> Function() scanQr, discover;
  const ConnectPanel({
    super.key,
    required this.controller,
    required this.scanQr,
    required this.discover,
  });
  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      controller.tell(error.toString());
    }
  }

  Future<void> _remove(BuildContext context, Json device) async {
    final c = controller;
    final confirmed = await showWaveDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(wt('connect.remove', context: dialog)),
        content: Text(
          wt(
            'connect.removeConfirm',
            values: {'name': device['name'] ?? ''},
            context: dialog,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: Text(wt('native.0ec753be8d', context: dialog)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(wt('connect.remove', context: dialog)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _run(() => c.revokeDevice(installationId(device)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = controller, v = waveVisuals(context), track = c.audio.viewCurrent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeading(
          wt('native.fec96a4982', context: context),
          wt('connect.description', context: context),
          eyebrow: 'GLUKWAVE CONNECT',
        ),
        Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                key: const Key('connect-independent'),
                contentPadding: EdgeInsets.zero,
                title: Text(
                  wt('connect.independent', context: context),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    wt('connect.independentHint', context: context),
                    style: TextStyle(fontSize: 12, height: 1.5, color: v.muted),
                  ),
                ),
                value: c.independentListening,
                onChanged: c.online && !c.connectChanging
                    ? (value) => _run(() => c.setIndependentListening(value))
                    : null,
              ),
              if (track != null) ...[
                const Divider(height: 30),
                Row(
                  children: [
                    Artwork(
                      controller: c,
                      url: track.artwork,
                      size: 56,
                      radius: 12,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            c.outputLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: v.accent, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    IconButton.filled(
                      style: IconButton.styleFrom(
                        backgroundColor: v.ink,
                        foregroundColor: v.background,
                      ),
                      onPressed: c.room != null && !c.canTogglePlayback
                          ? null
                          : () => _run(
                              c.audio.playing ? c.audio.pause : c.audio.play,
                            ),
                      tooltip: wt(
                        c.audio.playing
                            ? 'native.03498e395a'
                            : 'native.c750dc7d94',
                        context: context,
                      ),
                      icon: WavePlayPauseIcon(
                        playing: c.audio.playing,
                        color: v.background,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    WaveToggleIcon(
                      active: c.audio.volume == 0,
                      activeIcon: Icons.volume_off_outlined,
                      inactiveIcon: Icons.volume_up_outlined,
                      size: 18,
                      color: v.muted,
                    ),
                    Expanded(
                      child: VolumeSlider(
                        value: c.audio.volume,
                        onChanged:
                            c.activeDeviceId == null && !c.independentListening
                            ? null
                            : (value) => _run(
                                () => c.transport('volume', {'volume': value}),
                              ),
                      ),
                    ),
                  ],
                ),
                if (c.room != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        Icon(
                          Icons.headphones_rounded,
                          size: 16,
                          color: v.muted,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            c.room!['name']?.toString() ?? '',
                            style: TextStyle(color: v.muted, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (c.controllingRemote || c.room != null && !c.outputHere)
                  OutlinedButton.icon(
                    key: const Key('connect-play-here'),
                    onPressed: c.connected && c.pendingDeviceActions.isEmpty
                        ? () => _run(c.listenHere)
                        : null,
                    icon: const Icon(Icons.speaker_outlined, size: 18),
                    label: Text(wt('connect.playHere', context: context)),
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: Text(
                wt('connect.installations', context: context),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                ),
              ),
            ),
            IconButton(
              onPressed: c.online ? () => _run(c.refreshDevices) : null,
              tooltip: wt('devices.refresh', context: context),
              icon: const Icon(Icons.refresh_rounded, size: 20),
            ),
          ],
        ),
        const SizedBox(height: 10),
        for (final device in c.devices)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(17),
            decoration: BoxDecoration(
              color: v.surface,
              border: Border.all(
                color: installationId(device) == c.activeDeviceId
                    ? v.accent
                    : v.line,
              ),
              borderRadius: BorderRadius.circular(waveRadius(context, 15)),
            ),
            child: Row(
              children: [
                Icon(deviceKindIcon(device), size: 26, color: v.muted),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device['name']?.toString() ?? c.deviceName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${deviceKindLabel(device, context: context)} · ${installationId(device) == c.deviceId ? wt('native.4eca465a4a', context: context) : wt(device['online'] == true ? 'native.011e2099f2' : 'native.67b99cc9bf', context: context)}',
                        style: TextStyle(fontSize: 12, color: v.muted),
                      ),
                      if (installationId(device) == c.activeDeviceId)
                        Padding(
                          padding: const EdgeInsets.only(top: 7),
                          child: Row(
                            children: [
                              Icon(
                                c.audio.playing
                                    ? Icons.graphic_eq_rounded
                                    : Icons.pause_rounded,
                                size: 15,
                                color: v.accent,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  wt(
                                    c.audio.playing
                                        ? 'devices.activeOutput'
                                        : 'devices.selectedOutput',
                                    context: context,
                                  ),
                                  style: TextStyle(
                                    color: v.accent,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (device['sessions'] is num)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            wt(
                              'devices.sessionsCount',
                              values: {'count': device['sessions']},
                              context: context,
                            ),
                            style: TextStyle(color: v.muted, fontSize: 11),
                          ),
                        ),
                    ],
                  ),
                ),
                if (track != null &&
                    device['online'] == true &&
                    (installationId(device) != c.activeDeviceId ||
                        installationId(device) == c.deviceId &&
                            c.controllingRemote))
                  IconButton(
                    tooltip: wt('native.49daba7f72', context: context),
                    onPressed: c.pendingDeviceActions.isNotEmpty
                        ? null
                        : () => _run(
                            () => c.transfer(
                              installationId(device),
                              targetSurfaceId:
                                  installationId(device) == c.deviceId
                                  ? c.surfaceId
                                  : device['surfaceId']?.toString(),
                            ),
                          ),
                    icon:
                        c.pendingDeviceActions.contains(
                          'transfer:${installationId(device)}',
                        )
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            Icons.speaker_outlined,
                            size: 20,
                            color: v.accent,
                          ),
                  ),
                IconButton(
                  key: Key('connect-remove-${installationId(device)}'),
                  tooltip: wt('connect.remove', context: context),
                  onPressed: !c.online || c.pendingDeviceActions.isNotEmpty
                      ? null
                      : () => _remove(context, device),
                  icon:
                      c.pendingDeviceActions.contains(
                        'revoke:${installationId(device)}',
                      )
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(Icons.logout_rounded, size: 18, color: v.muted),
                ),
              ],
            ),
          ),
        if (c.devices.isEmpty)
          EmptyState(
            wt('native.76bdd0e417', context: context),
            wt('native.bf9b9e0034', context: context),
            icon: Icons.devices_rounded,
          ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            TextButton.icon(
              onPressed: scanQr,
              icon: const Icon(Icons.qr_code_scanner_rounded),
              label: Text(wt('native.280e0f673d', context: context)),
            ),
            TextButton.icon(
              onPressed: discover,
              icon: const Icon(Icons.wifi_find_rounded),
              label: Text(wt('native.8db44b4616', context: context)),
            ),
          ],
        ),
      ],
    );
  }
}
