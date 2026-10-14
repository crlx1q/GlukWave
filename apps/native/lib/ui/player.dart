import 'scrolling_label.dart';
import 'native19_strings.dart';
import 'native19_desktop_transport.dart';
import 'cover_ambient.dart';
import 'seasonal.dart';
import 'lyrics_editor.dart';
import 'motion_icons.dart';
import '../l10n/wave_localizations.dart';
import '../l10n/focused_player_strings.dart';
import '../l10n/listening_polish_strings.dart';
import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import '../core/controller.dart';
import '../core/models.dart';
import 'widgets.dart';
import 'volume_slider.dart';
import 'equalizer_panel.dart';
import 'album_stage.dart';
import 'player_gestures.dart';
import 'queue_panel.dart';
import 'connect_picker.dart';
import 'listening_presence.dart';

class SourceAttribution extends StatelessWidget {
  final WaveController controller;
  final WaveTrack track;
  final bool compact;
  const SourceAttribution({
    super.key,
    required this.controller,
    required this.track,
    this.compact = false,
  });
  @override
  Widget build(BuildContext context) {
    final credit = object(track.playback['attribution']),
        url = credit['sourceUrl']?.toString() ?? '';
    final uri = Uri.tryParse(url);
    if (credit.isEmpty ||
        uri?.scheme != 'https' ||
        uri?.host.isEmpty != false) {
      return compact
          ? ScrollingLabel(
              track.artist,
              style: TextStyle(color: waveVisuals(context).muted, fontSize: 10),
            )
          : const SizedBox.shrink();
    }
    final artist = credit['artist']?.toString() ?? track.artist;
    final label =
        '$artist · ${credit['source'] == 'soundcloud' ? 'SoundCloud' : credit['source']}';
    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        key: const Key('source-attribution'),
        onTap: () => controller.openUrl(url),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: compact ? 2 : 9),
          child: compact
              ? Row(
                  children: [
                    Expanded(
                      child: ScrollingLabel(
                        artist == track.artist
                            ? artist
                            : '${track.artist} · $artist',
                        style: TextStyle(
                          color: waveVisuals(context).muted,
                          fontSize: 10,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.cloud_outlined,
                      size: 12,
                      color: waveVisuals(context).muted,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      credit['source'] == 'soundcloud'
                          ? 'SoundCloud'
                          : credit['source'].toString(),
                      style: TextStyle(
                        color: waveVisuals(context).muted,
                        fontSize: 8,
                      ),
                    ),
                  ],
                )
              : Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: waveVisuals(context).muted,
                    fontSize: 12,
                    decoration: TextDecoration.underline,
                    decorationColor: waveVisuals(context).muted,
                  ),
                ),
        ),
      ),
    );
  }
}

