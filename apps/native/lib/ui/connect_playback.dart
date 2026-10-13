import 'package:flutter/material.dart';
import '../core/controller.dart';
import '../core/models.dart';
import '../l10n/wave_localizations.dart';
import 'widgets.dart';
import 'motion_icons.dart';
import 'device_labels.dart';
import 'volume_slider.dart';

/// The same confirmed output and command semantics in both Connect surfaces.
class ConnectPlayback extends StatelessWidget {
  final WaveController controller;
  final bool compact;
  const ConnectPlayback({
    super.key,
    required this.controller,
    this.compact = false,
  });
  Future<void> run(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      controller.tell(error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = controller, v = waveVisuals(context), track = c.audio.viewCurrent;
    if (track == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          wt('connect.noOutput', context: context),
          style: TextStyle(color: v.muted),
        ),
      );
    }
    return Container(
      key: const Key('connect-active-player'),
      padding: EdgeInsets.all(compact ? 14 : 19),
      decoration: BoxDecoration(
        color: v.accentSoft.withValues(alpha: .35),
        border: Border.all(color: v.accent.withValues(alpha: .24)),
        borderRadius: BorderRadius.circular(v.corners(18)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Artwork(
                controller: c,
                url: track.artwork,
                size: compact ? 46 : 62,
                radius: 11,
                trackLoading: c.trackLoading,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: v.muted),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      c.outputLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: v.accent),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              ListeningWave(playing: c.audio.playing, size: 18),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                key: const Key('connect-previous'),
                onPressed: c.canControl && !c.trackLoading
                    ? () => run(() => c.transport('previous'))
                    : null,
                tooltip: wt('native.3a2d254d6e', context: context),
                icon: const WaveControlIcon(
                  Icons.skip_previous_rounded,
                  size: 25,
                ),
              ),
              const SizedBox(width: 7),
              IconButton.filled(
                key: const Key('connect-play'),
                style: IconButton.styleFrom(
                  backgroundColor: v.ink,
                  foregroundColor: v.background,
                  minimumSize: const Size(42, 42),
                ),
                onPressed:
                    c.canTogglePlayback && (!c.trackLoading || c.audio.playing)
                    ? () => run(
                        () => c.transport(c.audio.playing ? 'pause' : 'play'),
                      )
                    : null,
                tooltip: wt(
                  c.audio.playing ? 'native.03498e395a' : 'native.c750dc7d94',
                  context: context,
                ),
                icon: WavePlaybackIcon(
                  playing: c.audio.playing,
                  loading: c.trackLoading,
                  size: 23,
                  color: v.background,
                ),
              ),
              const SizedBox(width: 7),
              IconButton(
                key: const Key('connect-next'),
                onPressed: c.canControl && !c.trackLoading
                    ? () => run(() => c.transport('next'))
                    : null,
                tooltip: wt('native.e9c094d2a9', context: context),
                icon: const WaveControlIcon(Icons.skip_next_rounded, size: 25),
              ),
            ],
          ),
          StreamBuilder<Duration>(
            stream: c.audio.positionStream,
            initialData: c.audio.position,
            builder: (context, snapshot) {
              final total =
                      c.audio.duration?.inMilliseconds.toDouble() ??
                      track.duration * 1000,
                  current = (snapshot.data?.inMilliseconds ?? 0)
                      .toDouble()
                      .clamp(0, total > 0 ? total : 1)
                      .toDouble();
              return Row(
                children: [
                  Text(
                    clock(current / 1000),
                    style: TextStyle(fontSize: 10, color: v.muted),
                  ),
                  Expanded(
                    child: DraftSlider(
                      sliderKey: const Key('connect-seek'),
                      scope: '${c.controlScope}:${track.id}',
                      value: current,
                      max: total > 0 ? total : 1,
                      onChanged: c.canSeek && total > 0
                          ? (value) => run(
                              () => c.transport('seek', {
                                'position': value / 1000,
                              }),
                            )
                          : null,
                    ),
                  ),
                  Text(
                    clock(total / 1000),
                    style: TextStyle(fontSize: 10, color: v.muted),
                  ),
                ],
              );
            },
          ),
          Row(
            children: [
              WaveVolumeIcon(volume: c.audio.volume, size: 16, color: v.muted),
              Expanded(
                child: VolumeSlider(
                  value: c.audio.volume,
                  scope: c.controlScope,
                  onPreview: c.previewVolume,
                  onCancel: c.cancelVolumeEdit,
                  onChanged: (value) =>
                      run(() => c.transport('volume', {'volume': value})),
                ),
              ),
              Text(
                '${(c.audio.volume * 100).round()}%',
                style: TextStyle(fontSize: 10, color: v.muted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
