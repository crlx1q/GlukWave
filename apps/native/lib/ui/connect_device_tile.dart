import 'package:flutter/material.dart';
import '../core/controller.dart';
import '../core/models.dart';
import '../l10n/wave_localizations.dart';
import '../l10n/ecosystem_polish_strings.dart';
import 'widgets.dart';
import 'device_labels.dart';

String connectDeviceId(Json device) =>
    (device['deviceId'] ?? device['id'] ?? '').toString();

/// One device, its confirmed state and one transfer action. Main transport stays in the player.
class ConnectDeviceTile extends StatelessWidget {
  final WaveController controller;
  final Json device;
  final bool compact, lan;
  final VoidCallback? onRemove;
  const ConnectDeviceTile({
    super.key,
    required this.controller,
    required this.device,
    this.compact = false,
    this.lan = false,
    this.onRemove,
  });
  Future<void> _transfer() async {
    final c = controller, id = connectDeviceId(device);
    try {
      final transfer = lan ? c.transfer : c.transferCloud;
      await transfer(
        id,
        targetSurfaceId: id == c.deviceId
            ? c.surfaceId
            : device['surfaceId']?.toString(),
      );
    } catch (error) {
      c.tell(error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = controller,
        v = waveVisuals(context),
        id = connectDeviceId(device),
        state = object(device['state']);
    final active = id == (lan ? c.activeDeviceId : c.connect['activeDeviceId']),
        local = id == c.deviceId,
        online = device['online'] == true;
    final pending = c.transferPending == id, own = c.audio.viewCurrent;
    final snapshot = object(device['track']);
    final useOwn =
        local && c.outputHere && (lan ? c.lanEnabled : !c.lanEnabled);
    final WaveTrack? track = useOwn
        ? own
        : snapshot['id'] != null
        ? WaveTrack(snapshot)
        : c.tracks.where((t) => t.id == state['trackId']).firstOrNull;
    final playing =
        online && (useOwn ? c.audio.playing : state['playing'] == true);
    return Container(
      key: Key('connect-device-$id'),
      margin: EdgeInsets.only(bottom: compact ? 0 : 9),
      padding: EdgeInsets.symmetric(
        vertical: compact ? 13 : 15,
        horizontal: compact ? 2 : 15,
      ),
      decoration: BoxDecoration(
        color: compact
            ? Colors.transparent
            : active
            ? v.accentSoft.withValues(alpha: .22)
            : v.surface,
        border: compact
            ? Border(bottom: BorderSide(color: v.line))
            : Border.all(
                color: active ? v.accent.withValues(alpha: .45) : v.line,
              ),
        borderRadius: compact ? null : BorderRadius.circular(v.corners(17)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              DevicePlatformIcon(
                device: device,
                size: 22,
                color: active ? v.accent : v.muted,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device['name']?.toString() ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: online ? v.ink : v.muted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: online
                                ? v.accent
                                : v.muted.withValues(alpha: .5),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            pending
                                ? ecosystemText('waiting', context)
                                : '${active ? ecosystemText('selectedOutput', context) : wt(online ? 'native.011e2099f2' : 'native.67b99cc9bf', context: context)}${local ? ' · ${wt('native.4eca465a4a', context: context)}' : ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              color: active ? v.accent : v.muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 5),
              if (active && !(local && c.controllingRemote))
                Icon(Icons.check_rounded, size: 18, color: v.accent)
              else
                IconButton(
                  key: Key('connect-transfer-$id'),
                  onPressed:
                      online &&
                          own != null &&
                          c.transferPending == null &&
                          (lan ? c.lanEnabled : c.connected)
                      ? _transfer
                      : null,
                  tooltip: wt('native.49daba7f72', context: context),
                  icon: pending
                      ? const SizedBox(
                          width: 17,
                          height: 17,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          Icons.arrow_forward_rounded,
                          size: 18,
                          color: online ? v.ink : v.muted,
                        ),
                  style: IconButton.styleFrom(
                    side: BorderSide(color: v.line),
                    minimumSize: const Size(38, 38),
                    maximumSize: const Size(38, 38),
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(v.corners(11)),
                    ),
                  ),
                ),
              if (onRemove != null)
                IconButton(
                  key: Key('connect-remove-$id'),
                  tooltip: wt('connect.remove', context: context),
                  onPressed: !c.online || c.pendingDeviceActions.isNotEmpty
                      ? null
                      : onRemove,
                  icon: Icon(Icons.logout_rounded, size: 17, color: v.muted),
                ),
            ],
          ),
          if (!compact)
            Padding(
              padding: const EdgeInsets.only(left: 33, top: 7),
              child: Text(
                '${deviceKindLabel(device, context: context)}${device['sessions'] is num ? ' · ${wt('devices.sessionsCount', values: {'count': device['sessions']}, context: context)}' : ''}',
                style: TextStyle(fontSize: 10, color: v.muted),
              ),
            ),
          if (track != null)
            Padding(
              padding: const EdgeInsets.only(left: 33, top: 11),
              child: Row(
                children: [
                  Artwork(
                    controller: c,
                    url: track.artwork,
                    size: compact ? 31 : 36,
                    radius: 6,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 10, color: v.muted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ListeningWave(playing: playing, size: 18),
                ],
              ),
            ),
          if (!compact &&
              !online &&
              activityDate(device['lastSeen'], context).isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 33, top: 9),
              child: Text(
                activityDate(device['lastSeen'], context),
                style: TextStyle(fontSize: 10, color: v.muted),
              ),
            ),
        ],
      ),
    );
  }
}