class MiniPlayer extends StatelessWidget {
  final WaveController controller;
  final VoidCallback onOpen;
  final VoidCallback? onDevices;
  final Key? artworkKey;
  final VoidCallback? onDragStart, onDragCancel;
  final ValueChanged<double>? onDragUpdate, onDragEnd;
  const MiniPlayer({
    super.key,
    required this.controller,
    required this.onOpen,
    this.onDevices,
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
    if (!compact) {
      return NativeDesktopTransport(
        controller: c,
        onOpen: onOpen,
        onDevices: onDevices,
        artworkKey: artworkKey,
        onDragStart: onDragStart,
        onDragUpdate: onDragUpdate,
        onDragEnd: onDragEnd,
        onDragCancel: onDragCancel,
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(
        waveRadius(context, compact ? 13 : 22),
      ),
      child: Material(
        color: v.player,
        child: StreamBuilder<Duration>(
          stream: c.audio.positionStream,
          builder: (context, snapshot) {
            final total =
                c.audio.duration?.inMilliseconds.toDouble() ??
                (track?.duration ?? 0) * 1000;
            final value = total > 0
                ? ((snapshot.data?.inMilliseconds ?? 0) / total).clamp(0.0, 1.0)
                : 0.0;
            return Stack(
              children: [
                if (compact)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Semantics(
                        label: polishText('progress', context),
                        value: '${(value * 100).round()}%',
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            key: const Key('mini-card-progress'),
                            widthFactor: value,
                            heightFactor: 1,
                            child: ColoredBox(
                              color: (c.trackLoading ? v.muted : v.accent)
                                  .withValues(
                                    alpha: c.trackLoading ? .08 : .16,
                                  ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                SizedBox(
                  height: track != null
                      ? 94
                      : compact || v.compact
                      ? 72
                      : 84,
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
                                            trackLoading: c.trackLoading,
                                            url: track.artwork,
                                            size: compact ? 44 : 52,
                                            radius: 8,
                                          ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              ScrollingLabel(
                                                track?.title ??
                                                    wt(
                                                      'native.899c8de911',
                                                      context: context,
                                                    ),
                                                style: TextStyle(
                                                  color: v.onPlayer,
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 13,
                                                ),
                                              ),
                                              const SizedBox(height: 3),
                                              ScrollingLabel(
                                                track?.artist ??
                                                    wt(
                                                      'native.b196b73079',
                                                      context: context,
                                                    ),
                                                style: TextStyle(
                                                  color: v.onPlayer.withValues(
                                                    alpha: .7,
                                                  ),
                                                  fontSize: 10,
                                                ),
                                              ),
                                              if (track != null &&
                                                  c.controllingRemote) ...[
                                                const SizedBox(height: 4),
                                                Builder(
                                                  builder: (anchor) =>
                                                      PlayingOutput(
                                                        key: const Key(
                                                          'mini-active-device',
                                                        ),
                                                        controller: c,
                                                        banner: true,
                                                        onTap: () =>
                                                            showConnectPicker(
                                                              anchor,
                                                              c,
                                                              onAllDevices:
                                                                  onDevices,
                                                              anchor:
                                                                  _anchorRect(
                                                                    anchor,
                                                                  ),
                                                            ),
                                                      ),
                                                ),
                                              ],
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
                                      ? wt(
                                          'native.4ddf34c036',
                                          context: context,
                                        )
                                      : wt(
                                          'native.5633e5c745',
                                          context: context,
                                        ),
                                  constraints: const BoxConstraints(
                                    minWidth: 44,
                                    minHeight: 44,
                                  ),
                                  onPressed: c.online
                                      ? () => _run(c, () => c.like(track))
                                      : null,
                                  icon: WaveToggleIcon(
                                    active: c.likedIds.contains(track.id),
                                    activeIcon: Icons.favorite_rounded,
                                    inactiveIcon: Icons.favorite_border_rounded,
                                    color: c.likedIds.contains(track.id)
                                        ? v.accent
                                        : v.onPlayer.withValues(alpha: .7),
                                    size: 21,
                                  ),
                                ),
                              if (!compact)
                                IconButton(
                                  tooltip: wt(
                                    'native.8e1abb9475',
                                    context: context,
                                  ),
                                  onPressed: c.canControl && !c.trackLoading
                                      ? () => _run(c, c.audio.skipToPrevious)
                                      : null,
                                  icon: WaveControlIcon(
                                    Icons.skip_previous_rounded,
                                    color: v.onPlayer,
                                  ),
                                ),
                              StreamBuilder<PlaybackState>(
                                stream: c.audio.playbackState,
                                builder: (context, state) {
                                  final busy = c.trackLoading;
                                  return IconButton.filled(
                                    tooltip: c.audio.playing
                                        ? wt(
                                            'native.03498e395a',
                                            context: context,
                                          )
                                        : wt(
                                            'native.c750dc7d94',
                                            context: context,
                                          ),
                                    style: IconButton.styleFrom(
                                      backgroundColor: v.onPlayer,
                                      foregroundColor: v.player,
                                      minimumSize: const Size(44, 44),
                                      maximumSize: const Size(44, 44),
                                    ),
                                    onPressed:
                                        c.canTogglePlayback &&
                                            track != null &&
                                            (!busy || c.audio.playing)
                                        ? () => _run(
                                            c,
                                            c.audio.playing
                                                ? c.audio.pause
                                                : c.audio.play,
                                          )
                                        : null,
                                    icon: WavePlaybackIcon(
                                      playing: c.audio.playing,
                                      loading: busy,
                                      size: 23,
                                    ),
                                  );
                                },
                              ),
                              if (!compact)
                                IconButton(
                                  tooltip: wt(
                                    'native.c97fa8b29b',
                                    context: context,
                                  ),
                                  onPressed: c.canControl && !c.trackLoading
                                      ? () => _run(c, c.audio.skipToNext)
                                      : null,
                                  icon: WaveControlIcon(
                                    Icons.skip_next_rounded,
                                    color: v.onPlayer,
                                    size: 23,
                                  ),
                                ),
                              if (!compact)
                                IconButton(
                                  key: const Key('mini-equalizer'),
                                  tooltip: wt('eq.title', context: context),
                                  isSelected: c.customization.equalizer.enabled,
                                  style: IconButton.styleFrom(
                                    backgroundColor:
                                        c.customization.equalizer.enabled
                                        ? v.accentSoft
                                        : Colors.transparent,
                                  ),
                                  onPressed: () =>
                                      showPlayerEqualizer(context, c),
                                  icon: WaveControlIcon(
                                    Icons.graphic_eq_rounded,
                                    color: c.customization.equalizer.enabled
                                        ? v.accent
                                        : v.onPlayer.withValues(alpha: .7),
                                    size: 19,
                                  ),
                                ),
                              if (!compact)
                                Builder(
                                  builder: (anchorContext) => IconButton(
                                    key: const Key('mini-connect'),
                                    tooltip: 'GlukWave Connect',
                                    onPressed: () => showConnectPicker(
                                      anchorContext,
                                      c,
                                      onAllDevices: onDevices,
                                      anchor: _anchorRect(anchorContext),
                                    ),
                                    icon: WaveControlIcon(
                                      Icons.devices_rounded,
                                      color: c.controllingRemote
                                          ? v.accent
                                          : v.onPlayer.withValues(alpha: .7),
                                      size: 19,
                                    ),
                                  ),
                                ),
                              if (!compact)
                                SizedBox(
                                  width: 130,
                                  child: Row(
                                    children: [
                                      WaveVolumeIcon(
                                        volume: c.audio.volume,
                                        color: v.onPlayer.withValues(
                                          alpha: .65,
                                        ),
                                        size: 19,
                                      ),
                                      Expanded(
                                        child: VolumeSlider(
                                          scope: c.controlScope,
                                          onPreview: c.previewVolume,
                                          onCancel: c.cancelVolumeEdit,
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
                                  tooltip: wt(
                                    'native.d66131f711',
                                    context: context,
                                  ),
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
                      if (!compact)
                        StreamBuilder<Duration>(
                          stream: c.audio.positionStream,
                          builder: (context, snapshot) {
                            final total = c.audio.duration?.inMilliseconds ?? 0;
                            return LinearProgressIndicator(
                              value: total > 0
                                  ? ((snapshot.data?.inMilliseconds ?? 0) /
                                            total)
                                        .clamp(0, 1)
                                  : 0,
                              minHeight: 2,
                              color: c.trackLoading ? v.muted : v.accent,
                              backgroundColor: v.onPlayer.withValues(
                                alpha: .12,
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
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

Future<void> showPlayerEqualizer(BuildContext context, WaveController c) {
  final box = context.findRenderObject() as RenderBox?,
      origin = box?.localToGlobal(Offset.zero) ?? Offset.zero,
      size = box?.size;
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: wt('native.398c7d4f7b', context: context),
    barrierColor: Colors.transparent,
    transitionDuration: waveVisuals(
      context,
    ).duration((220 / waveVisuals(context).speed).round()),
    pageBuilder: (dialog, _, _) => AnimatedBuilder(
      animation: c,
      builder: (dialog, _) {
        final inherited = Theme.of(dialog),
            liveVisuals = waveVisuals(dialog).copyWith(
              radius: c.customization.appearance.radius,
              speed: c.customization.appearance.speed,
              reducedMotion: c.customization.reducedMotion,
            );
        return Theme(
          data: inherited.copyWith(extensions: [liveVisuals]),
          child: Builder(
            builder: (dialog) => LayoutBuilder(
              builder: (dialog, constraints) {
                final width = (constraints.maxWidth - 16).clamp(200.0, 380.0),
                    height =
                        (constraints.maxHeight -
                                MediaQuery.paddingOf(dialog).vertical -
                                24)
                            .clamp(100.0, 460.0),
                    anchorY = size != null && size.height < 200
                        ? origin.dy
                        : constraints.maxHeight -
                              90 -
                              MediaQuery.paddingOf(dialog).bottom;
                final top = (anchorY - height - 12).clamp(
                      MediaQuery.paddingOf(dialog).top + 8,
                      constraints.maxHeight - height - 8,
                    ),
                    left =
                        (origin.dx +
                                (size?.width ?? constraints.maxWidth) -
                                width -
                                12)
                            .clamp(8.0, constraints.maxWidth - width - 8);
                return Stack(
                  children: [
                    Positioned(
                      left: left,
                      top: top,
                      width: width,
                      height: height,
                      child: Material(
                        key: const Key('player-eq-popover'),
                        elevation: 16,
                        color: waveVisuals(dialog).surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            waveRadius(dialog, 24),
                          ),
                          side: BorderSide(color: waveVisuals(dialog).line),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: SingleChildScrollView(
                          child: CompactEqualizerPanel(
                            controller: c,
                            onClose: () => Navigator.pop(dialog),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    ),
    transitionBuilder: (context, animation, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, .012),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    ),
  );
}

class PlayerPage extends StatefulWidget {
  final WaveController controller;
  final WaveTrack? initialTrack;
  final void Function(WaveTrack) onMore;
  final VoidCallback? onClose, onDevices, onDragStart, onDragCancel;
  final ValueChanged<double>? onDragUpdate, onDragEnd;
  final Key? artworkKey;
  final bool hideAlbum;
  const PlayerPage({
    super.key,
    required this.controller,
    this.initialTrack,
    required this.onMore,
    this.onClose,
    this.onDevices,
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
  String? _detailsScope;
  String detailsScope(WaveTrack? track) =>
      '${c.namespace}:${track?.id}:${c.online}:${c.localSavedPlayback}';
  final comment = TextEditingController();
  final _lyricsScroll = ScrollController();
  final _lyricKeys = <int, GlobalKey>{};
  int _lastLyric = -2;
  DateTime _manualLyricsUntil = DateTime(0);
  StreamSubscription<MediaItem?>? _media;
  @override
  void initState() {
    super.initState();
    current = widget.initialTrack ?? c.audio.viewCurrent;
    _detailsScope = detailsScope(current);
    unawaited(loadDetails());
    if (widget.initialTrack == null) {
      _media = c.audio.mediaItem.listen((_) => _syncCurrent());
      // viewCurrent also includes a track awaiting its audio descriptor;
      // mediaItem is deliberately published only after that descriptor arrives.
      c.addListener(_syncCurrent);
    }
  }

  void _syncCurrent() {
    if (!mounted) return;
    final track = c.audio.viewCurrent;
    final scope = detailsScope(track), changed = track?.id != current?.id;
    if (!changed && scope == _detailsScope) return;
    _detailsScope = scope;
    setState(() {
      current = track;
      if (changed) {
        lyrics = [];
        comments = [];
        _lyricKeys.clear();
        _lastLyric = -2;
      }
      if (track == null) {
        _load++;
        loading = false;
      }
    });
    unawaited(loadDetails());
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
      final lyricResult = await c.lyricsFor(current!);
      if (!mounted || revision != _load) return;
      setState(() {
        lyrics = objects(lyricResult['lines']);
        synchronized = lyricResult['synchronized'] == true;
      });
      if (c.online && c.settings['comments'] != false) {
        unawaited(loadComments(id, revision));
      }
    } catch (e) {
      if (mounted && revision == _load) setState(() => error = e.toString());
    } finally {
      if (mounted && revision == _load) setState(() => loading = false);
    }
  }

  Future<void> loadComments(String id, int revision) async {
    try {
      final data = await c.api.call('/api/tracks/$id/comments');
      if (mounted && revision == _load) {
        setState(() => comments = objects(data['comments']));
      }
    } catch (_) {
      /* Comments do not hold up saved or online lyrics. */
    }
  }

  @override
  void dispose() {
    c.removeListener(_syncCurrent);
    unawaited(_media?.cancel());
    comment.dispose();
    _lyricsScroll.dispose();
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
      if (tab == 3 && c.settings['comments'] == false ||
          tab == 1 && c.settings['lyrics'] == false) {
        tab = 0;
      }
      final track = current!;
      final wide = MediaQuery.sizeOf(context).width >= 851;
      final v = waveVisuals(context);
      return Stack(
        children: [
          if (v.blur && track.artwork.isNotEmpty)
            Positioned.fill(
              child: CoverAmbient(
                controller: c,
                artwork: track.artwork,
                playing: c.audio.viewCurrent?.id == track.id && c.audio.playing,
              ),
            ),
          if (c.customization.seasonalEffects.enabled)
            Positioned.fill(
              child: SeasonalAtmosphere(
                settings: c.customization.seasonalEffects,
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
                              focusedPlayerText('nowPlaying', context: context),
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
                    if (c.settings['lyrics'] != false)
                      IconButton(
                        key: const Key('player-lyrics-toggle'),
                        tooltip: wt('native.93970437e2', context: context),
                        isSelected: tab == 1,
                        style: IconButton.styleFrom(
                          minimumSize: const Size(34, 40),
                          padding: EdgeInsets.zero,
                          foregroundColor: tab == 1 ? v.accent : v.muted,
                          backgroundColor: tab == 1
                              ? v.accentSoft
                              : Colors.transparent,
                        ),
                        onPressed: () => setState(() => tab = tab == 1 ? 0 : 1),
                        icon: WaveViewIcon(
                          Icons.lyrics_outlined,
                          active: tab == 1,
                          size: 19,
                        ),
                      ),
                    IconButton(
                      key: const Key('player-queue-toggle'),
                      tooltip: wt('native.aec93b16ba', context: context),
                      isSelected: tab == 2,
                      style: IconButton.styleFrom(
                        minimumSize: const Size(34, 40),
                        padding: EdgeInsets.zero,
                        foregroundColor: tab == 2 ? v.accent : v.muted,
                        backgroundColor: tab == 2
                            ? v.accentSoft
                            : Colors.transparent,
                      ),
                      onPressed: () => setState(() => tab = tab == 2 ? 0 : 2),
                      icon: WaveViewIcon(
                        Icons.queue_music_rounded,
                        active: tab == 2,
                        size: 19,
                      ),
                    ),
                    PopupMenuButton<String>(
                      key: const Key('player-more'),
                      tooltip: focusedPlayerText('more', context: context),
                      icon: const WaveControlIcon(
                        Icons.more_horiz_rounded,
                        size: 20,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(v.corners(12)),
                      ),
                      itemBuilder: (_) => [
                        if (c.settings['comments'] != false)
                          PopupMenuItem(
                            value: 'comments',
                            child: Text(
                              wt('native.f1401a6c61', context: context),
                            ),
                          ),
                        PopupMenuItem(
                          value: 'cover',
                          child: Text(
                            focusedPlayerText('coverStyle', context: context),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'track',
                          child: Text(
                            wt('native.30ef88c9b5', context: context),
                          ),
                        ),
                      ],
                      onSelected: (value) {
                        if (value == 'comments') {
                          setState(() => tab = tab == 3 ? 0 : 3);
                        } else if (value == 'cover') {
                          showCoverStyle();
                        } else {
                          widget.onMore(track);
                        }
                      },
                    ),
                  ],
                ),
              ),
              if (loading)
                LinearProgressIndicator(
                  minHeight: 2,
                  color: waveVisuals(context).accent,
                ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, bounds) => playerBody(track, bounds, wide),
                ),
              ),
            ],
          ),
        ],
      );
    },
  );
  Future<void> showCoverStyle() => showWaveDialog<void>(
    context: context,
    builder: (dialog) => AnimatedBuilder(
      animation: c,
      builder: (context, _) => AlertDialog(
        title: Text(focusedPlayerText('coverStyle', context: context)),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: c.customization.appearance.cover3d,
                title: Text(wt('native.e7797473dd', context: context)),
                onChanged: (value) => _run(
                  c,
                  () => c.customize({
                    'appearance': {'cover3d': value},
                  }),
                ),
              ),
              for (final kind in ['vinyl', 'cd'])
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(kind == 'vinyl' ? 'VINYL' : 'CD'),
                  trailing: c.customization.appearance.coverKind == kind
                      ? Icon(
                          Icons.check_rounded,
                          color: waveVisuals(context).accent,
                        )
                      : null,
                  onTap: () {
                    Navigator.pop(dialog);
                    _run(
                      c,
                      () => c.customize({
                        'appearance': {'coverKind': kind, 'cover3d': true},
                      }),
                    );
                  },
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: Text(wt('native.398c7d4f7b', context: context)),
          ),
        ],
      ),
    ),
  );
  Widget playerBody(WaveTrack track, BoxConstraints bounds, bool wide) {
    if (tab == 0) {
      return Center(
        key: const Key('player-centered-view'),
        child: Padding(
          padding: EdgeInsets.fromLTRB(wide ? 32 : 20, 0, wide ? 32 : 20, 10),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 520),
            child: listening(track),
          ),
        ),
      );
    }
    Widget detail() => switch (tab) {
      1 => lyricPage(track),
      2 => queuePage(),
      _ => commentPage(track),
    };
    Widget scroll() => Listener(
      onPointerSignal: (_) =>
          _manualLyricsUntil = DateTime.now().add(const Duration(seconds: 5)),
      child: SingleChildScrollView(
        key: Key(
          tab == 1
              ? wide
                    ? 'desktop-lyrics-scroll'
                    : 'mobile-lyrics-scroll'
              : 'player-detail-scroll',
        ),
        controller: tab == 1 ? _lyricsScroll : null,
        padding: EdgeInsets.symmetric(horizontal: wide ? 32 : 24, vertical: 12),
        child: detail(),
      ),
    );
    if (wide) {
      return Padding(
        key: Key('player-detail-view-$tab'),
        padding: const EdgeInsets.fromLTRB(28, 10, 28, 16),
        child: Row(
          children: [
            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.only(right: 28),
                child: listening(track),
              ),
            ),
            Expanded(
              flex: 6,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(color: waveVisuals(context).line),
                  ),
                ),
                child: scroll(),
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      key: Key('player-detail-view-$tab'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 12),
          child: Row(
            children: [
              Artwork(
                controller: c,
                url: track.artwork,
                size: 46,
                radius: 12,
                trackLoading: c.trackLoading,
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ScrollingLabel(
                      track.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ScrollingLabel(
                      track.artist,
                      style: TextStyle(
                        fontSize: 11,
                        color: waveVisuals(context).muted,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                key: const Key('player-equalizer'),
                tooltip: wt('eq.title', context: context),
                isSelected: c.customization.equalizer.enabled,
                onPressed: () => showPlayerEqualizer(context, c),
                icon: WaveControlIcon(
                  Icons.graphic_eq_rounded,
                  color: c.customization.equalizer.enabled
                      ? waveVisuals(context).accent
                      : waveVisuals(context).muted,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
        Expanded(child: scroll()),
        Container(
          key: const Key('lyrics-persistent-controls'),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          decoration: BoxDecoration(
            color: waveVisuals(context).background.withValues(alpha: .9),
            border: Border(top: BorderSide(color: waveVisuals(context).line)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [progress(track), compactTransport()],
          ),
        ),
      ],
    );
  }

  Widget listening(WaveTrack track) => LayoutBuilder(
    builder: (context, bounds) {
      final v = waveVisuals(context),
          active = c.audio.viewCurrent?.id == track.id;
      final scale = MediaQuery.textScalerOf(context).scale(1);
      final dimensional = c.customization.appearance.cover3d && !c.energySaving;
      final landscape =
          MediaQuery.sizeOf(context).width > 600 && bounds.maxHeight < 470;
      // Give the rigid sleeve its complete turn envelope. The remaining space,
      // rather than the whole viewport, chooses the density of its controls.
      final size = ((bounds.maxWidth - 32) / (dimensional ? 1.6 : 1)).clamp(
        60.0,
        landscape ? 202.0 : 302.0,
      );
      final sceneHeight = dimensional
          ? referenceSleeveSceneHeight(size)
          : size + 36;
      final controlRoom = (bounds.maxHeight - sceneHeight - 20) / scale;
      final dense = controlRoom < 350,
          tiny = controlRoom < 290,
          short = controlRoom < 240;
      final preview =
          tab == 0 &&
          controlRoom >= 350 &&
          c.settings['lyrics'] == true &&
          c.settings['lyricsUnderCover'] != false &&
          lyrics.isNotEmpty;
      final previewHeight = preview ? 68.0 * scale : 0.0;
      final contents = <Widget>[
        SizedBox(
          height: sceneHeight,
          child: Center(
            child: PlayerGestureSurface(
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
          ),
        ),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ScrollingLabel(
                    track.title,
                    style: TextStyle(
                      fontSize: tiny
                          ? 19
                          : dense
                          ? 23
                          : 27,
                      height: 1.25,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.7,
                    ),
                  ),
                  SizedBox(height: short ? 3 : 5),
                  ScrollingLabel(
                    track.artist,
                    style: TextStyle(color: v.muted, fontSize: short ? 12 : 13),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: wt('native.36f30bdb01', context: context),
              onPressed: c.online ? () => _run(c, () => c.like(track)) : null,
              icon: WaveToggleIcon(
                active: c.likedIds.contains(track.id),
                activeIcon: Icons.favorite_rounded,
                inactiveIcon: Icons.favorite_border_rounded,
                color: c.likedIds.contains(track.id) ? v.accent : v.muted,
                size: 25,
              ),
            ),
          ],
        ),
        if (!short)
          Padding(
            padding: const EdgeInsets.only(top: 5, bottom: 2),
            child: Text(
              track.sourceName,
              key: const Key('source-attribution'),
              style: TextStyle(fontSize: 9, color: v.muted),
            ),
          ),
        if (preview)
          SizedBox(
            height: previewHeight,
            child: compactLyrics(track, tiny: tiny),
          ),
        if (active) ...[
          progress(track),
          SizedBox(height: short ? 3 : 7),
          Container(
            key: const Key('player-transport-capsule'),
            padding: EdgeInsets.symmetric(
              horizontal: 4,
              vertical: tiny ? 1 : 5,
            ),
            decoration: BoxDecoration(
              color: v.surface.withValues(alpha: .8),
              borderRadius: BorderRadius.circular(v.corners(26)),
            ),
            child: transport(compact: short),
          ),
          SizedBox(
            height: short
                ? 4
                : tiny
                ? 6
                : 12,
          ),
          Container(
            key: const Key('player-secondary-capsule'),
            decoration: BoxDecoration(
              color: v.surface.withValues(alpha: .55),
              borderRadius: BorderRadius.circular(v.corners(22)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                if (c.settings['lyrics'] != false)
                  IconButton(
                    tooltip: nativeText(context, 'lyrics'),
                    onPressed: () => setState(() => tab = 1),
                    icon: const WaveViewIcon(
                      Icons.lyrics_outlined,
                      active: false,
                      size: 21,
                    ),
                  ),
                IconButton(
                  key: const Key('player-equalizer'),
                  tooltip: wt('eq.title', context: context),
                  isSelected: c.customization.equalizer.enabled,
                  style: IconButton.styleFrom(
                    foregroundColor: c.customization.equalizer.enabled
                        ? v.accent
                        : v.muted,
                    backgroundColor: c.customization.equalizer.enabled
                        ? v.accentSoft
                        : Colors.transparent,
                  ),
                  onPressed: () => showPlayerEqualizer(context, c),
                  icon: const WaveControlIcon(
                    Icons.graphic_eq_rounded,
                    size: 21,
                  ),
                ),
                IconButton(
                  tooltip: wt('native.621777004a', context: context),
                  onPressed: showVolume,
                  icon: WaveVolumeIcon(
                    volume: c.audio.volume,
                    size: 20,
                    color: v.muted,
                  ),
                ),
                IconButton(
                  tooltip: nativeText(context, 'queue'),
                  onPressed: () => setState(() => tab = 2),
                  icon: const WaveViewIcon(
                    Icons.queue_music_rounded,
                    active: false,
                    size: 21,
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: nativeText(context, 'more'),
                  icon: const WaveControlIcon(
                    Icons.more_horiz_rounded,
                    size: 21,
                  ),
                  onSelected: (value) {
                    if (value == 'save') {
                      _run(c, () => c.downloadTrack(track));
                    } else {
                      widget.onMore(track);
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'save',
                      enabled: c.online && !c.cache.contains(track.id),
                      child: Text(nativeText(context, 'save')),
                    ),
                    PopupMenuItem(
                      value: 'more',
                      child: Text(nativeText(context, 'more')),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(
            height: short
                ? 2
                : tiny
                ? 3
                : 8,
          ),
          Row(
            children: [
              Expanded(
                child: Builder(
                  builder: (anchorContext) => PlayingOutput(
                    controller: c,
                    onTap: () => showConnectPicker(
                      anchorContext,
                      c,
                      onAllDevices: widget.onDevices,
                      anchor: _anchorRect(anchorContext),
                    ),
                  ),
                ),
              ),
              ListeningPresence(controller: c, compact: true),
            ],
          ),
        ] else ...[
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: track.playable
                ? () => _run(c, () => c.play(track))
                : null,
            icon: const WavePlayPauseIcon(playing: false, size: 22),
            label: Text(wt('native.b09bf87fd9', context: context)),
          ),
        ],
      ];
      return SingleChildScrollView(
        key: const Key('player-content-scroll'),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: bounds.maxHeight),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              contents.first,
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: contents.skip(1).toList(),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    },
  );

  Widget compactLyrics(WaveTrack track, {required bool tiny}) =>
      StreamBuilder<Duration>(
        stream: c.audio.positionStream,
        builder: (_, snapshot) {
          final active = synchronized && c.audio.viewCurrent?.id == track.id,
              index = active
                  ? activeLyric(
                      lyrics,
                      (snapshot.data?.inMilliseconds ?? 0) / 1000,
                    )
                  : 0,
              current = index.clamp(0, lyrics.length - 1);
          return Column(
            key: const Key('player-compact-lyrics'),
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final line in [
                current,
                if (current + 1 < lyrics.length) current + 1,
              ])
                Flexible(
                  child: InkWell(
                    onTap: active && c.canSeek
                        ? () => _run(
                            c,
                            () => c.transport('seek', {
                              'position': number(lyrics[line]['time']),
                            }),
                          )
                        : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Text(
                        lyrics[line]['text']?.toString() ?? '',
                        key: Key('mini-lyric-$line'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: line == current ? (tiny ? 15 : 17) : 13,
                          height: 1.3,
                          color: line == current
                              ? waveVisuals(context).ink
                              : waveVisuals(context).muted,
                          fontWeight: line == current
                              ? FontWeight.w800
                              : FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      );

  Widget compactTransport() => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      IconButton(
        tooltip: wt('native.3a2d254d6e', context: context),
        onPressed: c.canControl && !c.trackLoading
            ? () => _run(c, c.audio.skipToPrevious)
            : null,
        icon: const WaveControlIcon(Icons.skip_previous_rounded, size: 25),
      ),
      const SizedBox(width: 24),
      IconButton.filled(
        key: const Key('player-play'),
        tooltip: c.audio.playing
            ? wt('native.03498e395a', context: context)
            : wt('native.c750dc7d94', context: context),
        onPressed: c.canTogglePlayback && (!c.trackLoading || c.audio.playing)
            ? () => _run(c, c.audio.playing ? c.audio.pause : c.audio.play)
            : null,
        style: IconButton.styleFrom(
          minimumSize: const Size(52, 52),
          backgroundColor: waveVisuals(context).ink,
          foregroundColor: waveVisuals(context).background,
        ),
        icon: WavePlaybackIcon(
          playing: c.audio.playing,
          loading: c.trackLoading,
          size: 25,
        ),
      ),
      const SizedBox(width: 24),
      IconButton(
        tooltip: wt('native.e9c094d2a9', context: context),
        onPressed: c.canControl && !c.trackLoading
            ? () => _run(c, c.audio.skipToNext)
            : null,
        icon: const WaveControlIcon(Icons.skip_next_rounded, size: 25),
      ),
    ],
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
          DraftSlider(
            sliderKey: const Key('player-seek'),
            scope:
                '${c.audio.viewCurrent?.id}:${c.activeDeviceId}:${c.activeSurfaceId}',
            value: current,
            max: total > 0 ? total : 1,
            onChanged: c.canSeek && total > 0
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
  Widget transport({bool compact = false}) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
    children: [
      IconButton(
        tooltip: wt('native.d8a9b54429', context: context),
        onPressed: !c.canControl
            ? null
            : () => _run(
                c,
                () => c.audio.setShuffleMode(
                  c.audio.shuffle
                      ? AudioServiceShuffleMode.none
                      : AudioServiceShuffleMode.all,
                ),
              ),
        icon: WaveStateIcon(
          state: c.audio.shuffle,
          icon: Icons.shuffle_rounded,
          color: c.audio.shuffle
              ? waveVisuals(context).accent
              : waveVisuals(context).muted,
          size: 23,
        ),
      ),
      IconButton(
        tooltip: wt('native.3a2d254d6e', context: context),
        onPressed: c.canControl && !c.trackLoading
            ? () => _run(c, () => c.audio.skipToPrevious())
            : null,
        icon: WaveControlIcon(
          Icons.skip_previous_rounded,
          size: compact ? 27 : 33,
        ),
      ),
      IconButton.filled(
        key: const Key('player-play'),
        tooltip: c.audio.playing
            ? wt('native.03498e395a', context: context)
            : wt('native.c750dc7d94', context: context),
        onPressed: c.canTogglePlayback && (!c.trackLoading || c.audio.playing)
            ? () => _run(
                c,
                () => c.audio.playing ? c.audio.pause() : c.audio.play(),
              )
            : null,
        style: IconButton.styleFrom(
          minimumSize: compact ? const Size(56, 56) : const Size(66, 66),
          backgroundColor: waveVisuals(context).ink,
          foregroundColor: waveVisuals(context).background,
        ),
        icon: WavePlaybackIcon(
          playing: c.audio.playing,
          loading: c.trackLoading,
          size: compact ? 28 : 32,
        ),
      ),
      IconButton(
        tooltip: wt('native.e9c094d2a9', context: context),
        onPressed: c.canControl && !c.trackLoading
            ? () => _run(c, () => c.audio.skipToNext())
            : null,
        icon: WaveControlIcon(Icons.skip_next_rounded, size: compact ? 27 : 33),
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
        onPressed: !c.canControl
            ? null
            : () => _run(
                c,
                () => c.audio.setRepeatMode(switch (c.audio.repeat) {
                  AudioServiceRepeatMode.none => AudioServiceRepeatMode.all,
                  AudioServiceRepeatMode.all => AudioServiceRepeatMode.one,
                  _ => AudioServiceRepeatMode.none,
                }),
              ),
        icon: WaveStateIcon(
          state: c.audio.repeat,
          icon: c.audio.repeat == AudioServiceRepeatMode.one
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
          child: VolumeSlider(
            scope: c.controlScope,
            onPreview: c.previewVolume,
            onCancel: c.cancelVolumeEdit,
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
            if (active != _lastLyric && tab == 1) {
              _lastLyric = active;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                final node = _lyricKeys[active]?.currentContext;
                if (mounted &&
                    node != null &&
                    DateTime.now().isAfter(_manualLyricsUntil)) {
                  Scrollable.ensureVisible(
                    node,
                    alignment: .5,
                    duration: waveVisuals(
                      context,
                    ).duration((350 / waveVisuals(context).speed).round()),
                    curve: Curves.easeOutCubic,
                  );
                }
              });
            }
            return Padding(
              padding: EdgeInsets.symmetric(
                vertical: MediaQuery.sizeOf(context).height * .14,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < lyrics.length; i++)
                    InkWell(
                      key: _lyricKeys.putIfAbsent(i, () => GlobalKey()),
                      onTap:
                          synchronized &&
                              c.canSeek &&
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
                            fontSize: MediaQuery.sizeOf(context).width >= 851
                                ? 32
                                : 26,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -.7,
                            height: 1.5,
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
    final track = current!, account = c.user?.id, server = c.api.server;
    final draft = lyrics
        .map(
          (line) => synchronized && line['time'] != null
              ? '[${lrcClock(number(line['time']))}]${line['text']}'
              : line['text'],
        )
        .join('\n');
    await showWaveDialog<void>(
      context: context,
      builder: (_) => LyricsEditor(
        controller: c,
        track: track,
        initialText: draft,
        isCurrent: () =>
            mounted &&
            current?.id == track.id &&
            c.user?.id == account &&
            c.api.server == server,
        onSaved: () async {
          if (mounted && current?.id == track.id && c.user?.id == account) {
            await loadDetails();
          }
        },
      ),
    );
  }

  Widget queuePage({bool compact = false}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        wt('native.5a187c8ad3', context: context),
        style: TextStyle(
          fontSize: compact ? 17 : 30,
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
      QueuePanel(controller: c, onMore: widget.onMore),
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
                            if (c.canSeek &&
                                c.audio.viewCurrent?.id == track.id) {
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
                          onPressed:
                              c.canSeek && c.audio.viewCurrent?.id == track.id
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

Rect? _anchorRect(BuildContext context) {
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}
