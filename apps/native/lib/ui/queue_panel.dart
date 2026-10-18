import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:math' as math;
import '../core/controller.dart';
import '../core/models.dart';
import '../l10n/ecosystem_polish_strings.dart';
import 'device_labels.dart';
import 'widgets.dart';

class QueuePanel extends StatefulWidget {
  final WaveController controller;
  final ValueChanged<WaveTrack> onMore;
  const QueuePanel({super.key, required this.controller, required this.onMore});
  @override
  State<QueuePanel> createState() => _QueuePanelState();
}

class _QueueEntry {
  final int key;
  final WaveTrack track;
  const _QueueEntry(this.key, this.track);
}

class _QueuePanelState extends State<QueuePanel> {
  final rows = <_QueueEntry>[];
  int occurrence = 0;
  int? picked;
  Offset? pointer;
  Timer? edgeScroll;
  List<_QueueEntry> reconcile(List<WaveTrack> tracks) {
    final available = List<_QueueEntry>.of(rows);
    return tracks.map((track) {
      var at = available.indexWhere((row) => identical(row.track, track));
      if (at < 0) at = available.indexWhere((row) => row.track.id == track.id);
      return at < 0
          ? _QueueEntry(++occurrence, track)
          : _QueueEntry(available.removeAt(at).key, track);
    }).toList();
  }

  void scrollEdge() {
    if (!mounted || picked == null || pointer == null) return;
    final scroll = Scrollable.maybeOf(context),
        object = Scrollable.maybeOf(context)?.context.findRenderObject();
    if (scroll == null || object is! RenderBox) return;
    final y = object.globalToLocal(pointer!).dy,
        h = object.size.height,
        step = y < 56
            ? -math.min(18.0, (56 - y) * .28)
            : y > h - 56
            ? math.min(18.0, (y - h + 56) * .28)
            : 0.0;
    if (step != 0 && scroll.position.hasContentDimensions) {
      scroll.position.jumpTo(
        (scroll.position.pixels + step).clamp(
          scroll.position.minScrollExtent,
          scroll.position.maxScrollExtent,
        ),
      );
    }
  }

  Widget grip(int index, Widget child, bool canEdit) {
    final desktop = [
      TargetPlatform.windows,
      TargetPlatform.linux,
      TargetPlatform.macOS,
    ].contains(defaultTargetPlatform);
    return desktop
        ? ReorderableDragStartListener(
            index: index,
            enabled: canEdit,
            child: MouseRegion(
              cursor: canEdit
                  ? SystemMouseCursors.grab
                  : SystemMouseCursors.basic,
              child: child,
            ),
          )
        : ReorderableDelayedDragStartListener(
            index: index,
            enabled: canEdit,
            child: child,
          );
  }

