import 'lan_panel.dart';
import 'motion_icons.dart';
import 'package:flutter/material.dart';
import '../core/controller.dart';
import '../core/models.dart';
import '../l10n/wave_localizations.dart';
import '../l10n/ecosystem_polish_strings.dart';
import 'widgets.dart';
import 'listening_presence.dart';
import 'connect_device_tile.dart';

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
                onChanged: c.online && !c.connectChanging && !c.lanEnabled
                    ? (value) => _run(() => c.setIndependentListening(value))
                    : null,
              ),
              if (c.backgroundConnect.supported) ...[
                Divider(height: 26, color: v.line),
                SwitchListTile(
                  key: const Key('connect-screen-off'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    ecosystemText('connectScreenOff', context),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      ecosystemText('connectScreenOffHint', context),
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.5,
                        color: v.muted,
                      ),
                    ),
                  ),
                  value: c.backgroundConnectEnabled,
                  onChanged: (enabled) =>
                      _run(() => c.setBackgroundConnect(enabled)),
                ),
              ],
              if (track != null && (c.room != null || c.controllingRemote)) ...[
                const Divider(height: 30),
                if (c.room != null) ListeningPresence(controller: c),
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
        for (final device
            in ([...c.devices]..sort(
              (a, b) =>
                  ((installationId(b) == c.activeDeviceId ? 2 : 0) +
                          (b['online'] == true ? 1 : 0))
                      .compareTo(
                        (installationId(a) == c.activeDeviceId ? 2 : 0) +
                            (a['online'] == true ? 1 : 0),
                      ),
            )))
          ConnectDeviceTile(
            controller: c,
            device: device,
            onRemove: () => _remove(context, device),
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
              icon: const WaveControlIcon(Icons.qr_code_scanner_rounded),
              label: Text(wt('native.280e0f673d', context: context)),
            ),
            TextButton.icon(
              onPressed: discover,
              icon: const Icon(Icons.wifi_find_rounded),
              label: Text(wt('native.8db44b4616', context: context)),
            ),
          ],
        ),
        const SizedBox(height: 24),
        LanPanel(controller: c, scanQr: scanQr),
      ],
    );
  }
}
