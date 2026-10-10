import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../core/controller.dart';
import '../core/models.dart';
import '../l10n/lan_strings.dart';
import '../l10n/wave_localizations.dart';
import 'widgets.dart';
import 'device_labels.dart';

class LanPanel extends StatefulWidget {
  final WaveController controller;
  final Future<void> Function()? scanQr;
  const LanPanel({super.key, required this.controller, this.scanQr});
  @override
  State<LanPanel> createState() => _LanPanelState();
}

class _LanPanelState extends State<LanPanel> {
  final invitation = TextEditingController();
  bool busy = false;
  String? error;
  WaveController get c => widget.controller;
  String text(String key) => lanText(key, context: context);
  @override
  void dispose() {
    invitation.dispose();
    super.dispose();
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> revoke(Json peer) async {
    final ok = await showWaveDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(text('revoke')),
        content: Text(text('revokeConfirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(wt('native.0ec753be8d', context: ctx)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(text('revoke')),
          ),
        ],
      ),
    );
    if (ok == true) await run(() => c.removeLanPeer(peer['id'].toString()));
  }

  @override
  Widget build(BuildContext context) {
    final v = waveVisuals(context);
    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.wifi_rounded, color: v.accent, size: 21),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text('title'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (busy)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            text('caption'),
            style: TextStyle(color: v.muted, fontSize: 12, height: 1.5),
          ),
          SwitchListTile(
            key: const Key('lan-enable'),
            contentPadding: EdgeInsets.zero,
            title: Text(
              text('enable'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              text('enableHint'),
              style: TextStyle(color: v.muted, fontSize: 12, height: 1.5),
            ),
            value: c.lanEnabled,
            onChanged: busy
                ? null
                : (value) => run(() => c.setLanEnabled(value)),
          ),
          if (c.lanEnabled) ...[
            const Divider(height: 24),
            Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c.lanActive ? v.accent : v.muted,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    c.lanActive ? text('online') : text('ready'),
                    style: TextStyle(
                      color: v.accent,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
                if (c.lanActive)
                  IconButton(
                    key: const Key('lan-disconnect'),
                    onPressed: busy ? null : () => run(c.disconnectLan),
                    tooltip: text('disconnect'),
                    icon: const Icon(Icons.link_off_rounded, size: 20),
                  ),
              ],
            ),
            if (c.lanActive && c.controllingRemote)
              OutlinedButton.icon(
                key: const Key('lan-listen-here'),
                onPressed: busy ? null : () => run(c.listenHere),
                icon: const Icon(Icons.speaker_outlined, size: 18),
                label: Text(wt('connect.playHere', context: context)),
              ),
            if (c.lanHostName?.isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  c.lanHostName!,
                  style: TextStyle(color: v.muted, fontSize: 12),
                ),
              ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: const Key('lan-create-invite'),
                  onPressed: busy
                      ? null
                      : () => run(() async {
                          await c.createLanInvite();
                        }),
                  icon: const Icon(Icons.qr_code_rounded, size: 18),
                  label: Text(text('invite')),
                ),
                if (widget.scanQr != null)
                  TextButton.icon(
                    key: const Key('lan-scan-invite'),
                    onPressed: busy ? null : () => run(widget.scanQr!),
                    icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                    label: Text(text('scan')),
                  ),
              ],
            ),
            if (c.lanInvite?.isNotEmpty == true) ...[
              const SizedBox(height: 16),
              Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: QrImageView(
                      key: const Key('lan-qr'),
                      data: c.lanInvite!,
                      size: 192,
                      backgroundColor: Colors.white,
                      errorCorrectionLevel: QrErrorCorrectLevel.M,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                text('inviteHint'),
                style: TextStyle(color: v.muted, fontSize: 12, height: 1.5),
              ),
              TextButton.icon(
                key: const Key('lan-copy-invite'),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: c.lanInvite!));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(text('copied'))));
                },
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: Text(text('copy')),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              key: const Key('lan-invitation'),
              controller: invitation,
              maxLength: 4096,
              minLines: 1,
              maxLines: 3,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: text('paste'),
                hintText: 'glukwave://lan?data=…',
                counterText: '',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              key: const Key('lan-connect'),
              onPressed: busy
                  ? null
                  : () => run(() async {
                      await c.connectLan(invitation.text.trim());
                      if (mounted) invitation.clear();
                    }),
              icon: const Icon(Icons.link_rounded, size: 18),
              label: Text(text('connect')),
            ),
            const Divider(height: 30),
            Text(
              text('trusted'),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            ),
            const SizedBox(height: 10),
            if (c.lanPeers.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  text('empty'),
                  style: TextStyle(color: v.muted, fontSize: 12),
                ),
              ),
            for (final peer in c.lanPeers)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Icon(deviceKindIcon(peer), color: v.muted, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            peer['name']?.toString() ?? 'GlukWave',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            peer['isActive'] == true
                                ? text('output')
                                : peer['status'] == 'connecting'
                                ? text('connecting')
                                : peer['online'] == true
                                ? text('online')
                                : text('offline'),
                            style: TextStyle(
                              color: peer['isActive'] == true
                                  ? v.accent
                                  : v.muted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (peer['online'] == true && peer['isActive'] != true)
                      IconButton(
                        key: Key('lan-transfer-${peer['id']}'),
                        onPressed: busy || c.audio.viewCurrent == null
                            ? null
                            : () =>
                                  run(() => c.transfer(peer['id'].toString())),
                        tooltip: wt('connect.playHere', context: context),
                        icon: Icon(
                          Icons.speaker_outlined,
                          color: v.accent,
                          size: 20,
                        ),
                      ),
                    IconButton(
                      key: Key('lan-revoke-${peer['id']}'),
                      onPressed: busy ? null : () => revoke(peer),
                      tooltip: text('revoke'),
                      icon: Icon(
                        Icons.link_off_rounded,
                        color: v.muted,
                        size: 18,
                      ),
                    ),
                  ],
                ),
              ),
          ],
          if (error != null || c.lanError != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                error ?? c.lanError!,
                key: const Key('lan-error'),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
