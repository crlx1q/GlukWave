import '../l10n/wave_localizations.dart';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import '../core/controller.dart';
import '../core/models.dart';
import 'widgets.dart';
import 'volume_slider.dart';
import 'equalizer_panel.dart';
import 'album_stage.dart';
import 'player_gestures.dart';

class MiniPlayer extends StatelessWidget {
  final WaveController controller;
  final VoidCallback onOpen;
  final Key? artworkKey;
  final VoidCallback? onDragStart, onDragCancel;
  final ValueChanged<double>? onDragUpdate, onDragEnd;
  const MiniPlayer({
    super.key,
    required this.controller,
    required this.onOpen,
    this.artworkKey,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
    this.onDragCancel,
  });
  @override
  Widget build(BuildContext context) {
    final c = controller, track = c.audio.viewCurrent;
    final v = waveVisuals(context);
    final compact = MediaQuery.sizeOf(context).width < 800;
    return ClipRRect(
      borderRadius: BorderRadius.circular(
        waveRadius(context, compact ? 13 : 22),
      ),
      child: Material(
        color: v.player,
        child: SizedBox(
          height: compact || v.compact ? 66 : 84,
          child: Column(
            children: [
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 8 : 18,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: PlayerGestureSurface(
                          key: const Key('mini-gesture'),
                          controller: c,
                          opensPlayer: true,
                          onVerticalStart: onDragStart,
                          onVerticalUpdate: onDragUpdate,
                          onVerticalEnd: onDragEnd,
                          onVerticalCancel: onDragCancel,
                          child: InkWell(
                            onTap: onOpen,
                            child: Row(
                              children: [
                                if (track != null)
                                  Artwork(
                                    key: artworkKey,
                                    controller: c,
                                    url: track.artwork,
                                    size: compact ? 44 : 52,
                                    radius: 8,
                                  ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        track?.title ??
                                            wt(
                                              'native.899c8de911',
                                              context: context,
                                            ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: v.onPlayer,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 13,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        track?.artist ??
                                            wt(
                                              'native.b196b73079',
                                              context: context,
                                            ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: v.onPlayer.withValues(
                                            alpha: .7,
                                          ),
                                          fontSize: 10,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (track != null)
                        IconButton(
                          key: const Key('mini-like'),
                          tooltip: c.likedIds.contains(track.id)
                              ? wt('native.4ddf34c036', context: context)
                              : wt('native.5633e5c745', context: context),
                          constraints: const BoxConstraints(
                            minWidth: 44,
                            minHeight: 44,
                          ),
                          onPressed: c.online
                              ? () => _run(c, () => c.like(track))
                              : null,
                          icon: Icon(
                            c.likedIds.contains(track.id)
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            color: c.likedIds.contains(track.id)
                                ? v.accent
                                : v.onPlayer.withValues(alpha: .7),
                            size: 21,
                          ),
                        ),
                      if (!compact)
                        IconButton(
                          tooltip: wt('native.8e1abb9475', context: context),
                          onPressed: c.canControl
                              ? () => _run(c, c.audio.skipToPrevious)
                              : null,
                          icon: Icon(
                            Icons.skip_previous_rounded,
                            color: v.onPlayer,
                          ),
                        ),
                      StreamBuilder<PlaybackState>(
                        stream: c.audio.playbackState,
                        builder: (context, state) {
                          final busy = const [
                            AudioProcessingState.buffering,
                            AudioProcessingState.loading,
                          ].contains(state.data?.processingState);
                          return IconButton.filled(
                            tooltip: c.audio.playing
                                ? wt('native.03498e395a', context: context)
                                : wt('native.c750dc7d94', context: context),
                            style: IconButton.styleFrom(
                              backgroundColor: v.onPlayer,
                              foregroundColor: v.player,
                              minimumSize: const Size(44, 44),
                              maximumSize: const Size(44, 44),
                            ),
                            onPressed: c.canControl && track != null
                                ? () => _run(
                                    c,
                                    c.audio.playing
                                        ? c.audio.pause
                                        : c.audio.play,
                                  )
                                : null,
                            icon: busy
                                ? SizedBox(
                                    width: 17,
                                    height: 17,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: v.player,
                                    ),
                                  )
                                : Icon(
                                    c.audio.playing
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    size: 23,
                                  ),
                          );
                        },
                      ),
                      if (!compact)
                        IconButton(
                          tooltip: wt('native.c97fa8b29b', context: context),
                          onPressed: c.canControl
                              ? () => _run(c, c.audio.skipToNext)
                              : null,
                          icon: Icon(
                            Icons.skip_next_rounded,
                            color: v.onPlayer,
                            size: 23,
                          ),
                        ),
                      if (!compact)
                        IconButton(
                          key: const Key('mini-equalizer'),
                          tooltip: wt('eq.title', context: context),
                          onPressed: () => showPlayerEqualizer(context, c),
                          icon: Icon(
                            Icons.graphic_eq_rounded,
                            color: v.onPlayer.withValues(alpha: .7),
                            size: 19,
                          ),
                        ),
                      if (!compact)
                        SizedBox(
                          width: 130,
                          child: Row(
                            children: [
                              Icon(
                                Icons.volume_up_outlined,
                                color: v.onPlayer.withValues(alpha: .65),
                                size: 19,
                              ),
                              Expanded(
                                child: VolumeSlider(
                                  value: c.audio.volume.clamp(0, 1),
                                  onChanged: (value) => _run(
                                    c,
                                    () => c.transport('volume', {
                                      'volume': value,
                                    }),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (!compact)
                        IconButton(
                          tooltip: wt('native.d66131f711', context: context),
                          onPressed: onOpen,
                          icon: Icon(
                            Icons.open_in_full_rounded,
                            color: v.onPlayer,
                            size: 19,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              StreamBuilder<Duration>(
                stream: c.audio.positionStream,
                builder: (context, snapshot) {
                  final total = c.audio.duration?.inMilliseconds ?? 0;
                  return LinearProgressIndicator(
                    value: total > 0
                        ? ((snapshot.data?.inMilliseconds ?? 0) / total).clamp(
                            0,
                            1,
                          )
                        : 0,
                    minHeight: 2,
                    color: v.accent,
                    backgroundColor: v.onPlayer.withValues(alpha: .12),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _run(WaveController c, Future<void> Function() action) async {
  try {
    await action();
  } catch (error) {
    c.tell(error.toString());
  }
}

Future<void> showPlayerEqualizer(BuildContext context, WaveController c) =>
    showWaveDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(wt('eq.title', context: dialog)),
        content: SizedBox(
          width: 580,
          child: SingleChildScrollView(
            child: AnimatedBuilder(
              animation: c,
              builder: (_, _) => EqualizerPanel(controller: c),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: Text(wt('native.398c7d4f7b', context: dialog)),
          ),
        ],
      ),
    );

class PlayerPage extends StatefulWidget {
  final WaveController controller;
  final WaveTrack? initialTrack;
  final void Function(WaveTrack) onMore;
  final VoidCallback? onClose, onDragStart, onDragCancel;
  final ValueChanged<double>? onDragUpdate, onDragEnd;
  final Key? artworkKey;
  final bool hideAlbum;
  const PlayerPage({
    super.key,
    required this.controller,
    this.initialTrack,
    required this.onMore,
    this.onClose,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
    this.onDragCancel,
    this.artworkKey,
    this.hideAlbum = false,
  });
  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  WaveController get c => widget.controller;
  WaveTrack? current;
  List<Json> lyrics = [], comments = [];
  bool synchronized = false, loading = false;
  String? error;
  int tab = 0, _load = 0;
  final comment = TextEditingController();
  final _tabsScroll = ScrollController();
  final _tabKeys = List<GlobalKey>.generate(4, (_) => GlobalKey());
  StreamSubscription<MediaItem?>? _media;
  @override
  void initState() {
    super.initState();
    current = widget.initialTrack ?? c.audio.viewCurrent;
    unawaited(loadDetails());
    if (widget.initialTrack == null) {
      _media = c.audio.mediaItem.listen((item) {
        if (!mounted) return;
        final track = c.audio.viewCurrent;
        if (track?.id != current?.id) {
          setState(() {
            current = track;
            lyrics = [];
            comments = [];
          });
          unawaited(loadDetails());
        }
      });
    }
  }

  Future<void> loadDetails() async {
    if (current == null) return;
    final revision = ++_load, id = current!.id;
    if (mounted) {
      setState(() {
        loading = true;
        error = null;
      });
    }
    try {
      final result = await Future.wait([
        c.api.call('/api/tracks/$id/lyrics'),
        c.api.call('/api/tracks/$id/comments'),
      ]);
      if (!mounted || revision != _load) return;
      setState(() {
        lyrics = objects(result[0]['lines']);
        synchronized = result[0]['synchronized'] == true;
        comments = objects(result[1]['comments']);
      });
    } catch (e) {
      if (mounted && revision == _load) setState(() => error = e.toString());
    } finally {
      if (mounted && revision == _load) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    unawaited(_media?.cancel());
    comment.dispose();
    _tabsScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, child) {
      if (current == null) {
        return Center(
          child: EmptyState(
            wt('native.11bf0a5893', context: context),
            wt('native.a1d6afb1b3', context: context),
          ),
        );
      }
      final track = current!;
      final wide = MediaQuery.sizeOf(context).width >= 900;
      final v = waveVisuals(context);
      return Stack(
        children: [
          if (v.blur && track.artwork.isNotEmpty)
            Positioned.fill(
              child: IgnorePointer(
                child: Opacity(
                  opacity: v.brightness == Brightness.dark ? .22 : .1,
                  child: ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(sigmaX: 48, sigmaY: 48),
                    child: LayoutBuilder(
                      builder: (_, constraints) => Center(
                        child: Artwork(
                          controller: c,
                          url: track.artwork,
                          radius: 0,
                          size: constraints.biggest.longestSide,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: wt('native.590b94553f', context: context),
                      onPressed: widget.onClose ?? () => Navigator.pop(context),
                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                    ),
                    Expanded(
                      child: PlayerGestureSurface(
                        key: const Key('player-dismiss-handle'),
                        controller: c,
                        onVerticalStart: widget.onDragStart,
                        onVerticalUpdate: widget.onDragUpdate,
                        onVerticalEnd: widget.onDragEnd,
                        onVerticalCancel: widget.onDragCancel,
                        child: Column(
                          children: [
                            Text(
                              wt('native.b1b410f065', context: context),
                              style: TextStyle(
                                color: waveVisuals(context).muted,
                                letterSpacing: 1.5,
                                fontSize: 8,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              c.room?['name'] as String? ?? track.sourceName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: wt('native.30ef88c9b5', context: context),
                      onPressed: () => widget.onMore(track),
                      icon: const Icon(Icons.more_horiz_rounded),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 26),
                child: playerTabs(),
              ),
              if (loading)
                LinearProgressIndicator(
                  minHeight: 2,
                  color: waveVisuals(context).accent,
                ),
              Expanded(
                child: wide && tab != 2
                    ? Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 56),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 28,
                                ),
                                child: listening(track),
                              ),
                            ),
                            const SizedBox(width: 56),
                            Expanded(
                              child: SingleChildScrollView(
                                key: Key(
                                  tab == 0
                                      ? 'desktop-lyrics-scroll'
                                      : 'player-content-scroll',
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 28,
                                ),
                                child: tab == 3
                                    ? commentPage(track)
                                    : lyricPage(track),
                              ),
                            ),
                          ],
                        ),
                      )
                    : SingleChildScrollView(
                        key: const Key('player-content-scroll'),
                        padding: const EdgeInsets.fromLTRB(27, 26, 27, 30),
                        child: switch (tab) {
                          1 => lyricPage(track),
                          2 => queuePage(),
                          3 => commentPage(track),
                          _ => listening(track),
                        },
                      ),
              ),
              if (!wide && tab != 0 && c.audio.viewCurrent != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 4, 18, 16),
                  child: MiniPlayer(
                    controller: c,
                    onOpen: () => setState(() => tab = 0),
                  ),
                ),
            ],
          ),
        ],
      );
    },
  );
  Widget playerTabs() => LayoutBuilder(
    builder: (context, constraints) {
      final labels = [
        wt('native.28ca76fdd0', context: context),
        wt('native.93970437e2', context: context),
        wt('native.aec93b16ba', context: context),
        wt('native.f1401a6c61', context: context),
      ];
      final style = Theme.of(context).textTheme.bodyMedium!.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w800,
      );
      final widths = labels.map((label) {
        final text = TextPainter(
          text: TextSpan(text: label, style: style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        final width = (text.width + 24).clamp(64.0, double.infinity);
        text.dispose();
        return width;
      }).toList();
      final equalWidth = constraints.maxWidth / labels.length;
      final fits = widths.every((width) => width <= equalWidth);
      Widget button(int index) => Semantics(
        selected: tab == index,
        button: true,
        child: InkWell(
          key: _tabKeys[index],
          onTap: () {
            setState(() => tab = index);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              final box = _tabKeys[index].currentContext?.findRenderObject();
              if (mounted && _tabsScroll.hasClients && box != null) {
                _tabsScroll.position.ensureVisible(box, alignment: .5);
              }
            });
          },
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: tab == index
                      ? waveVisuals(context).ink
                      : waveVisuals(context).line,
                  width: tab == index ? 2 : 1,
                ),
              ),
            ),
            child: Text(
              labels[index],
              key: Key('player-tab-label-$index'),
              maxLines: 1,
              softWrap: false,
              textAlign: TextAlign.center,
              style: style.copyWith(
                fontWeight: tab == index ? FontWeight.w800 : FontWeight.w500,
                color: tab == index
                    ? waveVisuals(context).ink
                    : waveVisuals(context).muted,
              ),
            ),
          ),
        ),
      );
      final row = Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            if (fits)
              Expanded(child: button(i))
            else
              SizedBox(width: widths[i], child: button(i)),
        ],
      );
      return fits
          ? row
          : Scrollbar(
              controller: _tabsScroll,
              thumbVisibility: true,
              thickness: 2,
              child: SingleChildScrollView(
                key: const Key('player-tabs-scroll'),
                controller: _tabsScroll,
                scrollDirection: Axis.horizontal,
                child: row,
              ),
            );
    },
  );
  Widget listening(WaveTrack track) => LayoutBuilder(
    builder: (context, constraints) {
      final size = (constraints.maxWidth * .94).clamp(170.0, 400.0);
      final active = c.audio.viewCurrent?.id == track.id;
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 530),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PlayerGestureSurface(
              key: const Key('player-cover-gesture'),
              controller: c,
              onVerticalStart: widget.onDragStart,
              onVerticalUpdate: widget.onDragUpdate,
              onVerticalEnd: widget.onDragEnd,
              onVerticalCancel: widget.onDragCancel,
              child: Opacity(
                opacity: widget.hideAlbum ? 0 : 1,
                child: AlbumStage(
                  controller: c,
                  track: track,
                  size: size,
                  playing: active && c.audio.playing,
                  artworkKey: widget.artworkKey,
                  touchTilt: false,
                ),
              ),
            ),
            if (MediaQuery.sizeOf(context).width >= 900)
              Wrap(
                spacing: 5,
                runSpacing: 2,
                children: [
                  TextButton.icon(
                    onPressed: () => _run(
                      c,
                      () => c.customize({
                        'appearance': {
                          'cover3d': !c.customization.appearance.cover3d,
                        },
                      }),
                    ),
                    icon: Icon(
                      c.customization.appearance.cover3d
                          ? Icons.view_in_ar_outlined
                          : Icons.crop_square_rounded,
                      size: 16,
                    ),
                    label: Text(
                      c.customization.appearance.cover3d
                          ? wt('native.e7797473dd', context: context)
                          : wt('native.b3fae20397', context: context),
                      style: const TextStyle(fontSize: 10),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _run(
                      c,
                      () => c.customize({
                        'appearance': {
                          'coverKind':
                              c.customization.appearance.coverKind == 'vinyl'
                              ? 'cd'
                              : 'vinyl',
                        },
                      }),
                    ),
                    child: Text(
                      c.customization.appearance.coverKind == 'vinyl'
                          ? 'VINYL'
                          : 'CD',
                      style: TextStyle(
                        fontSize: 10,
                        color: waveVisuals(context).muted,
                      ),
                    ),
                  ),
                ],
              ),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.title,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -.8,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        track.artist,
                        style: TextStyle(
                          color: waveVisuals(context).muted,
                          fontSize: 13,
                        ),
                      ),
                      if (track.album.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            track.album,
                            style: TextStyle(
                              color: waveVisuals(context).muted,
                              fontSize: 11,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: wt('native.36f30bdb01', context: context),
                  onPressed: c.online
                      ? () => _run(c, () => c.like(track))
                      : null,
                  icon: Icon(
                    c.likedIds.contains(track.id)
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    color: c.likedIds.contains(track.id)
                        ? waveVisuals(context).accent
                        : waveVisuals(context).muted,
                    size: 25,
                  ),
                ),
              ],
            ),
            if (active) ...[
              const SizedBox(height: 18),
              progress(track),
              const SizedBox(height: 9),
              transport(),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 4,
                runSpacing: 2,
                children: [
                  IconButton(
                    key: const Key('player-equalizer'),
                    tooltip: wt('eq.title', context: context),
                    onPressed: () => showPlayerEqualizer(context, c),
                    icon: Icon(
                      Icons.graphic_eq_rounded,
                      size: 20,
                      color: waveVisuals(context).muted,
                    ),
                  ),
                  IconButton(
                    tooltip: wt('native.621777004a', context: context),
                    onPressed: () => showVolume(),
                    icon: Icon(
                      Icons.volume_up_outlined,
                      size: 20,
                      color: waveVisuals(context).muted,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => setState(() => tab = 2),
                    icon: const Icon(Icons.queue_music, size: 18),
                    label: Text(
                      wt('native.aec93b16ba', context: context),
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                  if (track.offline)
                    TextButton.icon(
                      onPressed: () =>
                          _run(c, () => c.cache.save(track, manual: true)),
                      icon: Icon(
                        c.cache.contains(track.id)
                            ? Icons.offline_pin_outlined
                            : Icons.download_rounded,
                        size: 18,
                      ),
                      label: Text(
                        wt('native.ca25d9c93e', context: context),
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                ],
              ),
            ] else ...[
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _run(
                    c,
                    () => track.playable
                        ? c.play(track)
                        : c.openUrl(track.sourceUrl),
                  ),
                  icon: Icon(
                    track.playable
                        ? Icons.play_arrow_rounded
                        : Icons.open_in_new_rounded,
                  ),
                  label: Text(
                    track.playable
                        ? wt('native.b09bf87fd9', context: context)
                        : wt(
                            'native.58ef1d8c95',
                            values: {'p0': (track.sourceName)},
                            context: context,
                          ),
                  ),
                ),
              ),
            ],
            if (!track.playable)
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: Text(
                  wt(
                    'native.ffe3af5890',
                    values: {'p0': (track.sourceName)},
                    context: context,
                  ),
                  style: TextStyle(
                    fontSize: 11,
                    color: waveVisuals(context).muted,
                    height: 1.7,
                  ),
                ),
              ),
            if (c.settings['lyrics'] == true && lyrics.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 26),
                child: StreamBuilder<Duration>(
                  stream: c.audio.positionStream,
                  builder: (_, snapshot) {
                    final index = synchronized && active
                        ? activeLyric(
                            lyrics,
                            (snapshot.data?.inMilliseconds ?? 0) / 1000,
                          )
                        : 0;
                    return InkWell(
                      onTap: () => setState(() => tab = 1),
                      child: Surface(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              wt('native.5a13cba854', context: context),
                              style: TextStyle(
                                fontSize: 8,
                                letterSpacing: 1.5,
                                color: waveVisuals(context).muted,
                              ),
                            ),
                            const SizedBox(height: 12),
                            AnimatedSwitcher(
                              duration: Duration(
                                milliseconds:
                                    c.settings['reducedMotion'] == true
                                    ? 0
                                    : 280,
                              ),
                              child: Text(
                                lyrics[index.clamp(
                                          0,
                                          lyrics.length - 1,
                                        )]['text']
                                        as String? ??
                                    '',
                                key: ValueKey(index),
                                style: const TextStyle(
                                  fontSize: 25,
                                  fontWeight: FontWeight.w800,
                                  height: 1.25,
                                  letterSpacing: -.6,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      );
    },
  );
  Widget progress(WaveTrack track) => StreamBuilder<Duration>(
    stream: c.audio.positionStream,
    builder: (context, snapshot) {
      final total =
          c.audio.duration?.inMilliseconds.toDouble() ?? track.duration * 1000;
      final current = (snapshot.data?.inMilliseconds ?? 0)
          .toDouble()
          .clamp(0, total > 0 ? total : 1)
          .toDouble();
      return Column(
        children: [
          Slider(
            value: current,
            max: total > 0 ? total : 1,
            onChanged: c.canControl && total > 0
                ? (v) => _run(
                    c,
                    () => c.audio.seek(Duration(milliseconds: v.round())),
                  )
                : null,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  clock(current / 1000),
                  style: TextStyle(
                    color: waveVisuals(context).muted,
                    fontSize: 10,
                  ),
                ),
                const Spacer(),
                Text(
                  clock(total / 1000),
                  style: TextStyle(
                    color: waveVisuals(context).muted,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    },
  );
  Widget transport() => Row(
    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
    children: [
      IconButton(
        tooltip: wt('native.d8a9b54429', context: context),
        onPressed: () => _run(
          c,
          () => c.audio.setShuffleMode(
            c.audio.shuffle
                ? AudioServiceShuffleMode.none
                : AudioServiceShuffleMode.all,
          ),
        ),
        icon: Icon(
          Icons.shuffle_rounded,
          color: c.audio.shuffle
              ? waveVisuals(context).accent
              : waveVisuals(context).muted,
          size: 23,
        ),
      ),
      IconButton(
        tooltip: wt('native.3a2d254d6e', context: context),
        onPressed: c.canControl
            ? () => _run(c, () => c.audio.skipToPrevious())
            : null,
        icon: const Icon(Icons.skip_previous_rounded, size: 33),
      ),
      IconButton.filled(
        tooltip: c.audio.playing
            ? wt('native.03498e395a', context: context)
            : wt('native.c750dc7d94', context: context),
        onPressed: c.canControl
            ? () => _run(
                c,
                () => c.audio.playing ? c.audio.pause() : c.audio.play(),
              )
            : null,
        style: IconButton.styleFrom(
          minimumSize: const Size(66, 66),
          backgroundColor: waveVisuals(context).ink,
          foregroundColor: waveVisuals(context).background,
        ),
        icon: Icon(
          c.audio.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
          size: 32,
        ),
      ),
      IconButton(
        tooltip: wt('native.e9c094d2a9', context: context),
        onPressed: c.canControl
            ? () => _run(c, () => c.audio.skipToNext())
            : null,
        icon: const Icon(Icons.skip_next_rounded, size: 33),
      ),
      IconButton(
        tooltip: wt(
          'native.9089f12327',
          values: {
            'p0': (c.audio.repeat == AudioServiceRepeatMode.none
                ? wt('native.0b48cc8756', context: context)
                : c.audio.repeat == AudioServiceRepeatMode.one
                ? wt('native.81d73996e1', context: context)
                : wt('native.7d449210b8', context: context)),
          },
          context: context,
        ),
        onPressed: () => _run(
          c,
          () => c.audio.setRepeatMode(switch (c.audio.repeat) {
            AudioServiceRepeatMode.none => AudioServiceRepeatMode.all,
            AudioServiceRepeatMode.all => AudioServiceRepeatMode.one,
            _ => AudioServiceRepeatMode.none,
          }),
        ),
        icon: Icon(
          c.audio.repeat == AudioServiceRepeatMode.one
              ? Icons.repeat_one_rounded
              : Icons.repeat_rounded,
          color: c.audio.repeat == AudioServiceRepeatMode.none
              ? waveVisuals(context).muted
              : waveVisuals(context).accent,
          size: 23,
        ),
      ),
    ],
  );
  Future<void> showVolume() => showWaveDialog<void>(
    context: context,
    builder: (_) => AnimatedBuilder(
      animation: c,
      builder: (_, child) => AlertDialog(
        title: Text(wt('native.621777004a', context: context)),
        content: SizedBox(
          width: 300,
          child: Slider(
            value: c.audio.volume.clamp(0, 1),
            onChanged: (v) =>
                _run(c, () => c.transport('volume', {'volume': v})),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(wt('native.398c7d4f7b', context: context)),
          ),
        ],
      ),
    ),
  );
  Widget lyricPage(WaveTrack track) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              synchronized
                  ? wt('native.ff780900c5', context: context)
                  : wt('native.7ad990dd63', context: context),
              style: TextStyle(
                fontSize: 9,
                letterSpacing: 1.4,
                color: waveVisuals(context).muted,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: c.online && c.loggedIn ? importLyrics : null,
            icon: const Icon(Icons.edit_outlined, size: 16),
            label: Text(
              wt('native.1aea079cdb', context: context),
              style: TextStyle(fontSize: 11),
            ),
          ),
        ],
      ),
      if (loading && lyrics.isEmpty)
        Padding(
          padding: EdgeInsets.only(top: 26),
          child: WaveLoadingList(
            rows: 4,
            label: wt('native.3d92401582', context: context),
          ),
        )
      else if (lyrics.isEmpty)
        EmptyState(
          wt('native.8f61423be2', context: context),
          error ?? wt('native.6774e0dd9c', context: context),
          icon: Icons.lyrics_outlined,
          action: c.online && c.loggedIn
              ? OutlinedButton(
                  onPressed: importLyrics,
                  child: Text(wt('native.0c37b5a035', context: context)),
                )
              : null,
        )
      else
        StreamBuilder<Duration>(
          stream: c.audio.positionStream,
          builder: (_, snapshot) {
            final active = synchronized && c.audio.viewCurrent?.id == track.id
                ? activeLyric(
                    lyrics,
                    (snapshot.data?.inMilliseconds ?? 0) / 1000,
                  )
                : -1;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 25),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < lyrics.length; i++)
                    InkWell(
                      onTap:
                          synchronized &&
                              c.canControl &&
                              c.audio.viewCurrent?.id == track.id
                          ? () => _run(
                              c,
                              () => c.audio.seek(
                                Duration(
                                  milliseconds:
                                      (number(lyrics[i]['time']) * 1000)
                                          .round(),
                                ),
                              ),
                            )
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: AnimatedDefaultTextStyle(
                          duration: waveVisuals(context).duration(220),
                          curve: Curves.easeOut,
                          style: TextStyle(
                            fontFamily: Theme.of(
                              context,
                            ).textTheme.bodyMedium?.fontFamily,
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -.7,
                            height: 1.3,
                            color: active < 0 || active == i
                                ? waveVisuals(context).ink
                                : waveVisuals(context).muted,
                          ),
                          child: Text(lyrics[i]['text'] as String? ?? ''),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
    ],
  );
  Future<void> importLyrics() async {
    final track = current!;
    final text = TextEditingController(
      text: lyrics
          .map(
            (line) => synchronized && line['time'] != null
                ? '[${lrcClock(number(line['time']))}]${line['text']}'
                : line['text'],
          )
          .join('\n'),
    );
    final title = TextEditingController(text: track.title),
        artist = TextEditingController(text: track.artist);
    List<Json>? candidates;
    Json? selected;
    var busy = false;
    await showWaveDialog<void>(
      context: context,
      builder: (outer) => StatefulBuilder(
        builder: (dialog, update) => AlertDialog(
          title: Text(wt('native.da4b2995ca', context: context)),
          content: SizedBox(
            width: 550,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: title,
                    maxLength: 200,
                    decoration: InputDecoration(
                      labelText: wt('lyrics.title', context: context),
                    ),
                  ),
                  TextField(
                    controller: artist,
                    maxLength: 200,
                    decoration: InputDecoration(
                      labelText: wt('lyrics.artist', context: context),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      icon: const Icon(Icons.search),
                      label: Text(wt('lyrics.search', context: context)),
                      onPressed: busy
                          ? null
                          : () async {
                              update(() => busy = true);
                              try {
                                final result = await c.api.call(
                                  '/api/tracks/${track.id}/lyrics/search',
                                  query: {
                                    'title': title.text,
                                    'artist': artist.text,
                                  },
                                );
                                if (dialog.mounted) {
                                  update(
                                    () => candidates = objects(
                                      result['candidates'],
                                    ),
                                  );
                                }
                              } catch (error) {
                                c.tell(error.toString());
                              } finally {
                                if (dialog.mounted) update(() => busy = false);
                              }
                            },
                    ),
                  ),
                  if (busy) const LinearProgressIndicator(),
                  if (candidates != null && candidates!.isEmpty)
                    Text(wt('lyrics.none', context: context)),
                  if (candidates != null)
                    ...candidates!.map(
                      (candidate) => ListTile(
                        selected:
                            selected?['providerId'] == candidate['providerId'],
                        title: Text(candidate['title'] as String? ?? ''),
                        subtitle: Text(
                          '${candidate['artist']} · ${candidate['synchronized'] == true ? wt('lyrics.synced', context: context) : wt('lyrics.plain', context: context)}',
                        ),
                        onTap: () => update(() {
                          selected = candidate;
                          text.text = candidate['raw'] as String? ?? '';
                        }),
                      ),
                    ),
                  TextField(
                    controller: text,
                    minLines: 8,
                    maxLines: 15,
                    maxLength: 100000,
                    decoration: InputDecoration(
                      labelText: wt('native.c157a9e867', context: context),
                      hintText: wt('native.59f2a68e7e', context: context),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    wt('lyrics.attribution', context: context),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: Text(wt('native.0ec753be8d', context: context)),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      update(() => busy = true);
                      await _run(c, () async {
                        if (selected != null && text.text == selected!['raw']) {
                          await c.api.call(
                            '/api/tracks/${track.id}/lyrics/lrclib',
                            method: 'POST',
                            data: {'providerId': selected!['providerId']},
                          );
                        } else {
                          await c.api.call(
                            '/api/tracks/${track.id}/lyrics',
                            method: 'PUT',
                            data: {'text': text.text},
                          );
                        }
                        if (dialog.mounted) Navigator.pop(dialog);
                        if (current?.id == track.id) await loadDetails();
                      });
                      if (dialog.mounted) update(() => busy = false);
                    },
              child: Text(wt('native.4864057d62', context: context)),
            ),
          ],
        ),
      ),
    );
    text.dispose();
    title.dispose();
    artist.dispose();
  }

  Widget queuePage() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        wt('native.5a187c8ad3', context: context),
        style: TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.w800,
          letterSpacing: -1,
        ),
      ),
      const SizedBox(height: 9),
      Text(
        wt(
          'native.bd71178379',
          values: {
            'p0': (c.audio.viewTracks.length),
            'p1': (c.room == null
                ? wt('native.90db49c312', context: context)
                : wt('native.b40415dfac', context: context)),
          },
          context: context,
        ),
        style: TextStyle(color: waveVisuals(context).muted, fontSize: 12),
      ),
      const SizedBox(height: 24),
      if (c.audio.viewTracks.isEmpty)
        EmptyState(
          wt('native.8c96dfdeaf', context: context),
          wt('native.f11290c0ba', context: context),
          icon: Icons.queue_music,
        ),
      for (final track in c.audio.viewTracks)
        TrackRow(
          controller: c,
          track: track,
          queue: c.audio.viewTracks,
          onMore: () => widget.onMore(track),
        ),
    ],
  );
  Widget commentPage(WaveTrack track) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        wt('native.3fe293662f', context: context),
        style: TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.w800,
          letterSpacing: -1,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        wt('native.35b3855a5f', context: context),
        style: TextStyle(color: waveVisuals(context).muted, fontSize: 12),
      ),
      const SizedBox(height: 22),
      if (track.duration > 0 && comments.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: SizedBox(
            height: 42,
            child: LayoutBuilder(
              builder: (_, constraints) => Stack(
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 21,
                    child: Divider(
                      color: waveVisuals(context).accent,
                      thickness: 2,
                    ),
                  ),
                  for (final entry in comments)
                    Positioned(
                      left:
                          (number(entry['position']) / track.duration).clamp(
                            0,
                            1,
                          ) *
                          (constraints.maxWidth - 28),
                      top: 4,
                      child: Tooltip(
                        message:
                            '${entry['displayName']} · ${clock(number(entry['position']))}',
                        child: GestureDetector(
                          onTap: () {
                            if (c.audio.viewCurrent?.id == track.id) {
                              _run(
                                c,
                                () => c.audio.seek(
                                  Duration(
                                    milliseconds:
                                        (number(entry['position']) * 1000)
                                            .round(),
                                  ),
                                ),
                              );
                            }
                          },
                          child: CircleAvatar(
                            radius: 14,
                            backgroundColor: waveVisuals(context).accentSoft,
                            child: Text(
                              (entry['displayName'] as String? ?? '?')
                                  .substring(0, 1),
                              style: TextStyle(
                                fontSize: 10,
                                color: waveVisuals(context).ink,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      Surface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: comment,
              maxLength: 1000,
              minLines: 2,
              maxLines: 5,
              decoration: InputDecoration(
                hintText: wt('native.b50bfb41fe', context: context),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  Icons.schedule_rounded,
                  size: 16,
                  color: waveVisuals(context).muted,
                ),
                const SizedBox(width: 8),
                Text(
                  clock(
                    c.audio.viewCurrent?.id == track.id
                        ? c.audio.position.inMilliseconds / 1000
                        : 0,
                  ),
                  style: TextStyle(
                    color: waveVisuals(context).muted,
                    fontSize: 11,
                  ),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: c.online
                      ? () => _run(c, () async {
                          if (comment.text.trim().isEmpty) return;
                          await c.api.call(
                            '/api/tracks/${track.id}/comments',
                            method: 'POST',
                            data: {
                              'text': comment.text.trim(),
                              'position': c.audio.viewCurrent?.id == track.id
                                  ? c.audio.position.inMilliseconds / 1000
                                  : 0,
                            },
                          );
                          comment.clear();
                          await loadDetails();
                        })
                      : null,
                  child: Text(wt('native.c65a7fd398', context: context)),
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 26),
      if (loading && comments.isEmpty)
        WaveLoadingList(
          rows: 3,
          label: wt('native.dcf664edf6', context: context),
        )
      else if (comments.isEmpty)
        EmptyState(
          wt('native.c51a972201', context: context),
          wt('native.5439c05c19', context: context),
          icon: Icons.chat_bubble_outline_rounded,
        ),
      for (final entry in comments)
        Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Artwork(
                controller: c,
                url: entry['avatarUrl'] as String?,
                size: 36,
                radius: 18,
                icon: Icons.person_outline,
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry['displayName'] as String? ?? '',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: c.audio.viewCurrent?.id == track.id
                              ? () => _run(
                                  c,
                                  () => c.audio.seek(
                                    Duration(
                                      milliseconds:
                                          (number(entry['position']) * 1000)
                                              .round(),
                                    ),
                                  ),
                                )
                              : null,
                          child: Text(
                            clock(number(entry['position'])),
                            style: TextStyle(
                              color: waveVisuals(context).accent,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SelectableText(
                      entry['text'] as String? ?? '',
                      style: const TextStyle(fontSize: 13, height: 1.7),
                    ),
                  ],
                ),
              ),
              if (entry['userId'] == c.user?.id || c.user?.admin == true)
                IconButton(
                  tooltip: wt('native.41eba7e6c0', context: context),
                  icon: Icon(
                    Icons.delete_outline,
                    size: 17,
                    color: waveVisuals(context).muted,
                  ),
                  onPressed: () => _run(c, () async {
                    await c.api.call(
                      '/api/comments/${entry['id']}',
                      method: 'DELETE',
                    );
                    await loadDetails();
                  }),
                ),
            ],
          ),
        ),
    ],
  );
}
