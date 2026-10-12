import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/controller.dart';
import '../l10n/ecosystem_polish_strings.dart';
import 'connect_panel.dart';
import 'device_labels.dart';
import 'widgets.dart';

Future<void> showConnectPicker(
  BuildContext context,
  WaveController c, {
  VoidCallback? onAllDevices,
}) => showGeneralDialog<void>(
  context: context,
  barrierDismissible: true,
  barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
  barrierColor: Colors.black.withValues(alpha: .18),
  transitionDuration: const Duration(milliseconds: 180),
  pageBuilder: (dialog, _, _) => AnimatedBuilder(
    animation: c,
    builder: (context, _) => SafeArea(
      child: Align(
        alignment: Alignment.bottomRight,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 105),
          child: Material(
            key: const Key('connect-quick-picker'),
            color: waveVisuals(context).surface,
            elevation: 12,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(waveRadius(context, 24)),
              side: BorderSide(color: waveVisuals(context).line),
            ),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              width: math.min(350, MediaQuery.sizeOf(context).width - 28),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(17),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'GLUKWAVE CONNECT',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                letterSpacing: .6,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close_rounded, size: 18),
                          ),
                        ],
                      ),
                      if (c.transferPending != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(
                            ecosystemText('waiting', context),
                            style: TextStyle(
                              color: waveVisuals(context).accent,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      for (final device
                          in c.lanEnabled ? c.lanPeers : c.devices)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: DevicePlatformIcon(
                            device: device,
                            color: installationId(device) == c.activeDeviceId
                                ? waveVisuals(context).accent
                                : waveVisuals(context).muted,
                          ),
                          title: Text(
                            device['name']?.toString() ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          subtitle: Text(
                            deviceKindLabel(device, context: context),
                            style: const TextStyle(fontSize: 10),
                          ),
                          trailing: c.transferPending == installationId(device)
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : installationId(device) == c.activeDeviceId
                              ? ListeningWave(playing: c.audio.playing)
                              : null,
                          enabled:
                              device['online'] == true &&
                              c.transferPending == null,
                          onTap: () async {
                            try {
                              await c.transfer(
                                installationId(device),
                                targetSurfaceId:
                                    installationId(device) == c.deviceId
                                    ? c.surfaceId
                                    : device['surfaceId']?.toString(),
                              );
                            } catch (e) {
                              c.tell(e.toString());
                            }
                          },
                        ),
                      if (onAllDevices != null)
                        TextButton(
                          onPressed: () {
                            Navigator.pop(context);
                            onAllDevices();
                          },
                          child: Text(ecosystemText('allDevices', context)),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  ),
  transitionBuilder: (context, animation, _, child) => FadeTransition(
    opacity: animation,
    child: SlideTransition(
      position: Tween(
        begin: const Offset(0, .018),
        end: Offset.zero,
      ).animate(animation),
      child: child,
    ),
  ),
);
