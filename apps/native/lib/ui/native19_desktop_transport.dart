import '../core/models.dart';
import 'playback_progress.dart';
import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import '../core/controller.dart';
import '../l10n/wave_localizations.dart';
import 'connect_picker.dart';
import 'motion_icons.dart';
import 'player_gestures.dart';
import 'scrolling_label.dart';
import 'widgets.dart';
import 'listening_presence.dart';
import 'volume_slider.dart';

/// A broad desktop dock; the separate tray / always-on-top windows keep their
/// compact geometry. There is one transport in the main application.
class NativeDesktopTransport extends StatelessWidget {
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
  Future<void> perform(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      controller.tell(error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = controller, v = waveVisuals(context), track = c.audio.viewCurrent;
    return Material(
      key: const Key('desktop-main-dock'),
      color: v.surface,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: .12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: v.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: 104,
        child: LayoutBuilder(
          builder: (_, constraints) {
            final wide = constraints.maxWidth >= 940;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    flex: 10,
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
                                      size: 60,
                                      radius: 10,
                                      trackLoading: c.trackLoading,
                                    ),
                                  const SizedBox(width: 13),
                                  Expanded(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        ScrollingLabel(
                                          track?.title ?? 'GlukWave',
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        if (!c.controllingRemote)
                                          ScrollingLabel(
                                            track?.artist ?? '',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: v.muted,
                                            ),
                                          ),
                                        if (track != null &&
                                            c.controllingRemote)
                                          PlayingOutput(
                                            key: const Key(
                                              'mini-active-device',
                                            ),
                                            controller: c,
                                            banner: true,
                                            onTap: () => showConnectPicker(
                                              context,
                                              c,
                                              onAllDevices: onDevices,
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
                            tooltip: wt('native.36f30bdb01', context: context),
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
                  const SizedBox(width: 16),
                  Expanded(
                    flex: wide ? 14 : 13,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (wide)
                              IconButton(
                                tooltip: wt(
                                  'native.d8a9b54429',
                                  context: context,
                                ),
                                onPressed: c.canControl
                                    ? () => perform(
                                        () => c.audio.setShuffleMode(
                                          !c.audio.shuffle
                                              ? AudioServiceShuffleMode.all
                                              : AudioServiceShuffleMode.none,
                                        ),
                                      )
                                    : null,
                                icon: WaveControlIcon(
                                  Icons.shuffle_rounded,
                                  size: 18,
                                  color: !c.audio.shuffle ? v.muted : v.accent,
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
                                size: 23,
                              ),
                            ),
                            StreamBuilder<PlaybackState>(
                              stream: c.audio.playbackState,
                              builder: (_, snapshot) => IconButton.filled(
                                key: const Key('mini-play'),
                                tooltip: wt(
                                  c.audio.playing
                                      ? 'native.03498e395a'
                                      : 'native.c750dc7d94',
                                  context: context,
                                ),
                                style: IconButton.styleFrom(
                                  minimumSize: const Size(44, 44),
                                  maximumSize: const Size(44, 44),
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
                                  size: 24,
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
                                size: 23,
                              ),
                            ),
                            if (wide)
                              IconButton(
                                tooltip: wt(
                                  'native.9089f12327',
                                  values: {
                                    'p0': wt(
                                      c.audio.repeat ==
                                              AudioServiceRepeatMode.none
                                          ? 'native.0b48cc8756'
                                          : c.audio.repeat ==
                                                AudioServiceRepeatMode.one
                                          ? 'native.81d73996e1'
                                          : 'native.7d449210b8',
                                      context: context,
                                    ),
                                  },
                                  context: context,
                                ),
                                onPressed: c.canControl
                                    ? () => perform(
                                        () => c.audio.setRepeatMode(
                                          c.audio.repeat ==
                                                  AudioServiceRepeatMode.none
                                              ? AudioServiceRepeatMode.all
                                              : c.audio.repeat ==
                                                    AudioServiceRepeatMode.all
                                              ? AudioServiceRepeatMode.one
                                              : AudioServiceRepeatMode.none,
                                        ),
                                      )
                                    : null,
                                icon: WaveControlIcon(
                                  c.audio.repeat == AudioServiceRepeatMode.one
                                      ? Icons.repeat_one_rounded
                                      : Icons.repeat_rounded,
                                  size: 18,
                                  color:
                                      c.audio.repeat ==
                                          AudioServiceRepeatMode.none
                                      ? v.muted
                                      : v.accent,
                                ),
                              ),
                          ],
                        ),
                        PlaybackProgress(
                          controller: c,
                          builder: (_, position, duration) => SizedBox(
                            height: 23,
                            child: Row(
                              children: [
                                Text(
                                  clock(position / 1000),
                                  style: TextStyle(fontSize: 9, color: v.muted),
                                ),
                                Expanded(
                                  child: DraftSlider(
                                    sliderKey: const Key('desktop-dock-seek'),
                                    scope: c.controlScope,
                                    value: position.clamp(
                                      0,
                                      duration > 0 ? duration : 1,
                                    ),
                                    max: duration > 0 ? duration : 1,
                                    onChanged: c.canSeek
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
                                  clock(duration / 1000),
                                  style: TextStyle(fontSize: 9, color: v.muted),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: wide ? 170 : 96,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            IconButton(
                              key: const Key('mini-connect'),
                              tooltip: 'GlukWave Connect',
                              onPressed: () => showConnectPicker(
                                context,
                                c,
                                onAllDevices: onDevices,
                              ),
                              icon: Icon(
                                Icons.devices_rounded,
                                size: 19,
                                color: v.muted,
                              ),
                            ),
                            IconButton(
                              tooltip: wt(
                                'native.d66131f711',
                                context: context,
                              ),
                              onPressed: onOpen,
                              icon: Icon(
                                Icons.open_in_full_rounded,
                                size: 18,
                                color: v.muted,
                              ),
                            ),
                          ],
                        ),
                        if (wide)
                          SizedBox(
                            height: 26,
                            child: VolumeSlider(
                              hoverHint: true,
                              scope: c.controlScope,
                              value: c.audio.volume,
                              onPreview: c.previewVolume,
                              onCancel: c.cancelVolumeEdit,
                              onChanged: (value) => perform(
                                () => c.transport('volume', {'volume': value}),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
