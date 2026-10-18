import '../l10n/glukwave27_ui_strings.dart';
import 'connect_picker.dart';
import 'listening_presence.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../core/controller.dart';
import '../core/models.dart';
import '../l10n/wave_localizations.dart';
import 'widgets.dart';

/// Desktop has a genuine listening rail, rather than a wider phone layout.
class DesktopListeningRail extends StatefulWidget {
  final WaveController controller;
  final VoidCallback onExpand, onDevices;
  final VoidCallback? onQueue;
  const DesktopListeningRail({
    super.key,
    required this.controller,
    required this.onExpand,
    required this.onDevices,
    this.onQueue,
  });
  @override
  State<DesktopListeningRail> createState() => _DesktopListeningRailState();
}

class _DesktopListeningRailState extends State<DesktopListeningRail> {
  WaveController get c => widget.controller;
  String? lyricTrack;
  List<Json> lines = [];
  bool synchronized = false;
  int request = 0;
  @override
  void initState() {
    super.initState();
    c.addListener(_changed);
    _changed();
  }

  void _changed() {
    final track = c.audio.viewCurrent;
    if (track?.id == lyricTrack) return;
    lyricTrack = track?.id;
    lines = [];
    final revision = ++request;
    if (track != null && c.settings['lyrics'] != false) {
      unawaited(
        c.api
            .call('/api/tracks/${track.id}/lyrics')
            .then((data) {
              if (!mounted || revision != request) return;
              setState(() {
                lines = objects(data['lines']);
                synchronized = data['synchronized'] == true;
              });
            })
            .catchError((_) {}),
      );
    }
  }

  @override
  void dispose() {
    c.removeListener(_changed);
    request++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = waveVisuals(context), track = c.audio.viewCurrent;
    return Container(
      key: const Key('desktop-listening-rail'),
      width: 244,
      padding: const EdgeInsets.fromLTRB(19, 26, 19, 18),
      decoration: BoxDecoration(
        color: v.surface.withValues(alpha: .6),
        border: Border(left: BorderSide(color: v.line)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    wt('native.b1b410f065', context: context),
                    style: TextStyle(
                      fontSize: 8,
                      letterSpacing: 1.3,
                      fontWeight: FontWeight.w800,
                      color: v.muted,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: widget.onExpand,
                  tooltip: wt('native.d66131f711', context: context),
                  icon: const Icon(Icons.open_in_full_rounded, size: 16),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (track == null) ...[
              Container(
                height: 185,
                decoration: BoxDecoration(
                  color: v.accentSoft.withValues(alpha: .5),
                  borderRadius: BorderRadius.circular(waveRadius(context, 16)),
                ),
                child: Center(
                  child: Icon(Icons.album_outlined, size: 55, color: v.accent),
                ),
              ),
              const SizedBox(height: 21),
              Text(
                wt('native.899c8de911', context: context),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 9),
              Text(
                wt('native.b196b73079', context: context),
                style: TextStyle(fontSize: 11, height: 1.6, color: v.muted),
              ),
            ] else ...[
              Artwork(controller: c, url: track.artwork, size: 204, radius: 16),
              const SizedBox(height: 20),
              Text(
                track.title,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 19,
                  letterSpacing: -.5,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 7),
              Text(
                track.artist,
                style: TextStyle(color: v.muted, fontSize: 11),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),
              PlayingOutput(
                controller: c,
                onTap: () => showConnectPicker(
                  context,
                  c,
                  onAllDevices: widget.onDevices,
                ),
              ),
              ListeningPresence(controller: c),
              const Divider(height: 32),
              Text(
                wave27Text(context, 'next'),
                style: TextStyle(fontSize: 10, height: 1.6, color: v.muted),
              ),
              const SizedBox(height: 12),
              for (final next
                  in c.audio.viewTracks
                      .where((item) => item.id != track.id)
                      .take(3))
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Artwork(
                        controller: c,
                        url: next.artwork,
                        size: 34,
                        radius: 7,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              next.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              next.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 10, color: v.muted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              TextButton.icon(
                onPressed: widget.onQueue ?? widget.onExpand,
                icon: const Icon(Icons.queue_music_rounded, size: 17),
                label: Text(wave27Text(context, 'queue')),
              ),
              if (lines.isNotEmpty && c.settings['lyrics'] != false) ...[
                const Divider(height: 32),
                Text(
                  wt('native.93970437e2', context: context),
                  style: TextStyle(
                    fontSize: 9,
                    letterSpacing: 1.2,
                    color: v.muted,
                  ),
                ),
                const SizedBox(height: 15),
                StreamBuilder<Duration>(
                  stream: c.audio.positionStream,
                  initialData: c.audio.position,
                  builder: (_, position) {
                    final active = synchronized
                        ? activeLyric(
                            lines,
                            (position.data?.inMilliseconds ?? 0) / 1000,
                          )
                        : 0;
                    return AnimatedSwitcher(
                      duration: v.duration(220),
                      child: Align(
                        key: ValueKey(active),
                        alignment: Alignment.centerLeft,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (
                              var index = active.clamp(0, lines.length - 1);
                              index < lines.length &&
                                  index < active.clamp(0, lines.length - 1) + 2;
                              index++
                            )
                              Padding(
                                padding: EdgeInsets.only(
                                  top:
                                      index == active.clamp(0, lines.length - 1)
                                      ? 0
                                      : 10,
                                ),
                                child: Text(
                                  lines[index]['text']?.toString() ?? '',
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize:
                                        index ==
                                            active.clamp(0, lines.length - 1)
                                        ? 18
                                        : 15,
                                    height: 1.45,
                                    fontWeight:
                                        index ==
                                            active.clamp(0, lines.length - 1)
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color:
                                        index ==
                                            active.clamp(0, lines.length - 1)
                                        ? v.ink
                                        : v.muted,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
