import 'package:flutter/material.dart';
import '../core/controller.dart';
import '../l10n/wave_localizations.dart';
import 'widgets.dart';
import 'device_labels.dart';

/// Confirmed output summary. Persistent transport owns playback controls.
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
        ],
      ),
    );
  }
}
