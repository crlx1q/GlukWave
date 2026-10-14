import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/controller.dart';
import '../l10n/ecosystem_polish_strings.dart';
import '../l10n/wave_localizations.dart';
import 'widgets.dart';
import 'connect_device_tile.dart';

Future<void> showConnectPicker(
  BuildContext context,
  WaveController c, {
  VoidCallback? onAllDevices,
  Rect? anchor,
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
          padding: EdgeInsets.fromLTRB(
            14,
            14,
            anchor == null
                ? 14
                : (MediaQuery.sizeOf(context).width - anchor.right).clamp(
                    14.0,
                    math.max(
                      14.0,
                      MediaQuery.sizeOf(context).width -
                          math.min(350, MediaQuery.sizeOf(context).width - 28) -
                          14,
                    ),
                  ),
            anchor == null
                ? 105
                : math.max(
                    16,
                    MediaQuery.sizeOf(context).height - anchor.top + 10,
                  ),
          ),
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
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: math.max(
                    150,
                    math.min(
                      600,
                      (anchor?.top ?? MediaQuery.sizeOf(context).height - 105) -
                          MediaQuery.paddingOf(context).top -
                          28,
                    ),
                  ),
                ),
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
                            in ([...c.devices]..sort(
                              (a, b) =>
                                  ((connectDeviceId(b) == c.activeDeviceId
                                              ? 2
                                              : 0) +
                                          (b['online'] == true ? 1 : 0))
                                      .compareTo(
                                        (connectDeviceId(a) == c.activeDeviceId
                                                ? 2
                                                : 0) +
                                            (a['online'] == true ? 1 : 0),
                                      ),
                            )))
                          ConnectDeviceTile(
                            controller: c,
                            device: device,
                            compact: true,
                          ),
                        if (c.devices.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            child: Text(
                              wt('native.76bdd0e417', context: context),
                              style: TextStyle(
                                color: waveVisuals(context).muted,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        if (c.lanEnabled && c.lanPeers.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.only(top: 18, bottom: 4),
                            child: Text(
                              'LAN · Wi-Fi',
                              key: const Key('connect-lan-section'),
                              style: TextStyle(
                                fontSize: 10,
                                color: waveVisuals(context).muted,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          for (final device in c.lanPeers)
                            ConnectDeviceTile(
                              controller: c,
                              device: device,
                              compact: true,
                              lan: true,
                            ),
                        ],
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
