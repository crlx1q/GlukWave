import '../l10n/parity_strings.dart';
import '../l10n/wave_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../core/controller.dart';
import '../core/models.dart';
import 'widgets.dart';

/// One width/input decision for the shell, dock and detail destinations.
class ClientLayout {
  final double width;
  final bool desktop;
  const ClientLayout(this.width, this.desktop);
  factory ClientLayout.of(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final desktopPlatform = switch (defaultTargetPlatform) {
      TargetPlatform.windows ||
      TargetPlatform.macOS ||
      TargetPlatform.linux => true,
      _ => false,
    };
    return ClientLayout(width, width >= 900 || desktopPlatform && width >= 720);
  }
  bool get labelledSidebar => desktop && width >= 1100;
  bool get contextPane => desktop && width >= 1280;
  double get sidebarWidth => labelledSidebar ? 224 : 76;
  double get gutter => desktop ? (width >= 1280 ? 30 : 24) : 18;
  EdgeInsets get pagePadding =>
      EdgeInsets.fromLTRB(gutter, desktop ? 28 : 20, gutter, 32);
}

/// A collection marker that the workspace turns into a lazy sliver. Keeping the
/// header and track rows in one scroll view avoids nested, eager music lists.
class ClientTrackRows extends StatelessWidget {
  final WaveController controller;
  final List<WaveTrack> tracks;
  final ValueChanged<WaveTrack> onMore;
  const ClientTrackRows({
    super.key,
    required this.controller,
    required this.tracks,
    required this.onMore,
  });
  Widget row(BuildContext context, int index) => TrackRow(
    key: ValueKey('collection-track-${tracks[index].id}'),
    controller: controller,
    track: tracks[index],
    queue: tracks,
    index: ClientLayout.of(context).desktop ? index + 1 : null,
    onMore: () => onMore(tracks[index]),
  );
  @override
  Widget build(BuildContext context) => ListView.builder(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    itemCount: tracks.length,
    itemBuilder: row,
  );
}

class ClientScrollPage extends StatelessWidget {
  final Widget content;
  final String storageKey;
  const ClientScrollPage({
    super.key,
    required this.content,
    required this.storageKey,
  });
  @override
  Widget build(BuildContext context) {
    final layout = ClientLayout.of(context);
    final children = content is Column
        ? (content as Column).children
        : [content];
    final scroll = CustomScrollView(
      key: PageStorageKey(storageKey),
      slivers: [
        SliverPadding(
          padding: layout.pagePadding,
          sliver: SliverMainAxisGroup(
            slivers: [
              for (final child in children)
                if (child is ClientTrackRows)
                  SliverMainAxisGroup(
                    slivers: [
                      if (layout.desktop)
                        const SliverToBoxAdapter(child: _ClientTrackHeader()),
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          child.row,
                          childCount: child.tracks.length,
                        ),
                      ),
                    ],
                  )
                else
                  SliverToBoxAdapter(child: child),
            ],
          ),
        ),
      ],
    );
    return content.key != null
        ? KeyedSubtree(key: content.key, child: scroll)
        : scroll;
  }
}

class _ClientTrackHeader extends StatelessWidget {
  const _ClientTrackHeader();
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final v = waveVisuals(context);
      final label = TextStyle(
        color: v.muted,
        fontSize: 10,
        fontWeight: FontWeight.w600,
      );
      return Container(
        key: const Key('desktop-track-table-header'),
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
        margin: const EdgeInsets.only(bottom: 5),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: v.line)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 33,
              child: Text('#', textAlign: TextAlign.center, style: label),
            ),
            Expanded(
              child: Text(
                parityLabel(WaveStrings.current.language, 'Tracks'),
                style: label,
              ),
            ),
            if (bounds.maxWidth >= 600)
              SizedBox(
                width: 132,
                child: Text(
                  wt('native.5384db72a4', context: context),
                  style: label,
                ),
              ),
            if (bounds.maxWidth > 340)
              SizedBox(
                width: 44,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Icon(Icons.schedule_rounded, size: 14, color: v.muted),
                ),
              ),
            const SizedBox(width: 88),
          ],
        ),
      );
    },
  );
}
