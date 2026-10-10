import 'package:flutter/material.dart';
import '../core/models.dart';
import 'theme.dart';
import 'motion_icons.dart';

class HomeWidgetPreviewLabels {
  final String Function(String key) text;
  const HomeWidgetPreviewLabels({required this.text});
}

/// Faithful static layout previews, with the account's real current track.
/// Pin actions belong to the existing platform bridge; these never play audio.
class HomeWidgetPreviews extends StatelessWidget {
  final WaveTrack? track;
  final Widget? artwork;
  final bool playing, loading, signedIn, liked;
  final HomeWidgetPreviewLabels labels;
  final VoidCallback onPinPlayer, onPinWave;
  const HomeWidgetPreviews({
    super.key,
    this.track,
    this.artwork,
    this.playing = false,
    this.loading = false,
    this.signedIn = true,
    this.liked = false,
    required this.labels,
    required this.onPinPlayer,
    required this.onPinWave,
  });
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final large in [false, true]) ...[
        if (large) const SizedBox(height: 24),
        Text(
          labels.text(large ? 'wave' : 'player'),
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: HomeWidgetPreviewPanel(
            large: large,
            track: track,
            artwork: artwork,
            playing: playing,
            loading: loading,
            signedIn: signedIn,
            liked: liked,
            labels: labels,
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: large ? onPinWave : onPinPlayer,
          icon: const Icon(Icons.add_rounded, size: 19),
          label: Text(labels.text('add')),
        ),
      ],
    ],
  );
}

class HomeWidgetPreviewPanel extends StatelessWidget {
  final bool large, playing, loading, signedIn, liked;
  final WaveTrack? track;
  final Widget? artwork;
  final HomeWidgetPreviewLabels labels;
  final double? height;
  const HomeWidgetPreviewPanel({
    super.key,
    required this.large,
    this.track,
    this.artwork,
    this.playing = false,
    this.loading = false,
    this.signedIn = true,
    this.liked = false,
    required this.labels,
    this.height,
  });
  @override
  Widget build(BuildContext context) {
    final v = waveVisuals(context);
    final panelHeight = height ?? (large ? 200.0 : 80.0);
    final showStatus =
        large || MediaQuery.textScalerOf(context).scale(1) <= 1.1;
    final title = signedIn ? track?.title ?? labels.text('empty') : 'GlukWave';
    final artist = signedIn
        ? track?.artist ?? labels.text('ready')
        : labels.text('signedOut');
    final status = loading
        ? labels.text('loading')
        : track != null && !playing
        ? labels.text('paused')
        : '';
    Widget control(IconData icon, {bool main = false, bool active = false}) =>
        Container(
          width: main ? 48 : 44,
          height: main ? 48 : 44,
          decoration: main
              ? BoxDecoration(color: v.ink, shape: BoxShape.circle)
              : null,
          alignment: Alignment.center,
          child: WaveControlIcon(
            icon,
            size: 24,
            color: main
                ? v.background
                : active
                ? v.accent
                : v.ink,
          ),
        );
    Widget metadata(bool cover) => Row(
      children: [
        if (cover) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: SizedBox(
              width: 44,
              height: 44,
              child:
                  artwork ??
                  ColoredBox(
                    color: v.accentSoft,
                    child: Center(
                      child: WaveControlIcon(
                        Icons.waves_rounded,
                        color: v.accent,
                        size: 24,
                      ),
                    ),
                  ),
            ),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: v.ink,
                  fontSize: 13,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: v.muted, fontSize: 11, height: 1.2),
              ),
              if (status.isNotEmpty && showStatus) ...[
                const SizedBox(height: 3),
                Text(
                  status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: v.accent, fontSize: 9, height: 1.1),
                ),
              ],
            ],
          ),
        ),
      ],
    );
    return ExcludeSemantics(
      child: IgnorePointer(
        child: LayoutBuilder(
          builder: (_, constraints) {
            final narrow = constraints.maxWidth < 250;
            final play = control(
              playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              main: true,
            );
            return Container(
              height: panelHeight - 8,
              margin: const EdgeInsets.all(4),
              padding: EdgeInsets.all(large ? 12 : 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color.lerp(v.surface, v.accent, .025)!, v.surface],
                ),
                border: Border.all(color: v.line),
              ),
              child: large
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (panelHeight >= 215)
                          Text(
                            'GLUKWAVE',
                            style: TextStyle(
                              fontSize: 10,
                              color: v.muted,
                              letterSpacing: 1.2,
                              height: 1.2,
                            ),
                          ),
                        const SizedBox(height: 7),
                        ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 44),
                          child: metadata(true),
                        ),
                        Expanded(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (!narrow) control(Icons.skip_previous_rounded),
                              play,
                              if (!narrow) control(Icons.skip_next_rounded),
                              control(
                                liked
                                    ? Icons.favorite_rounded
                                    : Icons.favorite_border_rounded,
                                active: liked,
                              ),
                            ],
                          ),
                        ),
                        Container(
                          height: 44,
                          decoration: BoxDecoration(
                            color: v.accentSoft,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              WaveControlIcon(
                                Icons.waves_rounded,
                                color: v.accent,
                                size: 24,
                              ),
                              const SizedBox(width: 9),
                              Flexible(
                                child: Text(
                                  labels.text('wave'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: v.ink,
                                    fontSize: 12,
                                    height: 1.2,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(child: metadata(constraints.maxWidth >= 180)),
                        const SizedBox(width: 6),
                        if (!narrow) control(Icons.skip_previous_rounded),
                        play,
                        if (!narrow) control(Icons.skip_next_rounded),
                      ],
                    ),
            );
          },
        ),
      ),
    );
  }
}
