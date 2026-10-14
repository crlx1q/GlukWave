import 'package:flutter/material.dart';
import '../core/controller.dart';
import '../core/models.dart';
import '../l10n/ecosystem_polish_strings.dart';
import 'device_labels.dart';
import 'widgets.dart';

bool memberListening(Json member) =>
    member['online'] == true &&
    objects(member['devices']).any(
      (device) =>
          device['online'] != false &&
          device['outputActive'] == true &&
          device['playing'] == true,
    );

class ListeningPresence extends StatelessWidget {
  final WaveController controller;
  final VoidCallback? onTap;
  final bool compact;
  const ListeningPresence({
    super.key,
    required this.controller,
    this.onTap,
    this.compact = false,
  });
  @override
  Widget build(BuildContext context) {
    final members = objects(
      controller.room?['members'],
    ).where(memberListening).toList();
    if (controller.room == null || members.isEmpty) {
      return const SizedBox.shrink();
    }
    final v = waveVisuals(context);
    return Semantics(
      label:
          '${ecosystemText('together', context)}: ${members.map((m) => m['displayName'] ?? '').join(', ')}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(v.corners(12)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 24 + (members.take(3).length - 1) * 16.0,
                height: 24,
                child: Stack(
                  children: [
                    for (var i = 0; i < members.take(3).length; i++)
                      Positioned(
                        left: i * 16.0,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: v.background, width: 1.5),
                          ),
                          child: ClipOval(
                            child: Artwork(
                              controller: controller,
                              url: members[i]['avatarUrl']?.toString(),
                              size: 21,
                              radius: 0,
                              icon: Icons.person_outline_rounded,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (!compact)
                Flexible(
                  child: Text(
                    ecosystemText('together', context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, color: v.muted),
                  ),
                ),
              if (members.length > 3)
                Padding(
                  padding: const EdgeInsets.only(left: 5),
                  child: Text(
                    '+${members.length - 3}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: v.accent,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class PlayingOutput extends StatelessWidget {
  final WaveController controller;
  final VoidCallback? onTap;
  final bool banner;
  const PlayingOutput({
    super.key,
    required this.controller,
    this.onTap,
    this.banner = false,
  });
  @override
  Widget build(BuildContext context) {
    final c = controller, v = waveVisuals(context);
    if (!c.controllingRemote || c.audio.viewCurrent == null) {
      if (banner) return const SizedBox.shrink();
      return TextButton.icon(
        key: const Key('connect-local-entry'),
        onPressed: onTap,
        icon: Icon(Icons.devices_rounded, size: 16, color: v.muted),
        label: Text(
          'GlukWave Connect',
          style: TextStyle(fontSize: 11, color: v.muted),
        ),
      );
    }
    final device =
        c.devices
            .where((d) => (d['deviceId'] ?? d['id']) == c.activeDeviceId)
            .firstOrNull ??
        <String, dynamic>{'name': c.activeDeviceName, 'kind': 'web'};
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(v.corners(banner ? 9 : 12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(v.corners(12)),
        child: Padding(
          padding: EdgeInsets.symmetric(
            vertical: banner ? 1 : 5,
            horizontal: 0,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DevicePlatformIcon(
                device: device,
                size: banner ? 13 : 16,
                color: v.accent,
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  device['name']?.toString() ?? c.activeDeviceName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: v.accent,
                    fontSize: banner ? 9 : 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ListeningWave(playing: c.audio.playing, size: banner ? 13 : 15),
            ],
          ),
        ),
      ),
    );
  }
}
