import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import '../core/controller.dart';
import '../core/models.dart';
import '../l10n/wave_localizations.dart';
import 'connect_picker.dart';
import 'motion_icons.dart';
import 'player.dart' show showPlayerEqualizer;
import 'player_gestures.dart';
import 'scrolling_label.dart';
import 'volume_slider.dart';
import 'widgets.dart';
import 'listening_presence.dart';
import 'mini_lyrics.dart';

class NativeDesktopTransport extends StatefulWidget {
  final WaveController controller;
  final VoidCallback onOpen;
  final VoidCallback? onDevices;
  final Key? artworkKey;
  final VoidCallback? onDragStart, onDragCancel;
  final ValueChanged<double>? onDragUpdate, onDragEnd;
  const NativeDesktopTransport({
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
  State<NativeDesktopTransport> createState() => _NativeDesktopTransportState();
}

class _NativeDesktopTransportState extends State<NativeDesktopTransport> {
  WaveController get controller => widget.controller;
  VoidCallback get onOpen => widget.onOpen;
  VoidCallback? get onDevices => widget.onDevices;
  Key? get artworkKey => widget.artworkKey;
  VoidCallback? get onDragStart => widget.onDragStart;
  VoidCallback? get onDragCancel => widget.onDragCancel;
  ValueChanged<double>? get onDragUpdate => widget.onDragUpdate;
  ValueChanged<double>? get onDragEnd => widget.onDragEnd;
  bool lyricsAvailable = false;
  Future<void> perform(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      controller.tell(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = controller, v = waveVisuals(context), track = c.audio.viewCurrent;
    return Material(
      color: v.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(v.corners(21)),
        side: BorderSide(color: v.line),
      ),
      child: SizedBox(
        height:
            lyricsAvailable &&
                c.settings['lyrics'] != false &&
                c.settings['lyricsUnderCover'] != false
            ? 160
            : 94,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
          child: LayoutBuilder(
            builder: (context, bounds) {
              final narrow = bounds.maxWidth < 1000;
              return Row(
                children: [
                  Expanded(
                    flex: 3,
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
                                size: 52,
                                radius: 11,
                                trackLoading: c.trackLoading,
                              ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ScrollingLabel(
                                    track?.title ?? 'GlukWave',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  ScrollingLabel(
                                    track?.artist ?? '',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: v.muted,
                                    ),
                                  ),
                                  if (track != null && c.controllingRemote) ...[
                                    const SizedBox(height: 4),
                                    Builder(
                                      builder: (anchor) => PlayingOutput(
                                        key: const Key('mini-active-device'),
                                        controller: c,
                                        banner: true,
                                        onTap: () {
                                          final box =
                                              anchor.findRenderObject()
                                                  as RenderBox?;
                                          showConnectPicker(
                                            anchor,
                                            c,
                                            onAllDevices: onDevices,
                                            anchor: box == null
                                                ? null
                                                : box.localToGlobal(
                                                        Offset.zero,
                                                      ) &
                                                      box.size,
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (!narrow && track != null)
                              IconButton(
                                key: const Key('mini-like'),
                                tooltip: wt(
                                  'native.36f30bdb01',
                                  context: context,
                                ),
                                onPressed: c.online
                                    ? () => perform(() => c.like(track))
                                    : null,
                                icon: WaveToggleIcon(
                                  active: c.likedIds.contains(track.id),
                                  activeIcon: Icons.favorite_rounded,
                                  inactiveIcon: Icons.favorite_border_rounded,
                                  size: 20,
                                  color: c.likedIds.contains(track.id)
                                      ? v.accent
                                      : v.muted,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 5,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (track != null)
                          MiniLyrics(
                            controller: c,
                            track: track,
                            dense: true,
                            onAvailability: (available) {
                              if (mounted && available != lyricsAvailable) {
                                setState(() => lyricsAvailable = available);
                              }
                            },
                          ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              tooltip: wt(
                                'native.d8a9b54429',
                                context: context,
                              ),
                              onPressed: c.canControl
                                  ? () => perform(
                                      () => c.audio.setShuffleMode(
                                        c.audio.shuffle
                                            ? AudioServiceShuffleMode.none
                                            : AudioServiceShuffleMode.all,
                                      ),
                                    )
                                  : null,
                              icon: WaveStateIcon(
                                state: c.audio.shuffle,
                                icon: Icons.shuffle_rounded,
                                color: c.audio.shuffle ? v.accent : v.muted,
                                size: 18,
                              ),
                            ),
                            IconButton(
                              tooltip: wt(
                                'native.3a2d254d6e',
                                context: context,
                              ),
                              onPressed: c.canControl && !c.trackLoading
                                  ? () => perform(c.audio.skipToPrevious)
                                  : null,
                              icon: const WaveControlIcon(
                                Icons.skip_previous_rounded,
                                size: 21,
                              ),
                            ),
                            StreamBuilder<PlaybackState>(
                              stream: c.audio.playbackState,
                              builder: (_, snapshot) => IconButton.filled(
                                key: const Key('mini-play'),
                                tooltip: c.audio.playing
                                    ? wt('native.03498e395a', context: context)
                                    : wt('native.c750dc7d94', context: context),
                                style: IconButton.styleFrom(
                                  minimumSize: const Size(42, 42),
                                  maximumSize: const Size(42, 42),
                                  foregroundColor: v.background,
                                  backgroundColor: v.ink,
                                  padding: EdgeInsets.zero,
                                ),
                                onPressed:
                                    c.canTogglePlayback &&
                                        (!c.trackLoading || c.audio.playing)
                                    ? () => perform(
                                        c.audio.playing
                                            ? c.audio.pause
                                            : c.audio.play,
                                      )
                                    : null,
                                icon: WavePlaybackIcon(
                                  playing: c.audio.playing,
                                  loading: c.trackLoading,
                                  size: 23,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: wt(
                                'native.e9c094d2a9',
                                context: context,
                              ),
                              onPressed: c.canControl && !c.trackLoading
                                  ? () => perform(c.audio.skipToNext)
                                  : null,
                              icon: const WaveControlIcon(
                                Icons.skip_next_rounded,
                                size: 21,
                              ),
                            ),
                            IconButton(
                              tooltip: wt(
                                'native.9089f12327',
                                values: {'p0': c.audio.repeat.name},
                                context: context,
                              ),
                              onPressed: c.canControl
                                  ? () => perform(
                                      () => c.audio.setRepeatMode(
                                        switch (c.audio.repeat) {
                                          AudioServiceRepeatMode.none =>
                                            AudioServiceRepeatMode.all,
                                          AudioServiceRepeatMode.all =>
                                            AudioServiceRepeatMode.one,
                                          _ => AudioServiceRepeatMode.none,
                                        },
                                      ),
                                    )
                                  : null,
                              icon: WaveStateIcon(
                                state: c.audio.repeat,
                                icon:
                                    c.audio.repeat == AudioServiceRepeatMode.one
                                    ? Icons.repeat_one_rounded
                                    : Icons.repeat_rounded,
                                color:
                                    c.audio.repeat ==
                                        AudioServiceRepeatMode.none
                                    ? v.muted
                                    : v.accent,
                                size: 18,
                              ),
                            ),
                          ],
                        ),
                        StreamBuilder<Duration>(
                          stream: c.audio.positionStream,
                          builder: (_, snapshot) {
                            final total =
                                c.audio.duration?.inMilliseconds.toDouble() ??
                                (track?.duration ?? 0) * 1000;
                            final value = (snapshot.data?.inMilliseconds ?? 0)
                                .toDouble()
                                .clamp(0, total > 0 ? total : 1);
                            return SizedBox(
                              height: 27,
                              child: Row(
                                children: [
                                  Text(
                                    clock(value / 1000),
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: v.muted,
                                    ),
                                  ),
                                  Expanded(
                                    child: DraftSlider(
                                      sliderKey: const Key('mini-seek'),
                                      scope: '${track?.id}:${c.controlScope}',
                                      value: value.toDouble(),
                                      max: total > 0 ? total : 1,
                                      onChanged: c.canSeek && total > 0
                                          ? (value) => perform(
                                              () => c.audio.seek(
                                                Duration(
                                                  milliseconds: value.round(),
                                                ),
                                              ),
                                            )
                                          : null,
                                    ),
                                  ),
                                  Text(
                                    clock(total / 1000),
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: v.muted,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        IconButton(
                          key: const Key('mini-equalizer'),
                          tooltip: wt('eq.title', context: context),
                          isSelected: c.customization.equalizer.enabled,
                          style: IconButton.styleFrom(
                            minimumSize: const Size(38, 42),
                            padding: EdgeInsets.zero,
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
                            size: 18,
                          ),
                        ),
                        Builder(
                          builder: (anchor) => IconButton(
                            tooltip: wt('native.7ab03d602e', context: context),
                            constraints: const BoxConstraints(
                              minWidth: 38,
                              minHeight: 42,
                            ),
                            padding: EdgeInsets.zero,
                            onPressed: () {
                              final box =
                                  anchor.findRenderObject() as RenderBox?;
                              showConnectPicker(
                                anchor,
                                c,
                                onAllDevices: onDevices,
                                anchor: box == null
                                    ? null
                                    : box.localToGlobal(Offset.zero) & box.size,
                              );
                            },
                            icon: WaveControlIcon(
                              Icons.devices_rounded,
                              size: 18,
                              color: c.controllingRemote ? v.accent : v.muted,
                            ),
                          ),
                        ),
                        if (!narrow) const SizedBox(width: 8),
                        if (!narrow)
                          WaveVolumeIcon(
                            volume: c.audio.volume,
                            size: 18,
                            color: v.muted,
                          ),
                        if (!narrow)
                          Flexible(
                            child: SizedBox(
                              width: 90,
                              child: VolumeSlider(
                                scope: c.controlScope,
                                value: c.audio.volume.clamp(0, 1),
                                onPreview: c.previewVolume,
                                onCancel: c.cancelVolumeEdit,
                                onChanged: (value) => perform(
                                  () =>
                                      c.transport('volume', {'volume': value}),
                                ),
                              ),
                            ),
                          ),
                        IconButton(
                          tooltip: wt('native.d66131f711', context: context),
                          constraints: const BoxConstraints(
                            minWidth: 38,
                            minHeight: 42,
                          ),
                          padding: EdgeInsets.zero,
                          onPressed: onOpen,
                          icon: Icon(
                            Icons.open_in_full_rounded,
                            size: 17,
                            color: v.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