  final retiring = <int>{};
  Timer? removal;
  bool busy = false;
  String? signature;
  WaveController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    rows.addAll(reconcile(c.audio.viewTracks));
    c.addListener(sync);
  }

  void sync() {
    if (!mounted || picked != null) return;
    final latest = c.audio.viewTracks;
    final next = reconcile(latest);
    final nextSignature =
        '${latest.map((t) => t.id).join("|")}:${c.audio.viewCurrent?.id}:${c.audio.playing}:${c.trackLoading}:${c.canControl}';
    if (signature == nextSignature) return;
    signature = nextSignature;
    final deleted = rows
        .where((t) => !next.any((v) => v.key == t.key))
        .map((t) => t.key)
        .toSet();
    if (deleted.isNotEmpty) {
      setState(() => retiring.addAll(deleted));
      removal?.cancel();
      removal = Timer(const Duration(milliseconds: 240), () {
        if (mounted) {
          setState(() {
            rows
              ..clear()
              ..addAll(reconcile(c.audio.viewTracks));
            retiring.clear();
          });
        }
      });
    } else if (retiring.isEmpty) {
      setState(
        () => rows
          ..clear()
          ..addAll(next),
      );
    }
  }

  @override
  void dispose() {
    c.removeListener(sync);
    removal?.cancel();
    edgeScroll?.cancel();
    super.dispose();
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
      sync();
    } catch (error) {
      c.tell(error.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = waveVisuals(context),
        canEdit = c.canControl && !busy && retiring.isEmpty;
    return Listener(
      onPointerMove: (event) => pointer = event.position,
      onPointerDown: (event) => pointer = event.position,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('queue-add'),
              onPressed: canEdit
                  ? () => showWaveDialog<void>(
                      context: context,
                      builder: (_) => QueueAddDialog(controller: c),
                    )
                  : null,
              icon: const Icon(Icons.add_rounded),
              label: Text(ecosystemText('queueAdd', context)),
            ),
          ),
          ReorderableListView.builder(
            key: const Key('native-queue-list'),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: rows.length,
            proxyDecorator: (child, index, animation) => AnimatedBuilder(
              animation: animation,
              child: child,
              builder: (_, child) {
                final lift = Curves.easeOutCubic.transform(animation.value);
                return Transform.translate(
                  offset: Offset(0, -5 * lift),
                  child: Transform.rotate(
                    angle: -.009 * lift,
                    child: Transform.scale(
                      scale: 1 + .025 * lift,
                      child: Material(
                        key: const Key('queue-lifted-proxy'),
                        color: v.surface,
                        elevation: 18 * lift,
                        shadowColor: Colors.black.withValues(alpha: .35),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(v.corners(14)),
                          side: BorderSide(
                            color: v.accent.withValues(alpha: .3),
                          ),
                        ),
                        child: child,
                      ),
                    ),
                  ),
                );
              },
            ),
            onReorderStart: (index) {
              setState(() => picked = index);
              edgeScroll?.cancel();
              edgeScroll = Timer.periodic(
                const Duration(milliseconds: 20),
                (_) => scrollEdge(),
              );
            },
            onReorderEnd: (_) {
              edgeScroll?.cancel();
              picked = null;
            },
            onReorder: (from, to) {
              if (!canEdit) return;
              if (to > from) to--;
              if (from == to) return;
              setState(() {
                final item = rows.removeAt(from);
                rows.insert(to, item);
                picked = null;
                signature = null;
              });
              unawaited(run(() => c.moveQueue(from, to)));
            },
            itemBuilder: (context, index) {
              final entry = rows[index],
                  track = entry.track,
                  active = c.audio.viewCurrent?.id == track.id;
              return _QueueSettlement(
                key: ValueKey(entry.key),
                duration: v.duration(230),
                curve: Curves.easeInOutCubic,
                alignment: Alignment.topCenter,
                child: retiring.contains(entry.key)
                    ? const SizedBox(width: double.infinity)
                    : ReorderableDelayedDragStartListener(
                        index: index,
                        enabled: canEdit,
                        child: Material(
                          color: active
                              ? v.accentSoft.withValues(alpha: .4)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(v.corners(14)),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 7,
                              horizontal: 3,
                            ),
                            child: Row(
                              children: [
                                if (canEdit)
                                  grip(
                                    index,
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        2,
                                        12,
                                        5,
                                        12,
                                      ),
                                      child: Icon(
                                        Icons.drag_indicator_rounded,
                                        color: v.muted,
                                        size: 17,
                                      ),
                                    ),
                                    canEdit,
                                  ),
                                InkWell(
                                  key: Key('queue-cover-${track.id}'),
                                  onTap: c.canControl
                                      ? () => run(
                                          () => c.play(
                                            track,
                                            list: c.audio.viewTracks,
                                            preserveWave: c.waveActive,
                                          ),
                                        )
                                      : null,
                                  borderRadius: BorderRadius.circular(
                                    v.corners(10),
                                  ),
                                  child: Artwork(
                                    controller: c,
                                    url: track.artwork,
                                    size: 42,
                                    radius: 10,
                                    trackLoading: active && c.trackLoading,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: InkWell(
                                    onTap: c.canControl
                                        ? () => run(
                                            () => c.play(
                                              track,
                                              list: c.audio.viewTracks,
                                              preserveWave: c.waveActive,
                                            ),
                                          )
                                        : null,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          track.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          track.artist,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: v.muted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                if (active)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                    ),
                                    child: ListeningWave(
                                      playing: c.audio.playing,
                                      size: 15,
                                    ),
                                  ),
                                PopupMenuButton<String>(
                                  key: Key('queue-actions-${track.id}'),
                                  icon: Icon(
                                    Icons.more_horiz_rounded,
                                    size: 19,
                                    color: v.muted,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                      v.corners(12),
                                    ),
                                  ),
                                  itemBuilder: (_) => [
                                    if (canEdit && index > 0)
                                      PopupMenuItem(
                                        value: 'up',
                                        child: Text(
                                          ecosystemText('up', context),
                                        ),
                                      ),
                                    if (canEdit && index < rows.length - 1)
                                      PopupMenuItem(
                                        value: 'down',
                                        child: Text(
                                          ecosystemText('down', context),
                                        ),
                                      ),
                                    if (canEdit)
                                      PopupMenuItem(
                                        value: 'remove',
                                        child: Text(
                                          ecosystemText('remove', context),
                                        ),
                                      ),
                                  ],
                                  onSelected: (action) => run(
                                    () => action == 'remove'
                                        ? c.removeQueueAt(index)
                                        : c.moveQueue(
                                            index,
                                            action == 'up'
                                                ? index - 1
                                                : index + 1,
                                          ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class QueueAddDialog extends StatefulWidget {
  final WaveController controller;
  const QueueAddDialog({super.key, required this.controller});
  @override
  State<QueueAddDialog> createState() => _QueueAddDialogState();
}

class _QueueAddDialogState extends State<QueueAddDialog> {
  final input = TextEditingController();
  Timer? timer;
  int generation = 0;
  bool pending = false;
  String? error;
  List<WaveTrack> found = [];
  WaveController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    found = List.of(c.tracks);
    c.addListener(changed);
  }

  void changed() {
    if (mounted) setState(() {});
  }

  void query(String value) {
    timer?.cancel();
    final revision = ++generation;
    setState(() => error = null);
    if (value.trim().isEmpty) {
      setState(() => found = List.of(c.tracks));
      return;
    }
    setState(
      () => found = c.tracks
          .where(
            (t) => '${t.title} ${t.artist}'.toLowerCase().contains(
              value.toLowerCase(),
            ),
          )
          .toList(),
    );
    if (!c.online) return;
    timer = Timer(const Duration(milliseconds: 300), () async {
      setState(() => pending = true);
      try {
        final data = await c.api.call(
          '/api/search',
          query: {'q': value.trim(), 'source': 'all'},
        );
        if (mounted && generation == revision) {
          setState(
            () => found = objects(data['tracks']).map(WaveTrack.new).toList(),
          );
        }
      } catch (e) {
        if (mounted && generation == revision) {
          setState(() => error = e.toString());
        }
      } finally {
        if (mounted && generation == revision) setState(() => pending = false);
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    generation++;
    c.removeListener(changed);
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(ecosystemText('queueAdd', context)),
    content: SizedBox(
      width: 460,
      height: 360,
      child: Column(
        children: [
          TextField(
            key: const Key('queue-search'),
            controller: input,
            onChanged: query,
            decoration: InputDecoration(
              hintText: ecosystemText('queueSearch', context),
              prefixIcon: const Icon(Icons.search_rounded),
            ),
          ),
          if (pending) const LinearProgressIndicator(minHeight: 2),
          if (error != null) Text(error!, maxLines: 2),
          Expanded(
            child: ListView(
              children: [
                for (final track in found)
                  ListTile(
                    leading: Artwork(
                      controller: c,
                      url: track.artwork,
                      size: 40,
                    ),
                    title: Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),
                    subtitle: Text(
                      track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: IconButton(
                      key: Key('enqueue-${track.id}'),
                      tooltip: ecosystemText('queueAdd', context),
                      onPressed:
                          c.canControl &&
                              !c.audio.viewTracks.any((t) => t.id == track.id)
                          ? () async {
                              try {
                                await c.addQueue(track);
                                if (mounted) setState(() {});
                              } catch (e) {
                                c.tell(e.toString());
                              }
                            }
                          : null,
                      icon: Icon(
                        c.audio.viewTracks.any((t) => t.id == track.id)
                            ? Icons.check_rounded
                            : Icons.add_rounded,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(MaterialLocalizations.of(context).closeButtonLabel),
      ),
    ],
  );
}

class _QueueSettlement extends StatelessWidget {
  final Duration duration;
  final Curve curve;
  final AlignmentGeometry alignment;
  final Widget child;
  const _QueueSettlement({
    super.key,
    required this.duration,
    required this.curve,
    required this.alignment,
    required this.child,
  });
  @override
  Widget build(BuildContext context) => duration == Duration.zero
      ? child
      : AnimatedSize(
          duration: duration,
          curve: curve,
          alignment: alignment,
          child: child,
        );
}
