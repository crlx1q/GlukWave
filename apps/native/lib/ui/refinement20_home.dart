import 'dart:async';
import 'package:flutter/material.dart';
import '../core/controller.dart';
import '../core/models.dart';
import 'widgets.dart';
import 'motion_icons.dart';
import 'refinement20_strings.dart';
import 'wave18_strings.dart';

/// Discovery shelves request only once they enter the viewport. Playback and
/// account state stay in the controller, and the same backend as Wave ranks it.
class NativeDiscoveryShelf extends StatefulWidget {
  final WaveController controller;
  final String mode;
  const NativeDiscoveryShelf({
    super.key,
    required this.controller,
    required this.mode,
  });
  @override
  State<NativeDiscoveryShelf> createState() => _NativeDiscoveryShelfState();
}

class _NativeDiscoveryShelfState extends State<NativeDiscoveryShelf> {
  ScrollPosition? scroll;
  bool requested = false, busy = false;
  String? error;
  List<WaveTrack> tracks = [];
  late final account = widget.controller.user?.id,
      origin = widget.controller.api.server;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.maybeOf(context)?.position;
    if (scroll != position) {
      scroll?.removeListener(check);
      scroll = position;
      scroll?.addListener(check);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) check();
    });
  }

  void check() {
    if (requested || !mounted || !widget.controller.online) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final y = box.localToGlobal(Offset.zero).dy;
    if (y <= MediaQuery.sizeOf(context).height + 100 &&
        y + box.size.height > 0) {
      requested = true;
      unawaited(load());
    }
  }

  Future<void> load() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final data = await widget.controller.api.call(
        '/api/recommendations',
        query: {'mode': widget.mode, 'mood': 'personal', 'limit': 8},
      );
      if (mounted &&
          account == widget.controller.user?.id &&
          origin == widget.controller.api.server) {
        setState(
          () => tracks = objects(data['tracks']).map(WaveTrack.new).toList(),
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    scroll?.removeListener(check);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller, v = waveVisuals(context);
    final title = refinementText(
      context,
      widget.mode == 'discovery' ? 'discover' : 'popular',
    );
    return Padding(
      padding: const EdgeInsets.only(top: 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 22,
                    letterSpacing: -.6,
                  ),
                ),
              ),
              IconButton(
                key: Key('home-start-${widget.mode}'),
                tooltip: wave18Text(context, 'wave18.mode.${widget.mode}'),
                onPressed: c.online
                    ? () async {
                        try {
                          await c.startWave(mode: widget.mode);
                        } catch (e) {
                          c.tell(e.toString());
                        }
                      }
                    : null,
                icon: WaveControlIcon(
                  Icons.play_arrow_rounded,
                  size: 22,
                  color: v.accent,
                ),
              ),
            ],
          ),
          Text(
            wave18Text(context, 'wave18.caption.${widget.mode}'),
            style: TextStyle(fontSize: 12, color: v.muted, height: 1.5),
          ),
          const SizedBox(height: 15),
          if (busy)
            const LinearProgressIndicator(minHeight: 2)
          else if (tracks.isNotEmpty)
            LayoutBuilder(
              builder: (context, bounds) {
                final size = bounds.maxWidth < 400 ? 136.0 : 158.0;
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final track in tracks)
                        Padding(
                          padding: const EdgeInsets.only(right: 14),
                          child: SizedBox(
                            width: size,
                            child: WavePress(
                              child: InkWell(
                                borderRadius: BorderRadius.circular(
                                  v.corners(16),
                                ),
                                onTap: () async {
                                  try {
                                    await c.play(track, list: tracks);
                                  } catch (e) {
                                    c.tell(e.toString());
                                  }
                                },
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Artwork(
                                      controller: c,
                                      url: track.artwork,
                                      size: size,
                                      radius: 16,
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      track.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      track.artist,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: v.muted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            )
          else if (error != null)
            Row(
              children: [
                Expanded(
                  child: Text(
                    refinementText(context, 'recommendationsUnavailable'),
                    style: TextStyle(color: v.muted, fontSize: 12),
                  ),
                ),
                TextButton(
                  onPressed: load,
                  child: Text(refinementText(context, 'retry')),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
