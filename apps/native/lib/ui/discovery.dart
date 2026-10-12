import 'package:flutter/material.dart';
import '../core/controller.dart';
import '../core/models.dart';
import '../l10n/listening_polish_strings.dart';
import '../l10n/wave_localizations.dart';
import 'motion_icons.dart';
import 'parity_panels.dart';
import 'widgets.dart';

/// Result types are one compact navigation row; provider filtering is secondary.
class DiscoveryView extends StatelessWidget {
  final WaveController controller;
  final String query, type, source;
  final bool loading;
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
  });

  @override
  Widget build(BuildContext context) {
    final c = controller, v = waveVisuals(context);
    final providers = {
      'all': wt('native.58b59eb005', context: context),
      'local': wt('native.1aa3589e13', context: context),
      'soundcloud': 'SoundCloud',
      'spotify': 'Spotify',
      'youtube': 'YouTube',
      'yandex': wt('native.0fb8bc0888', context: context),
    };
    bool shows(String value) => type == 'all' || type == value;
    Widget title(String value) => Padding(
      padding: const EdgeInsets.only(top: 28, bottom: 14),
      child: Text(
        polishText(value, context),
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: -.5,
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final value in [
                      'all',
                      'tracks',
                      'artists',
                      'playlists',
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 7),
                        child: WavePress(
                          child: ChoiceChip(
                            key: Key('search-type-$value'),
                            label: Text(polishText(value, context)),
                            selected: type == value,
                            showCheckmark: false,
                            selectedColor: v.ink,
                            labelStyle: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(
                                  color: type == value ? v.background : v.ink,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                            onSelected: (_) => onType(value),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            PopupMenuButton<String>(
              key: const Key('search-source-menu'),
              tooltip: polishText('source', context),
              initialValue: source,
              onSelected: onSource,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(v.corners(14)),
                side: BorderSide(color: v.line),
              ),
              itemBuilder: (_) => [
                for (final value in providers.entries)
                  PopupMenuItem(
                    value: value.key,
                    child: Row(
                      children: [
                        Expanded(child: Text(value.value)),
                        if (source == value.key)
                          Icon(Icons.check_rounded, size: 17, color: v.accent),
                      ],
                    ),
                  ),
              ],
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: source == 'all' ? v.surface : v.accentSoft,
                  border: Border.all(color: v.line),
                  borderRadius: BorderRadius.circular(v.corners(13)),
                ),
                child: WaveControlIcon(
                  Icons.graphic_eq_rounded,
                  size: 20,
                  color: v.muted,
                ),
              ),
            ),
          ],
        ),
        if (source != 'all')
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              providers[source] ?? source,
              style: TextStyle(color: v.muted, fontSize: 11),
            ),
          ),
        if (loading)
          const Padding(
            padding: EdgeInsets.only(top: 20),
            child: WaveLoadingList(key: Key('search-loading')),
          )
        else if (query.trim().isEmpty) ...[
          title('categories'),
          LayoutBuilder(
            builder: (context, box) {
              final columns = box.maxWidth < 400
                  ? 2
                  : box.maxWidth < 700
                  ? 3
                  : 4;
              final width = (box.maxWidth - (columns - 1) * 12) / columns;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final genre in [
                    'Pop',
                    'Hip-Hop',
                    'Electronic',
                    'Rock',
                    'Ambient',
                    'Jazz',
                  ])
                    SizedBox(
                      width: width,
                      child: WavePress(
                        child: InkWell(
                          key: Key('browse-category-$genre'),
                          borderRadius: BorderRadius.circular(v.corners(18)),
                          onTap: () => onQuery(genre),
                          child: Container(
                            constraints: const BoxConstraints(minHeight: 94),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Color.lerp(
                                v.surface,
                                v.accent,
                                .06 +
                                    [
                                          'Pop',
                                          'Hip-Hop',
                                          'Electronic',
                                          'Rock',
                                          'Ambient',
                                          'Jazz',
                                        ].indexOf(genre) *
                                        .025,
                              ),
                              borderRadius: BorderRadius.circular(
                                v.corners(18),
                              ),
                              border: Border.all(color: v.line),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                WaveControlIcon(
                                  Icons.album_outlined,
                                  size: 20,
                                  color: v.accent,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  genre,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
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
          ),
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
                        title('artists'),
                        DiscoveryArtists(controller: c, artists: artists),
                      ],
                    );
            },
          ),
          if (c.playlists.isNotEmpty) ...[
            title('playlists'),
            DiscoveryPlaylists(
              controller: c,
              playlists: c.playlists,
              onTap: onPlaylist,
            ),
          ],
        ] else ...[
          if (c.results.isEmpty &&
              c.artistResults.isEmpty &&
              c.playlistResults.isEmpty)
            EmptyState(
              wt('native.e61d08951b', context: context),
              wt('native.10c727a4cc', context: context),
            )
          else ...[
            if (shows('tracks') && c.results.isNotEmpty) ...[
              title('tracks'),
              for (final track in type == 'all' ? c.results.take(6) : c.results)
                TrackRow(
                  controller: c,
                  track: track,
                  queue: c.results,
                  onMore: () => onMore(track),
                ),
              if (type == 'all' && c.results.length > 6)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => onType('tracks'),
                    child: Text(polishText('tracks', context)),
                  ),
                ),
            ],
            if (shows('artists') && c.artistResults.isNotEmpty) ...[
              title('artists'),
              DiscoveryArtists(controller: c, artists: c.artistResults),
            ],
            if (shows('playlists') && c.playlistResults.isNotEmpty) ...[
              title('playlists'),
              DiscoveryPlaylists(
                controller: c,
                playlists: c.playlistResults,
                onTap: onPlaylist,
              ),
            ],
            if (type == 'artists' && c.artistResults.isEmpty ||
                type == 'playlists' && c.playlistResults.isEmpty ||
                type == 'tracks' && c.results.isEmpty)
              EmptyState(
                wt('native.e61d08951b', context: context),
                wt('native.10c727a4cc', context: context),
              ),
          ],
        ],
      ],
    );
  }
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
) => Navigator.push(
  context,
  MaterialPageRoute<void>(
    builder: (context) => Scaffold(
      appBar: AppBar(
        title: Text(
          playlist['name']?.toString() ?? polishText('playlists', context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          ApiPanel(
            controller: c,
            path:
                '/api/playlists/${Uri.encodeComponent(playlist['id'].toString())}',
            builder: (data, _) {
              final tracks = objects(
                data['tracks'],
              ).map(WaveTrack.new).toList();
              final detail = object(data['playlist']);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: PlaylistArtwork(
                      controller: c,
                      playlist: detail.isEmpty ? playlist : detail,
                      size: 220,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    playlist['name']?.toString() ?? '',
                    style: const TextStyle(
                      fontSize: 27,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (playlist['description']?.toString().isNotEmpty == true)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(playlist['description'].toString()),
                    ),
                  const SizedBox(height: 24),
                  for (final track in tracks)
                    TrackRow(
                      controller: c,
                      track: track,
                      queue: tracks,
                      onMore: () => parityTrackActions(context, c, track),
                    ),
                  if (tracks.isEmpty)
                    EmptyState(
                      wt('native.1adc5a6a23', context: context),
                      wt('native.29f6c0dba0', context: context),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    ),
  ),
);
