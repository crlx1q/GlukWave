import 'package:flutter/material.dart';
import '../core/controller.dart';
import '../core/models.dart';
import '../l10n/listening_polish_strings.dart';
import '../l10n/glukwave26_strings.dart';
import '../l10n/parity_strings.dart';
import '../l10n/wave_localizations.dart';
import 'client32_content.dart';
import 'client32_workspace.dart';
import 'motion_icons.dart';
import 'parity_panels.dart';
import 'widgets.dart';

/// Search owns one bounded viewport in the workspace. The legacy inline mode
/// remains available to small independently embedded discovery sections.
class DiscoveryView extends StatelessWidget {
  final WaveController controller;
  final String query, type, source;
  final bool loading, scrollable;
  final Widget? header;
  final ValueChanged<String> onType, onSource, onQuery;
  final ValueChanged<Json> onPlaylist;
  final ValueChanged<WaveTrack> onMore;
  const DiscoveryView({
    super.key,
    required this.controller,
    required this.query,
    required this.type,
    required this.source,
    required this.loading,
    required this.onType,
    required this.onSource,
    required this.onQuery,
    required this.onPlaylist,
    required this.onMore,
    this.scrollable = false,
    this.header,
  });

  @override
  Widget build(BuildContext context) {
    final c = controller, v = waveVisuals(context);
    final providers = <String, String>{
      'all': wt('native.58b59eb005', context: context),
      'local': wt('native.1aa3589e13', context: context),
      'soundcloud': 'SoundCloud',
      'spotify': 'Spotify',
      'youtube': 'YouTube',
      'yandex': wt('native.0fb8bc0888', context: context),
    };
    final children = <Widget>[];
    void add(Widget child) =>
        children.add(scrollable ? clientBox(child) : child);
    void section(String title) =>
        add(ClientSectionHeading(polishText(title, context)));
    bool shows(String value) => type == 'all' || type == value;
    if (header != null) add(header!);
    add(
      LayoutBuilder(
        builder: (context, box) {
          final provider = PopupMenuButton<String>(
            key: const Key('search-source-menu'),
            tooltip: polishText('source', context),
            initialValue: source,
            onSelected: onSource,
            itemBuilder: (_) => [
              for (final entry in providers.entries)
                CheckedPopupMenuItem(
                  value: entry.key,
                  checked: source == entry.key,
                  child: Text(entry.value),
                ),
            ],
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
              decoration: BoxDecoration(
                color: v.surface,
                border: Border.all(color: v.line),
                borderRadius: BorderRadius.circular(v.corners(12)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.tune_rounded, size: 17, color: v.muted),
                  const SizedBox(width: 8),
                  Text(
                    providers[source] ?? source,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Icon(Icons.expand_more_rounded, size: 17, color: v.muted),
                ],
              ),
            ),
          );
          final filters = SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final value in ['all', 'tracks', 'artists', 'playlists'])
                  Padding(
                    padding: const EdgeInsets.only(right: 7),
                    child: ChoiceChip(
                      key: Key('search-type-$value'),
                      label: Text(polishText(value, context)),
                      selected: type == value,
                      showCheckmark: false,
                      selectedColor: v.ink,
                      labelStyle: TextStyle(
                        color: type == value ? v.background : v.ink,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                      onSelected: (_) => onType(value),
                    ),
                  ),
              ],
            ),
          );
          return box.maxWidth < 480
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [filters, const SizedBox(height: 12), provider],
                )
              : Row(
                  children: [
                    Expanded(child: filters),
                    const SizedBox(width: 16),
                    provider,
                  ],
                );
        },
      ),
    );
    if (c.searchProviderErrors.isNotEmpty || c.searchError != null) {
      add(
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Container(
            decoration: BoxDecoration(
              color: v.surface,
              borderRadius: BorderRadius.circular(v.corners(12)),
              border: Border.all(color: v.line),
            ),
            child: ExpansionTile(
              key: const Key('search-provider-errors'),
              tilePadding: const EdgeInsets.symmetric(horizontal: 14),
              leading: Icon(Icons.cloud_off_outlined, size: 19, color: v.muted),
              title: Text(
                c.searchError ?? pt(context, 'Unavailable'),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              children: [
                for (final error in c.searchProviderErrors)
                  ListTile(
                    dense: true,
                    title: Text(
                      providers[error['provider']] ??
                          error['provider']?.toString() ??
                          '',
                    ),
                    subtitle: Text(
                      (error['message'] ?? error['reason'] ?? '').toString(),
                    ),
                  ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => c.search(query, source: source),
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: Text(pt(context, 'Retry')),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (loading && c.results.isEmpty && query.trim().isNotEmpty) {
      add(
        const Padding(
          padding: EdgeInsets.only(top: 24),
          child: WaveLoadingList(key: Key('search-loading')),
        ),
      );
    } else if (query.trim().isEmpty) {
      section('categories');
      add(_DiscoveryGenres(onQuery: onQuery));
      add(
        ApiPanel(
          controller: c,
          path: '/api/artists?limit=12',
          builder: (data, _) {
            final artists = objects(data['artists']).take(12).toList();
            return artists.isEmpty
                ? const SizedBox.shrink()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClientSectionHeading(polishText('artists', context)),
                      DiscoveryArtists(controller: c, artists: artists),
                    ],
                  );
          },
        ),
      );
      if (c.playlists.isNotEmpty) {
        section('playlists');
        add(
          DiscoveryPlaylists(
            controller: c,
            playlists: c.playlists,
            onTap: onPlaylist,
          ),
        );
      }
    } else {
      if (loading || c.searchPendingProviders.isNotEmpty) {
        add(
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: LinearProgressIndicator(minHeight: 2, color: v.accent),
          ),
        );
      }
      if (c.results.isEmpty &&
          c.artistResults.isEmpty &&
          c.playlistResults.isEmpty &&
          !loading) {
        add(
          EmptyState(
            wt('native.e61d08951b', context: context),
            wt('native.10c727a4cc', context: context),
          ),
        );
      } else {
        if (shows('tracks') && c.results.isNotEmpty) {
          section('tracks');
          final visible = type == 'all'
              ? c.results.take(6).toList()
              : c.results;
          if (scrollable) {
            children.add(
              clientTracks(
                controller: c,
                tracks: visible,
                queue: c.results,
                onMore: onMore,
              ),
            );
          } else {
            for (final track in visible) {
              add(
                TrackRow(
                  key: ValueKey('search-track-${track.id}'),
                  controller: c,
                  track: track,
                  queue: c.results,
                  onMore: () => onMore(track),
                ),
              );
            }
          }
          if (type == 'all' && c.results.length > 6) {
            add(
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => onType('tracks'),
                  child: Text(polishText('tracks', context)),
                ),
              ),
            );
          }
        }
        if (shows('artists') && c.artistResults.isNotEmpty) {
          section('artists');
          add(DiscoveryArtists(controller: c, artists: c.artistResults));
        }
        if (shows('playlists') && c.playlistResults.isNotEmpty) {
          section('playlists');
          add(
            DiscoveryPlaylists(
              controller: c,
              playlists: c.playlistResults,
              onTap: onPlaylist,
            ),
          );
        }
        if (!loading &&
            (type == 'artists' && c.artistResults.isEmpty ||
                type == 'playlists' && c.playlistResults.isEmpty ||
                type == 'tracks' && c.results.isEmpty)) {
          add(
            EmptyState(
              wt('native.e61d08951b', context: context),
              wt('native.10c727a4cc', context: context),
            ),
          );
        }
      }
    }
    return scrollable
        ? ClientContentScroll(
            key: const Key('discovery-scroll'),
            slivers: children,
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          );
  }
}

