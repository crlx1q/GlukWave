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

/// The desktop transport is a compact floating listening capsule. Detailed
/// seeking, volume, EQ and queue remain in the expanded player.
class NativeDesktopTransport extends StatelessWidget {
  final WaveController controller;
  final VoidCallback onOpen;
  final VoidCallback? onDevices;
  final Key? artworkKey;
  final VoidCallback? onDragStart, onDragCancel;
  final ValueChanged<double>? onDragUpdate, onDragEnd;
  const NativeDesktopTransport({super.key, required this.controller, required this.onOpen, this.onDevices, this.artworkKey, this.onDragStart, this.onDragUpdate, this.onDragEnd, this.onDragCancel});
  Future<void> perform(Future<void> Function() action) async {
    try { await action(); } catch (error) { controller.tell(error.toString()); }
  }
  @override
  Widget build(BuildContext context) {
    final c = controller, v = waveVisuals(context), track = c.audio.viewCurrent;
    return Align(alignment: Alignment.bottomCenter, widthFactor: 1, heightFactor: 1, child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 740),
      child: Material(color: v.surface, elevation: 12, shadowColor: Colors.black.withValues(alpha: .18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: v.line)),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(height: 68, child: Column(children: [
          Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), child: Row(children: [
            Expanded(child: PlayerGestureSurface(key: const Key('mini-gesture'), controller: c, opensPlayer: true,
              onVerticalStart: onDragStart, onVerticalUpdate: onDragUpdate, onVerticalEnd: onDragEnd, onVerticalCancel: onDragCancel,
              child: InkWell(onTap: onOpen, child: Row(children: [
                if (track != null) Artwork(key: artworkKey, controller: c, url: track.artwork, size: 44, radius: 8, trackLoading: c.trackLoading),
                const SizedBox(width: 12),
                Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  ScrollingLabel(track?.title ?? 'GlukWave', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  if (!c.controllingRemote) ScrollingLabel(track?.artist ?? '', style: TextStyle(fontSize: 10, color: v.muted)),
                  if (track != null && c.controllingRemote) Builder(builder: (anchor) => PlayingOutput(key: const Key('mini-active-device'), controller: c, banner: true, onTap: () => showConnectPicker(anchor, c, onAllDevices: onDevices))),
                ])),
              ])),
            )),
            if (track != null) IconButton(key: const Key('mini-like'), tooltip: wt('native.36f30bdb01', context: context),
              onPressed: c.online ? () => perform(() => c.like(track)) : null,
              icon: WaveToggleIcon(active: c.likedIds.contains(track.id), activeIcon: Icons.favorite_rounded, inactiveIcon: Icons.favorite_border_rounded, size: 20, color: c.likedIds.contains(track.id) ? v.accent : v.muted)),
            IconButton(tooltip: wt('native.3a2d254d6e', context: context), onPressed: c.canControl && !c.trackLoading ? () => perform(c.audio.skipToPrevious) : null, icon: const WaveControlIcon(Icons.skip_previous_rounded, size: 22)),
            StreamBuilder<PlaybackState>(stream: c.audio.playbackState, builder: (_, snapshot) => IconButton.filled(
              key: const Key('mini-play'), tooltip: wt(c.audio.playing ? 'native.03498e395a' : 'native.c750dc7d94', context: context),
              style: IconButton.styleFrom(minimumSize: const Size(44,44), maximumSize: const Size(44,44), foregroundColor: v.background, backgroundColor: v.ink, padding: EdgeInsets.zero),
              onPressed: c.canTogglePlayback && (!c.trackLoading || c.audio.playing) ? () => perform(c.audio.playing ? c.audio.pause : c.audio.play) : null,
              icon: WavePlaybackIcon(playing: c.audio.playing, loading: c.trackLoading, size: 23),
            )),
            IconButton(tooltip: wt('native.e9c094d2a9', context: context), onPressed: c.canControl && !c.trackLoading ? () => perform(c.audio.skipToNext) : null, icon: const WaveControlIcon(Icons.skip_next_rounded, size: 22)),
            IconButton(tooltip: wt('native.d66131f711', context: context), onPressed: onOpen, icon: Icon(Icons.open_in_full_rounded, size: 17, color: v.muted)),
          ]))),
          PlaybackProgress(controller: c, builder: (_, position, duration) => LinearProgressIndicator(minHeight: 2, value: duration > 0 ? (position / duration).clamp(0,1) : 0, color: c.trackLoading ? v.muted : v.accent, backgroundColor: v.line)),
        ])),
      ),
    ));
  }
}
