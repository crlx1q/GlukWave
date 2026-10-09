import 'dart:async';
import 'package:flutter/material.dart';
import '../core/controller.dart';
import '../core/discord.dart';
import '../core/models.dart';
import '../l10n/discord_strings.dart';
import 'widgets.dart';

/// Account linking and server status only. Playback is observed by the server,
/// including when another device is the active GlukWave output.
class DiscordPanel extends StatefulWidget {
  final WaveController controller;
  const DiscordPanel({super.key, required this.controller});
  @override
  State<DiscordPanel> createState() => _DiscordPanelState();
}

class _DiscordPanelState extends State<DiscordPanel> {
  bool _linking = false;
  WaveController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    if (c.discordConnection == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(c.refreshDiscord());
      });
    }
  }

  Future<void> _link() async {
    if (_linking) return;
    setState(() => _linking = true);
    try {
      await c.connectProvider('discord');
    } catch (_) {
      if (mounted) c.tell(dt(context, 'Refresh failed'));
    } finally {
      if (mounted) setState(() => _linking = false);
    }
  }

  Future<void> _unlink() async {
    final confirmed = await showWaveDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(dt(dialog, 'Disconnect question')),
        content: Text(dt(dialog, 'Disconnect detail')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: Text(dt(dialog, 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(dt(dialog, 'Disconnect')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _linking = true);
    try {
      await c.disconnectProvider('discord');
    } catch (_) {
      if (mounted) c.tell(dt(context, 'Refresh failed'));
    } finally {
      if (mounted) setState(() => _linking = false);
    }
  }

  Future<void> _open(String url) async {
    try {
      await c.openUrl(url);
    } catch (_) {
      if (mounted) c.tell(dt(context, 'Refresh failed'));
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) {
      final v = waveVisuals(context), d = c.discordConnection;
      final eligible =
          d?.eligible ?? (c.user?.plan == 'beta' || c.user?.plan == 'unbound');
      final busy = _linking || c.discordChanging;
      return Surface(
        key: const Key('discord-panel'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: v.accentSoft,
                    borderRadius: BorderRadius.circular(
                      waveRadius(context, 14),
                    ),
                  ),
                  child: Icon(Icons.discord, color: v.accent, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Discord',
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -.5,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        dt(context, 'Subtitle'),
                        style: TextStyle(
                          color: v.muted,
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                if (eligible && ['beta', 'unbound'].contains(c.user?.plan)) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: v.line),
                      borderRadius: BorderRadius.circular(
                        waveRadius(context, 8),
                      ),
                    ),
                    child: Text(
                      c.user?.plan == 'beta' ? 'Beta' : 'Unbound',
                      style: TextStyle(
                        color: v.accent,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 20),
            if (!eligible) ...[
              if (d != null && d.identity.isNotEmpty) ...[
                Row(
                  children: [
                    const Icon(Icons.link_rounded, size: 17),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        '@${d.username}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton(
                      key: const Key('discord-unlink'),
                      onPressed: c.online && !busy ? _unlink : null,
                      child: Text(dt(context, 'Disconnect')),
                    ),
                  ],
                ),
                const Divider(height: 24),
              ],
              Text(
                dt(context, 'Locked title'),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                dt(context, 'Locked detail'),
                style: TextStyle(color: v.muted, height: 1.6, fontSize: 13),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const Key('discord-upgrade'),
                onPressed: () => _open(
                  Uri.parse(c.appUrl).resolve('/app/#profile').toString(),
                ),
                icon: const Icon(Icons.auto_awesome_outlined, size: 17),
                label: Text(dt(context, 'Upgrade')),
              ),
            ] else ...[
              if (c.discordLoading && d == null) ...[
                LinearProgressIndicator(
                  key: const Key('discord-loading'),
                  minHeight: 2,
                  color: v.accent,
                  backgroundColor: v.line,
                ),
                const SizedBox(height: 12),
                Text(
                  dt(context, 'Loading'),
                  style: TextStyle(color: v.muted, fontSize: 12),
                ),
              ],
              if (c.discordError != null) ...[
                _DiscordMessage(
                  text: dt(
                    context,
                    c.discordError == 'save_failed'
                        ? 'Save failed'
                        : 'Refresh failed',
                  ),
                  action: TextButton(
                    onPressed: c.discordLoading ? null : c.refreshDiscord,
                    child: Text(dt(context, 'Retry')),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (d != null) ...[
                if (d.identity.isNotEmpty) ...[
                  Row(
                    children: [
                      ClipOval(
                        child: Artwork(
                          controller: c,
                          url: d.avatar,
                          size: 48,
                          radius: 24,
                        ),
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              d.displayName.isNotEmpty
                                  ? d.displayName
                                  : d.username,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '@${d.username}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: v.muted, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                _DiscordStatus(connection: d),
                const SizedBox(height: 12),
                if (!d.connected || d.needsReconnect) ...[
                  Text(
                    dt(
                      context,
                      d.needsReconnect ? 'Reconnect detail' : 'Anywhere',
                    ),
                    style: TextStyle(
                      color: v.muted,
                      fontSize: 12,
                      height: 1.65,
                    ),
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    key: const Key('discord-connect'),
                    onPressed: c.online && d.configured && !busy ? _link : null,
                    icon: _linking
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.link_rounded, size: 18),
                    label: Text(
                      dt(context, d.needsReconnect ? 'Reconnect' : 'Connect'),
                    ),
                  ),
                  if (d.identity.isNotEmpty)
                    TextButton(
                      onPressed: busy ? null : _unlink,
                      child: Text(dt(context, 'Disconnect')),
                    ),
                ] else ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      OutlinedButton.icon(
                        key: const Key('discord-change'),
                        onPressed: c.online && d.configured && !busy
                            ? _link
                            : null,
                        icon: const Icon(Icons.swap_horiz_rounded, size: 17),
                        label: Text(dt(context, 'Change')),
                      ),
                      TextButton(
                        key: const Key('discord-unlink'),
                        onPressed: c.online && !busy ? _unlink : null,
                        child: Text(dt(context, 'Disconnect')),
                      ),
                    ],
                  ),
                  const Divider(height: 32),
                  SwitchListTile.adaptive(
                    key: const Key('discord-enabled'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      dt(context, 'Presence'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Text(
                        dt(context, 'Presence detail'),
                        style: TextStyle(
                          color: v.muted,
                          fontSize: 12,
                          height: 1.55,
                        ),
                      ),
                    ),
                    value: d.enabled,
                    onChanged: c.online && !busy
                        ? (value) => c.updateDiscord({'enabled': value})
                        : null,
                  ),
                  const Divider(height: 24),
                  SwitchListTile.adaptive(
                    key: const Key('discord-allow-join'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      dt(context, 'Join'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Text(
                        dt(context, 'Join detail'),
                        style: TextStyle(
                          color: v.muted,
                          fontSize: 12,
                          height: 1.55,
                        ),
                      ),
                    ),
                    value: d.allowJoin,
                    onChanged: c.online && !busy
                        ? (value) => c.updateDiscord({'allowJoin': value})
                        : null,
                  ),
                ],
                const SizedBox(height: 24),
                DiscordActivityPreview(controller: c, connection: d),
              ],
            ],
          ],
        ),
      );
    },
  );
}

class _DiscordMessage extends StatelessWidget {
  final String text;
  final Widget action;
  const _DiscordMessage({required this.text, required this.action});
  @override
  Widget build(BuildContext context) => Container(
    key: const Key('discord-error'),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: waveVisuals(context).accentSoft,
      borderRadius: BorderRadius.circular(waveRadius(context, 12)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text, style: const TextStyle(height: 1.55, fontSize: 12)),
        action,
      ],
    ),
  );
}

class _DiscordStatus extends StatelessWidget {
  final DiscordConnection connection;
  const _DiscordStatus({required this.connection});
  @override
  Widget build(BuildContext context) {
    final v = waveVisuals(context), active = connection.status == 'active';
    final updating = ['publishing', 'retrying'].contains(connection.status);
    return Row(
      children: [
        if (updating)
          SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(strokeWidth: 1.5, color: v.accent),
          )
        else
          Icon(
            active ? Icons.check_circle_rounded : Icons.circle_outlined,
            size: 13,
            color: active ? v.accent : v.muted,
          ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            dt(context, connection.status),
            key: const Key('discord-status'),
            style: TextStyle(
              color: active ? v.accent : v.muted,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }
}

class DiscordActivityPreview extends StatefulWidget {
  final WaveController controller;
  final DiscordConnection connection;
  const DiscordActivityPreview({
    super.key,
    required this.controller,
    required this.connection,
  });
  @override
  State<DiscordActivityPreview> createState() => _DiscordActivityPreviewState();
}

class _DiscordActivityPreviewState extends State<DiscordActivityPreview> {
  Timer? _clock;
  @override
  void initState() {
    super.initState();
    _syncClock();
  }

  @override
  void didUpdateWidget(covariant DiscordActivityPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncClock();
  }

  void _syncClock() {
    if (!widget.connection.playing) {
      _clock?.cancel();
      _clock = null;
      return;
    }
    _clock ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && TickerMode.of(context)) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  Future<void> _open(String? url) async {
    if (url == null) return;
    try {
      await widget.controller.openUrl(url);
    } catch (_) {
      if (mounted) widget.controller.tell(dt(context, 'Refresh failed'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.connection,
        v = waveVisuals(context),
        position = d.positionAt(DateTime.now());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          dt(context, 'Preview').toUpperCase(),
          style: TextStyle(
            fontSize: 10,
            letterSpacing: 1.4,
            fontWeight: FontWeight.w800,
            color: v.muted,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          key: const Key('discord-preview'),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Color.lerp(v.surface, v.ink, .055),
            borderRadius: BorderRadius.circular(waveRadius(context, 17)),
            border: Border.all(color: v.line),
          ),
          child: d.title.isEmpty
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.headphones_rounded, color: v.accent, size: 30),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            dt(context, 'Ready'),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            dt(context, 'Empty'),
                            style: TextStyle(
                              color: v.muted,
                              fontSize: 12,
                              height: 1.6,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final narrow = constraints.maxWidth < 420;
                    final cover = Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Artwork(
                          controller: widget.controller,
                          url: d.cover,
                          size: narrow ? 68 : 104,
                          radius: 12,
                        ),
                        Positioned(
                          right: -3,
                          bottom: -3,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: v.surface,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Brand(compact: true, size: 19),
                          ),
                        ),
                      ],
                    );
                    final copy = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          dt(context, d.playing ? 'Listening' : 'Paused'),
                          style: TextStyle(
                            fontSize: 10,
                            color: v.muted,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          d.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          d.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: v.ink),
                        ),
                        if (d.album.isNotEmpty)
                          Text(
                            d.album,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: v.muted),
                          ),
                      ],
                    );
                    final progress = Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Row(
                        children: [
                          Text(
                            clock(position),
                            key: const Key('discord-position'),
                            style: TextStyle(color: v.muted, fontSize: 10),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: LinearProgressIndicator(
                                value: d.duration > 0
                                    ? (position / d.duration).clamp(0, 1)
                                    : 0,
                                color: v.ink,
                                backgroundColor: v.line,
                                minHeight: 3,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            clock(d.duration),
                            style: TextStyle(color: v.muted, fontSize: 10),
                          ),
                        ],
                      ),
                    );
                    final buttons = Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Wrap(
                        spacing: 7,
                        runSpacing: 7,
                        children: [
                          if (d.joinUrl != null)
                            OutlinedButton.icon(
                              key: const Key('discord-listen'),
                              onPressed: () => _open(d.joinUrl),
                              icon: const Icon(
                                Icons.headphones_rounded,
                                size: 14,
                              ),
                              label: Text(dt(context, 'Listen together')),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 36),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                textStyle: Theme.of(context)
                                    .textTheme
                                    .labelLarge
                                    ?.copyWith(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                          OutlinedButton.icon(
                            key: const Key('discord-open-track'),
                            onPressed: d.trackUrl == null
                                ? null
                                : () => _open(d.trackUrl),
                            icon: const Icon(
                              Icons.north_east_rounded,
                              size: 14,
                            ),
                            label: Text(dt(context, 'Open Wave')),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 36),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              textStyle: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    );
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            cover,
                            const SizedBox(width: 15),
                            Expanded(child: copy),
                          ],
                        ),
                        progress,
                        buttons,
                      ],
                    );
                  },
                ),
        ),
        if (d.deviceName.isNotEmpty && d.title.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              children: [
                Icon(Icons.speaker_rounded, size: 12, color: v.accent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    d.deviceName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: v.accent, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 10),
        Text(
          dt(context, 'Rendering'),
          style: TextStyle(fontSize: 10, height: 1.5, color: v.muted),
        ),
      ],
    );
  }
}
