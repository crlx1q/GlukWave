import 'player.dart' show SourceAttribution;
import 'scrolling_label.dart';
import 'motion_icons.dart';
import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../core/controller.dart';
import '../l10n/wave_localizations.dart';
import 'widgets.dart';
import 'volume_slider.dart';

/// Same session and audio handler as the full application. The desktop shell
/// switches the native window's bounds and frame; no second player is created.
class DesktopCompactPlayer extends StatefulWidget {
  final WaveController controller;
  final bool quick;
  const DesktopCompactPlayer({
    super.key,
    required this.controller,
    this.quick = false,
  });
  @override
  State<DesktopCompactPlayer> createState() => _DesktopCompactPlayerState();
}

class _DesktopCompactPlayerState extends State<DesktopCompactPlayer> {
  WaveController get c => widget.controller;
  DateTime? _lastWheel;
  double _swipe = 0;
  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      c.tell(error.toString());
    }
  }

  void _wheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent ||
        !c.canControl ||
        c.audio.viewCurrent == null) {
      return;
    }
    final now = DateTime.now();
    if (_lastWheel != null &&
        now.difference(_lastWheel!).inMilliseconds < 280) {
      return;
    }
    _lastWheel = now;
    final delta = event.scrollDelta.dx.abs() > event.scrollDelta.dy.abs()
        ? event.scrollDelta.dx
        : event.scrollDelta.dy;
    if (delta == 0) return;
    unawaited(_run(delta > 0 ? c.audio.skipToNext : c.audio.skipToPrevious));
  }

  Widget _control(
    IconData icon,
    String label,
    Future<void> Function() action, {
    Key? key,
  }) => IconButton(
    key: key,
    tooltip: label,
    onPressed: c.canControl && c.audio.viewCurrent != null
        ? () => _run(action)
        : null,
    icon: WaveControlIcon(icon, size: widget.quick ? 23 : 20),
    visualDensity: VisualDensity.compact,
  );

  Widget _play() => StreamBuilder<PlaybackState>(
    stream: c.audio.playbackState,
    builder: (context, snapshot) {
      final v = waveVisuals(context);
      final busy = [
        AudioProcessingState.loading,
        AudioProcessingState.buffering,
      ].contains(snapshot.data?.processingState);
      return IconButton.filled(
        key: const Key('desktop-quick-play'),
        tooltip: wt(
          c.audio.playing ? 'native.03498e395a' : 'native.c750dc7d94',
          context: context,
        ),
        style: IconButton.styleFrom(
          minimumSize: Size.square(widget.quick ? 56 : 40),
          maximumSize: Size.square(widget.quick ? 56 : 40),
          backgroundColor: v.ink,
          foregroundColor: v.background,
        ),
        onPressed: c.canTogglePlayback && c.audio.viewCurrent != null
            ? () => _run(c.audio.playing ? c.audio.pause : c.audio.play)
            : null,
        icon: busy
            ? SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: v.background,
                ),
              )
            : WavePlayPauseIcon(
                playing: c.audio.playing,
                size: widget.quick ? 30 : 25,
              ),
      );
    },
  );

  Widget _metadata({bool centered = false}) {
    final v = waveVisuals(context), track = c.audio.viewCurrent;
    return GestureDetector(
      key: const Key('desktop-player-swipe'),
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: (_) => _swipe = 0,
      onHorizontalDragUpdate: (details) => _swipe += details.delta.dx,
      onHorizontalDragEnd: (details) {
        if (!c.canControl ||
            track == null ||
            (_swipe.abs() < 42 && details.primaryVelocity!.abs() < 700)) {
          return;
        }
        _run(_swipe < 0 ? c.audio.skipToNext : c.audio.skipToPrevious);
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: centered
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          ScrollingLabel(
            track?.title ?? wt('native.899c8de911', context: context),
            textAlign: centered ? TextAlign.center : TextAlign.start,
            style: TextStyle(
              fontSize: centered ? 16 : 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          if (track?.playback['attribution'] is Map)
            SourceAttribution(controller: c, track: track!, compact: true)
          else
            ScrollingLabel(
              track?.artist ?? wt('native.b196b73079', context: context),
              textAlign: centered ? TextAlign.center : TextAlign.start,
              style: TextStyle(color: v.muted, fontSize: centered ? 11 : 10),
            ),
        ],
      ),
    );
  }

  Widget _header() {
    final v = waveVisuals(context);
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            key: const Key('desktop-player-drag'),
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => _run(c.desktop.drag),
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: widget.quick ? 0 : 4),
              child: widget.quick
                  ? const Brand(size: 24)
                  : Text(
                      'GLUKWAVE',
                      style: TextStyle(
                        color: v.muted,
                        fontSize: 8,
                        letterSpacing: 1.6,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
            ),
          ),
        ),
        IconButton(
          key: const Key('desktop-player-expand'),
          tooltip: wt('native.6c1e1967ba', context: context),
          visualDensity: VisualDensity.compact,
          onPressed: () => _run(c.desktop.showMain),
          icon: Icon(Icons.open_in_full_rounded, size: widget.quick ? 17 : 14),
        ),
        if (widget.quick)
          IconButton(
            key: const Key('desktop-quick-dismiss'),
            tooltip: wt('native.4ae50d3073', context: context),
            visualDensity: VisualDensity.compact,
            onPressed: () => _run(c.desktop.dismissQuick),
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final v = waveVisuals(context), track = c.audio.viewCurrent;
    return Scaffold(
      backgroundColor: v.surface,
      body: Listener(
        key: const Key('desktop-player-scroll'),
        onPointerSignal: _wheel,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            widget.quick ? 22 : 14,
            widget.quick ? 14 : 2,
            widget.quick ? 22 : 14,
            widget.quick ? 14 : 8,
          ),
          child: widget.quick
              ? Column(
                  children: [
                    _header(),
                    Divider(color: v.line, height: 22),
                    Expanded(
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (track != null)
                              Artwork(
                                controller: c,
                                trackLoading: c.trackLoading,
                                url: track.artwork,
                                size: 88,
                                radius: 15,
                              )
                            else
                              Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  color: v.accentSoft,
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: Icon(
                                  Icons.music_note_rounded,
                                  size: 31,
                                  color: v.accent,
                                ),
                              ),
                            const SizedBox(height: 16),
                            _metadata(centered: true),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _control(
                          Icons.skip_previous_rounded,
                          wt('native.8e1abb9475', context: context),
                          c.audio.skipToPrevious,
                          key: const Key('desktop-quick-previous'),
                        ),
                        const SizedBox(width: 13),
                        _play(),
                        const SizedBox(width: 13),
                        _control(
                          Icons.skip_next_rounded,
                          wt('native.c97fa8b29b', context: context),
                          c.audio.skipToNext,
                          key: const Key('desktop-quick-next'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        WaveControlIcon(
                          Icons.volume_up_outlined,
                          color: v.muted,
                          size: 18,
                        ),
                        Expanded(
                          child: VolumeSlider(
                            key: const Key('desktop-quick-volume'),
                            value: c.audio.volume.clamp(0, 1),
                            onChanged: (value) => _run(
                              () => c.transport('volume', {'volume': value}),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 31,
                          child: Text(
                            '${(c.audio.volume * 100).round()}%',
                            textAlign: TextAlign.end,
                            style: TextStyle(color: v.muted, fontSize: 10),
                          ),
                        ),
                      ],
                    ),
                  ],
                )
              : Column(
                  children: [
                    SizedBox(height: 30, child: _header()),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (track != null)
                          Artwork(
                            controller: c,
                            trackLoading: c.trackLoading,
                            url: track.artwork,
                            size: 44,
                            radius: 9,
                          )
                        else
                          Icon(
                            Icons.music_note_rounded,
                            size: 36,
                            color: v.accent,
                          ),
                        const SizedBox(width: 10),
                        Expanded(child: _metadata()),
                        _control(
                          Icons.skip_previous_rounded,
                          wt('native.8e1abb9475', context: context),
                          c.audio.skipToPrevious,
                        ),
                        _play(),
                        _control(
                          Icons.skip_next_rounded,
                          wt('native.c97fa8b29b', context: context),
                          c.audio.skipToNext,
                        ),
                      ],
                    ),
                    const SizedBox(height: 9),
                    StreamBuilder<Duration>(
                      stream: c.audio.positionStream,
                      builder: (context, position) => ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          minHeight: 2,
                          value: track != null && track.duration > 0
                              ? ((position.data?.inMilliseconds ?? 0) /
                                        1000 /
                                        track.duration)
                                    .clamp(0, 1)
                              : 0,
                          backgroundColor: v.line,
                          color: v.accent,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