class _DiscoveryGenres extends StatelessWidget {
  final ValueChanged<String> onQuery;
  const _DiscoveryGenres({required this.onQuery});
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final v = waveVisuals(context),
          columns = box.maxWidth < 440
              ? 2
              : box.maxWidth < 720
              ? 3
              : 3;
      final width = (box.maxWidth - (columns - 1) * 12) / columns;
      const genres = <(String, IconData)>[
        ('Pop', Icons.auto_awesome_outlined),
        ('Hip-Hop', Icons.mic_none_rounded),
        ('Electronic', Icons.graphic_eq_rounded),
        ('Rock', Icons.bolt_rounded),
        ('Ambient', Icons.waves_rounded),
        ('Jazz', Icons.piano_outlined),
      ];
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (var i = 0; i < genres.length; i++)
            SizedBox(
              width: width,
              child: Material(
                color: Color.lerp(v.surface, v.accent, .02 + i * .012),
                borderRadius: BorderRadius.circular(v.corners(16)),
                child: InkWell(
                  key: Key('browse-category-${genres[i].$1}'),
                  onTap: () => onQuery(genres[i].$1),
                  borderRadius: BorderRadius.circular(v.corners(16)),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 114),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(genres[i].$2, color: v.muted, size: 26),
                            const Spacer(),
                            Text(
                              '0${i + 1}',
                              style: TextStyle(
                                fontSize: 10,
                                color: v.muted,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        Text(
                          genres[i].$1,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}

class DiscoveryArtists extends StatelessWidget {
  final WaveController controller;
  final List<Json> artists;
  const DiscoveryArtists({
    super.key,
    required this.controller,
    required this.artists,
  });
  @override
  Widget build(BuildContext context) {
    final v = waveVisuals(context),
        compact = MediaQuery.sizeOf(context).width < 700;
    final size = compact ? 86.0 : 108.0;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final artist in artists)
            Padding(
              padding: const EdgeInsets.only(right: 18),
              child: SizedBox(
                width: size + 8,
                child: WavePress(
                  child: InkWell(
                    key: ValueKey('search-artist-${artist['id']}'),
                    borderRadius: BorderRadius.circular(v.corners(14)),
                    onTap: () => openArtist(context, controller, artist),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Column(
                        children: [
                          ClipOval(
                            child: Artwork(
                              controller: controller,
                              url: artist['artwork']?.toString(),
                              size: size,
                              radius: 0,
                              icon: Icons.person_outline_rounded,
                            ),
                          ),
                          const SizedBox(height: 11),
                          Text(
                            artist['name']?.toString() ?? '',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class DiscoveryPlaylists extends StatelessWidget {
  final WaveController controller;
  final List<Json> playlists;
  final ValueChanged<Json> onTap;
  const DiscoveryPlaylists({
    super.key,
    required this.controller,
    required this.playlists,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final v = waveVisuals(context),
        size = MediaQuery.sizeOf(context).width < 700 ? 142.0 : 174.0;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final playlist in playlists)
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: SizedBox(
                width: size,
                child: WavePress(
                  child: InkWell(
                    key: ValueKey('search-playlist-${playlist['id']}'),
                    borderRadius: BorderRadius.circular(v.corners(16)),
                    onTap: () => onTap(playlist),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        PlaylistArtwork(
                          controller: controller,
                          playlist: playlist,
                          size: size,
                        ),
                        const SizedBox(height: 11),
                        Text(
                          playlist['name']?.toString() ?? '',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (playlist['description']?.toString().isNotEmpty ==
                            true)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              playlist['description'].toString(),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: v.muted,
                                fontSize: 10,
                                height: 1.5,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

Future<void> openDiscoveryPlaylist(
  BuildContext context,
  WaveController c,
  Json playlist,
) => openClientDetail(
  context,
  title: playlist['name']?.toString() ?? polishText('playlists', context),
  identity: 'playlist:${playlist['id']}',
  builder: (_) => DiscoveryPlaylistContent(controller: c, playlist: playlist),
);

class DiscoveryPlaylistContent extends StatelessWidget {
  final WaveController controller;
  final Json playlist;
  const DiscoveryPlaylistContent({
    super.key,
    required this.controller,
    required this.playlist,
  });
  @override
  Widget build(BuildContext context) => ApiPanel(
    controller: controller,
    path: '/api/playlists/${Uri.encodeComponent(playlist['id'].toString())}',
    bounded: true,
    builder: (data, _) {
      final tracks = objects(data['tracks']).map(WaveTrack.new).toList();
      final detail = {...playlist, ...object(data['playlist'])};
      final size = MediaQuery.sizeOf(context).width < 600 ? 164.0 : 206.0;
      return ClientContentScroll(
        key: ValueKey('playlist-detail-${playlist['id']}'),
        slivers: [
          clientBox(
            ClientCollectionHero(
              artwork: PlaylistArtwork(
                controller: controller,
                playlist: detail,
                size: size,
              ),
              title: detail['name']?.toString() ?? '',
              eyebrow: polishText('playlists', context),
              description: detail['description']?.toString(),
              actions: [
                if (tracks.isNotEmpty)
                  FilledButton.icon(
                    key: const Key('public-playlist-play'),
                    onPressed: controller.canControl
                        ? () => parityRun(
                            controller,
                            () => controller.play(tracks.first, list: tracks),
                          )
                        : null,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: Text(wave26Text(context, 'artist.playAll')),
                  ),
              ],
            ),
          ),
          clientBox(ClientSectionHeading(polishText('tracks', context))),
          if (tracks.isEmpty)
            clientBox(
              EmptyState(
                wt('native.1adc5a6a23', context: context),
                wt('native.29f6c0dba0', context: context),
              ),
            )
          else
            clientTracks(
              controller: controller,
              tracks: tracks,
              onMore: (track) => parityTrackActions(context, controller, track),
            ),
        ],
      );
    },
  );
}
