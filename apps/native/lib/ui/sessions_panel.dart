import 'dart:async';
import 'package:flutter/material.dart';
import '../core/controller.dart';
import '../l10n/wave_localizations.dart';
import 'device_labels.dart';
import 'widgets.dart';

class SessionsPanel extends StatefulWidget {
  final WaveController controller;
  const SessionsPanel({super.key, required this.controller});
  @override
  State<SessionsPanel> createState() => _SessionsPanelState();
}

class _SessionsPanelState extends State<SessionsPanel> {
  @override
  void initState() {
    super.initState();
    scheduleMicrotask(widget.controller.refreshSessions);
  }

  Future<void> remove(String? id) async {
    final c = widget.controller;
    final accepted = await showWaveDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(
          wt(
            id == null ? 'sessions.endOthers' : 'sessions.end',
            context: dialog,
          ),
        ),
        content: Text(
          wt(
            id == null ? 'sessions.confirmOthers' : 'sessions.confirm',
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
            child: Text(wt('sessions.end', context: dialog)),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    try {
      await c.revokeSession(id);
    } catch (_) {
      c.tell(wt('sessions.actionFailed'));
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final c = widget.controller, v = waveVisuals(context);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeading(
            wt('sessions.title', context: context),
            wt('sessions.description', context: context),
            eyebrow: wt('sessions.security', context: context),
          ),
          if (c.sessionsLoading) const LinearProgressIndicator(minHeight: 2),
          if (c.sessionsError != null)
            Surface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.sessionsError!),
                  TextButton.icon(
                    onPressed: c.refreshSessions,
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(wt('devices.refresh', context: context)),
                  ),
                ],
              ),
            ),
          if (!c.sessionsSupported)
            EmptyState(
              wt('sessions.unavailable', context: context),
              wt('sessions.unavailableHint', context: context),
              icon: Icons.lock_outline_rounded,
            ),
          if (c.sessionsSupported &&
              c.sessions.isEmpty &&
              !c.sessionsLoading &&
              c.sessionsError == null)
            EmptyState(
              wt('sessions.empty', context: context),
              wt('sessions.description', context: context),
              icon: Icons.lock_outline_rounded,
            ),
          for (final session in c.sessions) ...[
            Surface(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: v.accentSoft,
                      borderRadius: BorderRadius.circular(v.corners(13)),
                    ),
                    child: Icon(
                      deviceKindIcon(session),
                      color: v.accent,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          session['deviceName']?.toString() ??
                              wt('connect.otherDevice', context: context),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '${deviceKindLabel(session, context: context)} · ${wt(session['current'] == true
                              ? 'sessions.current'
                              : session['online'] == true
                              ? 'native.011e2099f2'
                              : 'native.67b99cc9bf', context: context)}',
                          style: TextStyle(
                            color: session['current'] == true
                                ? v.accent
                                : v.muted,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 9),
                        Text(
                          wt(
                            'sessions.lastActive',
                            values: {
                              'time': activityDate(
                                session['lastActiveAt'],
                                context,
                              ),
                            },
                            context: context,
                          ),
                          style: TextStyle(fontSize: 11, color: v.muted),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: Key('session-revoke-${session['id']}'),
                    tooltip: wt('sessions.end', context: context),
                    onPressed:
                        !c.online ||
                            c.pendingSessionActions.contains(session['id'])
                        ? null
                        : () => remove(session['id'].toString()),
                    icon: c.pendingSessionActions.contains(session['id'])
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(Icons.logout_rounded, color: v.muted, size: 19),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (c.sessions.any((s) => s['current'] != true)) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('sessions-revoke-others'),
              onPressed: !c.online || c.pendingSessionActions.contains('others')
                  ? null
                  : () => remove(null),
              icon: const Icon(Icons.security_rounded, size: 18),
              label: Text(wt('sessions.endOthers', context: context)),
            ),
            const SizedBox(height: 10),
            Text(
              wt('sessions.preserveCurrent', context: context),
              style: TextStyle(color: v.muted, fontSize: 12, height: 1.5),
            ),
          ],
        ],
      );
    },
  );
}
