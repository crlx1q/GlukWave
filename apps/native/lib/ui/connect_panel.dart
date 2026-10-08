import 'package:flutter/material.dart';
import '../core/controller.dart';
import '../core/models.dart';
import '../l10n/wave_localizations.dart';
import 'widgets.dart';
import 'volume_slider.dart';

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
                onChanged: c.online
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
                            c.controllingRemote
                                ? wt(
                                    'connect.playingOn',
                                    values: {'name': c.activeDeviceName},
                                    context: context,
                                  )
                                : c.deviceName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: v.accent, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    IconButton.filled(
                      style: IconButton.styleFrom(
                        backgroundColor: v.ink,
                        foregroundColor: v.background,
                      ),
                      onPressed: () =>
                          _run(c.audio.playing ? c.audio.pause : c.audio.play),
                      tooltip: wt(
                        c.audio.playing
                            ? 'native.03498e395a'
                            : 'native.c750dc7d94',
                        context: context,
                      ),
                      icon: Icon(
                        c.audio.playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: v.background,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Icon(Icons.volume_up_outlined, size: 18, color: v.muted),
                    Expanded(
                      child: VolumeSlider(
                        value: c.audio.volume,
                        onChanged: (value) => _run(
                          () => c.transport('volume', {'volume': value}),
                        ),
                      ),
                    ),
                  ],
                ),
                if (c.controllingRemote)
                  OutlinedButton.icon(
                    key: const Key('connect-play-here'),
                    onPressed: c.connected
                        ? () => _run(
                            () => c.transfer(
                              c.deviceId,
                              targetSurfaceId: c.surfaceId,
                            ),
                          )
                        : null,
                    icon: const Icon(Icons.speaker_outlined, size: 18),
                    label: Text(wt('connect.playHere', context: context)),
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text(
          wt('connect.installations', context: context),
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
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
                Icon(
                  ['android', 'ios'].contains(device['kind'])
                      ? Icons.smartphone_rounded
                      : device['kind'] == 'web'
                      ? Icons.language_rounded
                      : Icons.computer_outlined,
                  size: 26,
                  color: v.muted,
                ),
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
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        installationId(device) == c.deviceId
                            ? wt('native.4eca465a4a', context: context)
                            : wt(
                                device['online'] == true
                                    ? 'native.011e2099f2'
                                    : 'native.67b99cc9bf',
                                context: context,
                              ),
                        style: TextStyle(fontSize: 10, color: v.muted),
                      ),
                    ],
                  ),
                ),
                if (track != null &&
                    device['online'] == true &&
                    installationId(device) != c.activeDeviceId)
                  IconButton(
                    tooltip: wt('native.49daba7f72', context: context),
                    onPressed: () => _run(
                      () => c.transfer(
                        installationId(device),
                        targetSurfaceId: device['surfaceId']?.toString(),
                      ),
                    ),
                    icon: Icon(
                      Icons.speaker_outlined,
                      size: 20,
                      color: v.accent,
                    ),
                  ),
                IconButton(
                  key: Key('connect-remove-${installationId(device)}'),
                  tooltip: wt('connect.remove', context: context),
                  onPressed: () => _remove(context, device),
                  icon: Icon(Icons.logout_rounded, size: 18, color: v.muted),
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
