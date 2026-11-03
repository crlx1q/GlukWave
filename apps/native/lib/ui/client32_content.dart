import 'package:flutter/material.dart';
import '../core/controller.dart';
import '../core/models.dart';
import 'widgets.dart';
import 'client32_design.dart';

/// A bounded page owns one viewport. Track children are created on demand and
/// retain their identity while metadata, playback, or library state changes.
class ClientContentScroll extends StatelessWidget {
  final List<Widget> slivers;
  final EdgeInsetsGeometry? padding;
  const ClientContentScroll({super.key, required this.slivers, this.padding});

  @override
  Widget build(BuildContext context) => CustomScrollView(
    slivers: [
      SliverPadding(
        padding: padding ?? ClientLayout.of(context).pagePadding,
        sliver: SliverMainAxisGroup(slivers: slivers),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 24)),
    ],
  );
}

Widget clientBox(Widget child) => SliverToBoxAdapter(child: child);

Widget clientTracks({
  required WaveController controller,
  required List<WaveTrack> tracks,
  required ValueChanged<WaveTrack> onMore,
  List<WaveTrack>? queue,
  Future<void> Function(WaveTrack)? onPlay,
}) => SliverList.builder(
  itemCount: tracks.length,
  itemBuilder: (context, index) {
    final track = tracks[index];
    return TrackRow(
      key: ValueKey('content-track-${track.id}'),
      controller: controller,
      track: track,
      index: ClientLayout.of(context).desktop ? index + 1 : null,
      queue: queue ?? tracks,
      onPlay: onPlay == null ? null : () => onPlay(track),
      onMore: () => onMore(track),
    );
  },
);

class ClientSectionHeading extends StatelessWidget {
  final String title;
  final Widget? action;
  const ClientSectionHeading(this.title, {super.key, this.action});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 28, bottom: 12),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -.55,
            ),
          ),
        ),
        if (action != null) action!,
      ],
    ),
  );
}

/// Real metadata is the visual anchor; this hero never invents counts or art.
class ClientCollectionHero extends StatelessWidget {
  final Widget artwork;
  final String title;
  final String? eyebrow, description;
  final List<Widget> actions;
  const ClientCollectionHero({
    super.key,
    required this.artwork,
    required this.title,
    this.eyebrow,
    this.description,
    this.actions = const [],
  });
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final v = waveVisuals(context), wide = box.maxWidth >= 560;
      final copy = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (eyebrow?.isNotEmpty == true) ...[
            Text(
              eyebrow!.toUpperCase(),
              style: TextStyle(
                color: v.muted,
                fontSize: 10,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
          ],
          Text(
            title,
            style: TextStyle(
              fontSize: wide ? 38 : 28,
              height: 1.12,
              letterSpacing: wide ? -1.3 : -.8,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (description?.isNotEmpty == true) ...[
            const SizedBox(height: 13),
            Text(
              description!,
              style: TextStyle(color: v.muted, fontSize: 13, height: 1.65),
            ),
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 22),
            Wrap(spacing: 10, runSpacing: 10, children: actions),
          ],
        ],
      );
      return Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 8),
        child: wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  artwork,
                  const SizedBox(width: 28),
                  Expanded(child: copy),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [artwork, const SizedBox(height: 24), copy],
              ),
      );
    },
  );
}
