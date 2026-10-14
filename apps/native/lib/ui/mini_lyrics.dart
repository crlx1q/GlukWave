import 'dart:async';
import 'package:flutter/material.dart';
import '../core/controller.dart';
import '../core/models.dart';
import 'native19_strings.dart';
import 'widgets.dart';

/// One small, vertically stacked current/next excerpt shared by transports.
/// Supplied lines reuse the full player's lookup; compact windows use the
/// controller's saved/online lyrics pipeline and reject stale responses.
class MiniLyrics extends StatefulWidget {
  final WaveController controller;
  final WaveTrack track;
  final List<Json>? lines;
  final bool synchronized, dense;
  final ValueChanged<bool>? onAvailability;
  const MiniLyrics({
    super.key,
    required this.controller,
    required this.track,
    this.lines,
    this.synchronized = false,
    this.dense = false,
    this.onAvailability,
  });
  @override
  State<MiniLyrics> createState() => _MiniLyricsState();
}

class _MiniLyricsState extends State<MiniLyrics> {
  List<Json> lines = [];
  bool synchronized = false;
  bool loading = false;
  int request = 0;
  String? scope;
  bool? reported;
  WaveController get c => widget.controller;
  bool get enabled =>
      c.settings['lyrics'] != false && c.settings['lyricsUnderCover'] != false;
  @override
  void initState() {
    super.initState();
    c.addListener(changed);
    changed();
  }

  @override
  void didUpdateWidget(MiniLyrics old) {
    super.didUpdateWidget(old);
    if (old.controller != c) {
      old.controller.removeListener(changed);
      c.addListener(changed);
    }
    changed();
  }

  void changed() {
    final next =
        '${c.namespace}:${widget.track.id}:$enabled:${c.online}:${c.localSavedPlayback}';
    if (widget.lines != null || next == scope) return;
    scope = next;
    final revision = ++request;
    lines = [];
    loading = enabled;
    if (!enabled) return;
    unawaited(
      c
          .lyricsFor(widget.track)
          .then((data) {
            if (!mounted || request != revision) return;
            setState(() {
              lines = objects(data['lines']);
              synchronized = data['synchronized'] == true;
              loading = false;
            });
          })
          .catchError((Object _) {
            if (mounted && request == revision) setState(() => loading = false);
          }),
    );
  }

  @override
  void dispose() {
    request++;
    c.removeListener(changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final excerpt = widget.lines ?? lines;
    final available =
        enabled && (excerpt.isNotEmpty || loading && reported == true);
    if (reported != available) {
      reported = available;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.onAvailability?.call(available);
          if (widget.onAvailability != null) setState(() {});
        }
      });
      // Give an adaptive transport one frame to make space for the excerpt.
      if (available && widget.onAvailability != null) {
        return const SizedBox.shrink();
      }
    }
    if (!available || excerpt.isEmpty) return const SizedBox.shrink();
    final v = waveVisuals(context), dense = widget.dense;
    return StreamBuilder<Duration>(
      stream: c.audio.positionStream,
      initialData: c.audio.position,
      builder: (context, position) {
        final timed =
            (widget.lines == null ? synchronized : widget.synchronized) &&
            c.audio.viewCurrent?.id == widget.track.id;
        final index =
            (timed
                    ? activeLyric(
                        excerpt,
                        (position.data?.inMilliseconds ?? 0) / 1000,
                      )
                    : 0)
                .clamp(0, excerpt.length - 1);
        return Container(
          key: const Key('mini-lyrics-frame'),
          width: double.infinity,
          margin: EdgeInsets.symmetric(vertical: dense ? 3 : 8),
          padding: EdgeInsets.symmetric(
            horizontal: dense ? 8 : 10,
            vertical: dense ? 5 : 7,
          ),
          decoration: BoxDecoration(
            border: Border.all(color: v.line),
            borderRadius: BorderRadius.circular(v.corners(12)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                nativeText(context, 'lyrics'),
                key: const Key('mini-lyrics-caption'),
                style: TextStyle(
                  fontSize: dense ? 7 : 8,
                  height: 1.2,
                  color: v.muted,
                  letterSpacing: .5,
                ),
              ),
              const SizedBox(height: 3),
              for (final line in [
                index,
                if (index + 1 < excerpt.length) index + 1,
              ])
                Text(
                  excerpt[line]['text']?.toString() ?? '',
                  key: Key('mini-lyric-$line'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: line == index
                        ? (dense ? 12 : 16)
                        : (dense ? 10 : 12),
                    height: 1.3,
                    fontWeight: line == index
                        ? FontWeight.w800
                        : FontWeight.w500,
                    color: line == index ? v.ink : v.muted,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
