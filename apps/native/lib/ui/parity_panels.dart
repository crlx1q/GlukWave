import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../core/controller.dart';
import '../core/models.dart';
import '../core/parity.dart';
import '../l10n/parity_strings.dart';
import '../l10n/wave_localizations.dart';
import 'widgets.dart';

String paritySourceName(BuildContext context, dynamic source) =>
    switch (source) {
      'youtube' => 'YouTube',
      'spotify' => 'Spotify',
      'soundcloud' => 'SoundCloud',
      'yandex' => wt('native.0fb8bc0888', context: context),
      _ => wt('native.8df71302b3', context: context),
    };

Future<void> parityRun(WaveController c, Future<void> Function() action) async {
  try {
    await action();
  } catch (e) {
    c.tell(e.toString());
  }
}

Future<void> parityTrackActions(
  BuildContext context,
  WaveController c,
  WaveTrack track,
) => showModalBottomSheet<void>(
  context: context,
  useSafeArea: true,
  builder: (sheet) => Padding(
    padding: const EdgeInsets.all(20),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          leading: Artwork(controller: c, url: track.artwork),
          title: Text(track.title, maxLines: 2),
          subtitle: Text(track.artist),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.queue_music),
          title: Text(wt('native.f130436a3b', context: sheet)),
          enabled: c.canControl,
          onTap: () {
            Navigator.pop(sheet);
            unawaited(
              parityRun(c, () => c.audio.addQueueItem(c.audio.item(track))),
            );
          },
        ),
        ListTile(
          leading: const Icon(Icons.playlist_add),
          title: Text(wt('native.df0c76065d', context: sheet)),
          onTap: () async {
            Navigator.pop(sheet);
            final playlist = await showWaveDialog<Json>(
              context: context,
              builder: (dialog) => SimpleDialog(
                title: Text(wt('native.81524f9e71', context: dialog)),
                children: [
                  for (final p in c.playlists)
                    SimpleDialogOption(
                      onPressed: () => Navigator.pop(dialog, p),
                      child: Text(p['name'].toString()),
                    ),
                  if (c.playlists.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(wt('native.9feaa9c30e', context: dialog)),
                    ),
                ],
              ),
            );
            if (playlist != null) {
              await parityRun(c, () => c.addToPlaylist(playlist, track));
            }
          },
        ),
        if (track.offline)
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: Text(wt('native.5fbca5dea7', context: sheet)),
            onTap: () {
              Navigator.pop(sheet);
              unawaited(
                parityRun(c, () async {
                  await c.cache.save(track, manual: true);
                }),
              );
            },
          ),
        if (track.sourceUrl.isNotEmpty)
          ListTile(
            leading: const Icon(Icons.open_in_new),
            title: Text(
              wt(
                'native.22618d4822',
                context: sheet,
                values: {'p0': track.sourceName},
              ),
            ),
            onTap: () {
              Navigator.pop(sheet);
              unawaited(parityRun(c, () => c.openUrl(track.sourceUrl)));
            },
          ),
      ],
    ),
  ),
);

/// Owns optional endpoint states independently of playback/library refresh.
class ApiPanel extends StatefulWidget {
  final WaveController controller;
  final String path;
  final Widget Function(Json, Future<void> Function()) builder;
  final Listenable? refresh;
  final Future<Json> Function()? loadData;
  const ApiPanel({
    super.key,
    required this.controller,
    required this.path,
    required this.builder,
    this.refresh,
    this.loadData,
  });
  @override
  State<ApiPanel> createState() => _ApiPanelState();
}

class _ApiPanelState extends State<ApiPanel> {
  Json? data;
  bool failed = false;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    widget.refresh?.addListener(refresh);
    unawaited(load());
  }

  @override
  void didUpdateWidget(ApiPanel old) {
    super.didUpdateWidget(old);
    if (old.refresh != widget.refresh) {
      old.refresh?.removeListener(refresh);
      widget.refresh?.addListener(refresh);
    }
    if (old.path != widget.path || old.controller != widget.controller) {
      unawaited(load());
    }
  }

  Future<void> load() async {
    final request = ++generation, api = widget.controller.api;
    final token = api.token, origin = api.server;
    if (mounted) {
      setState(() {
        failed = false;
        data = null;
      });
    }
    try {
      final result = await (widget.loadData?.call() ?? api.call(widget.path));
      if (result['_error'] != null) {
        throw StateError(result['_error'].toString());
      }
      if (mounted &&
          request == generation &&
          token == api.token &&
          origin == api.server) {
        setState(() => data = result);
      }
    } catch (_) {
      if (mounted &&
          request == generation &&
          token == api.token &&
          origin == api.server) {
        setState(() => failed = true);
      }
    }
  }

  @override
  void dispose() {
    widget.refresh?.removeListener(refresh);
    generation++;
    super.dispose();
  }

  void refresh() => unawaited(load());

  @override
  Widget build(BuildContext context) => failed
      ? EmptyState(
          pt(context, 'Unavailable'),
          pt(context, 'Unavailable detail'),
          icon: Icons.cloud_off_outlined,
          action: OutlinedButton.icon(
            onPressed: load,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(pt(context, 'Retry')),
          ),
        )
      : data == null
      ? const WaveLoadingList()
      : widget.builder(data!, load);
}

class TasteInvitation extends StatelessWidget {
  final WaveParity parity;
  final VoidCallback onOpen;
  const TasteInvitation({
    super.key,
    required this.parity,
    required this.onOpen,
  });
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: parity,
    builder: (context, _) {
      if (parity.preference.isEmpty ||
          parity.preference['onboardingCompleted'] == true) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: const EdgeInsets.only(bottom: 22),
        child: Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.waves_rounded, color: waveVisuals(context).accent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      pt(context, 'Welcome'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                pt(context, 'Taste subtitle'),
                style: TextStyle(
                  color: waveVisuals(context).muted,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  FilledButton(
                    onPressed: onOpen,
                    child: Text(pt(context, 'Start')),
                  ),
                  TextButton(
                    onPressed: () => parity
                        .saveTaste({
                          'artists': [],
                          'onboardingCompleted': true,
                          'onboardingStep': 3,
                        })
                        .catchError((Object _) {}),
                    child: Text(pt(context, 'Skip')),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

Future<void> openTaste(
  BuildContext context,
  WaveController c,
  WaveParity parity,
) async {
  await Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => TastePage(controller: c, parity: parity),
    ),
  );
  await parity.load();
}

class TastePage extends StatefulWidget {
  final WaveController controller;
  final WaveParity parity;
  const TastePage({super.key, required this.controller, required this.parity});
  @override
  State<TastePage> createState() => _TastePageState();
}

class _TastePageState extends State<TastePage> {
  final search = TextEditingController();
  final selected = <String, Json>{};
  List<Json> artists = [];
  List<String> genres = [];
  bool loading = true, saving = false, failed = false, automatic = true;
  Timer? timer;
  int request = 0;
  @override
  void initState() {
    super.initState();
    for (final a in objects(widget.parity.preference['artists'])) {
      selected[a['id'].toString()] = a;
    }
    automatic = widget.parity.preference['automatic'] != false;
    unawaited(load());
  }

  Future<void> load() async {
    final id = ++request;
    setState(() {
      loading = true;
      failed = false;
    });
    try {
      final result = await widget.controller.api.call(
        '/api/artists',
        query: {'q': search.text.trim(), 'source': 'all'},
      );
      if (mounted && id == request) {
        setState(() {
          artists = objects(result['artists']);
          genres = List<String>.from(result['genres'] ?? []);
          loading = false;
        });
      }
    } catch (_) {
      if (mounted && id == request) {
        setState(() {
          failed = true;
          loading = false;
        });
      }
    }
  }

  Future<void> save({bool skip = false}) async {
    setState(() => saving = true);
    try {
      await widget.parity.saveTaste({
        'artists': skip ? <Json>[] : selected.values.toList(),
        'automatic': automatic,
        'onboardingStep': 3,
        'onboardingCompleted': true,
      });
      if (mounted) Navigator.pop(context);
    } catch (e) {
      widget.controller.tell(e.toString());
    }
    if (mounted) setState(() => saving = false);
  }

  void choose(Json a) {
    setState(() {
      final id = a['id'].toString();
      selected.containsKey(id) ? selected.remove(id) : selected[id] = a;
    });
    unawaited(
      widget.parity
          .saveTaste({'artists': selected.values.toList(), 'onboardingStep': 2})
          .catchError((Object e) {
            widget.controller.tell(e.toString());
          }),
    );
  }

  @override
  void dispose() {
    request++;
    timer?.cancel();
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      backgroundColor: waveVisuals(context).background,
      title: Text(pt(context, 'Taste')),
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            PageHeading(
              pt(context, 'Welcome'),
              pt(context, 'Taste subtitle'),
              eyebrow: 'GLUKWAVE',
            ),
            Text(
              '02 / 03 · ${selected.length} ${pt(context, 'Artists')}',
              style: TextStyle(
                color: waveVisuals(context).accent,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              key: const Key('taste-search'),
              controller: search,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: pt(context, 'Search artists'),
              ),
              onChanged: (_) {
                timer?.cancel();
                timer = Timer(const Duration(milliseconds: 350), load);
              },
            ),
            const SizedBox(height: 18),
            if (selected.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final a in selected.values)
                    InputChip(
                      label: Text(a['name'].toString()),
                      onDeleted: () => choose(a),
                    ),
                ],
              ),
            const SizedBox(height: 18),
            if (loading)
              const WaveLoadingList()
            else if (failed)
              EmptyState(
                pt(context, 'Unavailable'),
                pt(context, 'Unavailable detail'),
                action: OutlinedButton(
                  onPressed: load,
                  child: Text(pt(context, 'Retry')),
                ),
              )
            else if (artists.isEmpty)
              EmptyState(
                pt(context, 'No artists'),
                pt(context, 'No artists detail'),
              )
            else
              ArtistGrid(
                controller: widget.controller,
                artists: artists,
                selected: selected.keys.toSet(),
                onTap: choose,
              ),
            if (genres.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final genre in genres) Chip(label: Text(genre)),
                  ],
                ),
              ),
            const SizedBox(height: 24),
            Surface(
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(pt(context, 'Automatic taste')),
                value: automatic,
                onChanged: (v) => setState(() => automatic = v),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton(
                  key: const Key('taste-save'),
                  onPressed: saving ? null : save,
                  child: Text(pt(context, 'Save')),
                ),
                TextButton(
                  onPressed: saving ? null : () => save(skip: true),
                  child: Text(pt(context, 'Skip')),
                ),
                TextButton(
                  onPressed: saving
                      ? null
                      : () => parityRun(widget.controller, () async {
                          await widget.controller.api.call(
                            '/api/taste/learned',
                            method: 'DELETE',
                          );
                          if (context.mounted) {
                            widget.controller.tell(pt(context, 'Saved'));
                          }
                        }),
                  child: Text(pt(context, 'Clear learned')),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class ArtistGrid extends StatelessWidget {
  final WaveController controller;
  final List<Json> artists;
  final Set<String> selected;
  final ValueChanged<Json> onTap;
  const ArtistGrid({
    super.key,
    required this.controller,
    required this.artists,
    required this.onTap,
    this.selected = const {},
  });
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final count = box.maxWidth < 500
          ? 2
          : box.maxWidth < 800
          ? 4
          : 5;
      final width = (box.maxWidth - (count - 1) * 16) / count;
      return Wrap(
        spacing: 16,
        runSpacing: 22,
        children: [
          for (final artist in artists)
            SizedBox(
              width: width,
              child: Semantics(
                selected: selected.contains(artist['id']),
                button: true,
                child: InkWell(
                  key: ValueKey('artist-${artist['id']}'),
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => onTap(artist),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      children: [
                        Stack(
                          alignment: Alignment.bottomRight,
                          children: [
                            ClipOval(
                              child: Artwork(
                                controller: controller,
                                url: artist['artwork']?.toString(),
                                size: (width - 16).clamp(48, 140),
                                radius: 0,
                                icon: Icons.person_outline,
                              ),
                            ),
                            if (selected.contains(artist['id']))
                              CircleAvatar(
                                radius: 15,
                                backgroundColor: waveVisuals(context).ink,
                                child: Icon(
                                  Icons.check,
                                  size: 18,
                                  color: waveVisuals(context).background,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          artist['name']?.toString() ?? '',
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          paritySourceName(context, artist['source']),
                          style: TextStyle(
                            fontSize: 10,
                            color: waveVisuals(context).muted,
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

class ArtistBrowse extends StatelessWidget {
  final WaveController controller;
  final String query;
  const ArtistBrowse({super.key, required this.controller, this.query = ''});
  @override
  Widget build(BuildContext context) => ApiPanel(
    controller: controller,
    path: '/api/artists?q=${Uri.encodeQueryComponent(query)}',
    builder: (data, reload) {
      final artists = objects(data['artists']),
          genres = List<String>.from(data['genres'] ?? []);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeading(pt(context, 'Artists'), pt(context, 'No artists detail')),
          if (genres.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final genre in genres)
                    ActionChip(
                      label: Text(genre),
                      onPressed: () => openGenre(context, controller, genre),
                    ),
                ],
              ),
            ),
          if (artists.isEmpty)
            EmptyState(
              pt(context, 'No artists'),
              pt(context, 'No artists detail'),
            )
          else
            ArtistGrid(
              controller: controller,
              artists: artists,
              onTap: (artist) => openArtist(context, controller, artist),
            ),
        ],
      );
    },
  );
}

Future<void> openGenre(
  BuildContext context,
  WaveController c,
  String genre,
) => Navigator.push(
  context,
  MaterialPageRoute<void>(
    builder: (context) => Scaffold(
      appBar: AppBar(
        backgroundColor: waveVisuals(context).background,
        title: Text(genre),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          ApiPanel(
            controller: c,
            path: '/api/search?q=${Uri.encodeQueryComponent(genre)}&source=all',
            builder: (data, _) {
              final tracks = objects(
                    data['tracks'],
                  ).map(WaveTrack.new).toList(),
                  artists = objects(data['artists']);
              return Column(
                children: [
                  if (artists.isNotEmpty)
                    ArtistGrid(
                      controller: c,
                      artists: artists,
                      onTap: (a) => openArtist(context, c, a),
                    ),
                  const SizedBox(height: 24),
                  for (final track in tracks)
                    TrackRow(
                      controller: c,
                      track: track,
                      queue: tracks,
                      onMore: () => parityTrackActions(context, c, track),
                    ),
                  if (artists.isEmpty && tracks.isEmpty)
                    EmptyState(
                      pt(context, 'No artists'),
                      pt(context, 'No artists detail'),
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

Future<void> openArtist(BuildContext context, WaveController c, Json artist) =>
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ArtistDetail(controller: c, artist: artist),
      ),
    );

class ArtistDetail extends StatefulWidget {
  final WaveController controller;
  final Json artist;
  const ArtistDetail({
    super.key,
    required this.controller,
    required this.artist,
  });
  @override
  State<ArtistDetail> createState() => _ArtistDetailState();
}

class _ArtistDetailState extends State<ArtistDetail> {
  List<WaveTrack> tracks = [];
  bool loading = true, failed = false;
  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      failed = false;
    });
    try {
      Json result;
      try {
        result = await widget.controller.api.call(
          '/api/artists/${Uri.encodeComponent(widget.artist['id'].toString())}',
        );
      } catch (_) {
        result = {};
      }
      var found = objects(result['tracks']).map(WaveTrack.new).toList();
      if (found.isEmpty) {
        await widget.controller.searchArtist(widget.artist);
        found = widget.controller.results.toList();
      }
      if (mounted) {
        setState(() {
          tracks = found;
          loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      backgroundColor: waveVisuals(context).background,
      title: Text(pt(context, 'Artists')),
    ),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            ClipOval(
              child: Artwork(
                controller: widget.controller,
                url: widget.artist['artwork']?.toString(),
                size: 100,
                radius: 0,
                icon: Icons.person_outline,
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.artist['name']?.toString() ?? '',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    paritySourceName(context, widget.artist['source']),
                    style: TextStyle(color: waveVisuals(context).muted),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        if (loading)
          const WaveLoadingList()
        else if (failed)
          EmptyState(
            pt(context, 'Unavailable'),
            pt(context, 'Unavailable detail'),
            action: OutlinedButton(
              onPressed: load,
              child: Text(pt(context, 'Retry')),
            ),
          )
        else if (tracks.isEmpty)
          EmptyState(
            pt(context, 'No artists'),
            pt(context, 'No artists detail'),
          )
        else
          for (final track in tracks)
            TrackRow(
              controller: widget.controller,
              track: track,
              queue: tracks,
              onMore: () =>
                  parityTrackActions(context, widget.controller, track),
            ),
      ],
    ),
  );
}

Future<void> openPublicProfile(
  BuildContext context,
  WaveController c,
  Json user,
) => Navigator.push(
  context,
  MaterialPageRoute<void>(
    builder: (context) => Scaffold(
      appBar: AppBar(
        backgroundColor: waveVisuals(context).background,
        title: Text(
          user['displayName']?.toString() ?? user['username']?.toString() ?? '',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          ApiPanel(
            controller: c,
            path: '/api/profile/${Uri.encodeComponent(user['id'].toString())}',
            builder: (data, _) {
              final profile = object(data['user']),
                  stats = object(data['stats']);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if ((profile['bannerUrl']?.toString() ?? '').isNotEmpty)
                    AspectRatio(
                      aspectRatio: 3.5,
                      child: FittedBox(
                        fit: BoxFit.cover,
                        clipBehavior: Clip.hardEdge,
                        child: Artwork(
                          controller: c,
                          url: profile['bannerUrl']?.toString(),
                          size: 600,
                        ),
                      ),
                    ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Artwork(
                        controller: c,
                        url: profile['avatarUrl']?.toString(),
                        size: 70,
                        radius: 35,
                        icon: Icons.person_outline,
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 10,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  profile['displayName']?.toString() ?? '',
                                  style: const TextStyle(
                                    fontSize: 25,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Chip(
                                  label: Text(
                                    (profile['role'] == 'admin'
                                            ? 'admin'
                                            : profile['plan'] ?? 'free')
                                        .toString()
                                        .toUpperCase(),
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              '@${profile['username'] ?? ''}',
                              style: TextStyle(
                                color: waveVisuals(context).muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if ((profile['bio']?.toString() ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      child: Text(
                        profile['bio'].toString(),
                        style: const TextStyle(height: 1.7),
                      ),
                    ),
                  if (data['stats'] is Map)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Surface(
                        child: Wrap(
                          spacing: 28,
                          runSpacing: 18,
                          children: [
                            for (final entry in {
                              'Plays': number(stats['plays']).round(),
                              'Minutes':
                                  (number(stats['listeningSeconds']) / 60)
                                      .floor(),
                              'Artists': number(stats['artistCount']).round(),
                            }.entries)
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    localizedNumber(
                                      entry.value,
                                      context: context,
                                    ),
                                    style: const TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  Text(
                                    pt(context, entry.key),
                                    style: TextStyle(
                                      color: waveVisuals(context).muted,
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                  for (final playlist in objects(data['playlists']))
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      leading: PlaylistArtwork(
                        controller: c,
                        playlist: playlist,
                        size: 52,
                      ),
                      title: Text(playlist['name']?.toString() ?? ''),
                      subtitle: Text(
                        playlist['description']?.toString() ?? '',
                        maxLines: 2,
                      ),
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

class FriendsPage extends StatefulWidget {
  final WaveController controller;
  final VoidCallback onRoom;
  final WaveParity? parity;
  const FriendsPage({
    super.key,
    required this.controller,
    required this.onRoom,
    this.parity,
  });
  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage> {
  final search = TextEditingController();
  List<Json> results = [];
  bool searching = false;
  String? searchError;
  Timer? timer;
  int generation = 0;
  Future<void> find() async {
    final id = ++generation;
    if (search.text.trim().length < 2) {
      setState(() {
        results = [];
        searching = false;
      });
      return;
    }
    setState(() {
      searching = true;
      searchError = null;
    });
    try {
      final data = await widget.controller.api.call(
        '/api/users/search',
        query: {'q': search.text.trim()},
      );
      if (mounted && id == generation) {
        setState(() {
          results = objects(data['users']);
          searching = false;
        });
      }
    } catch (_) {
      if (mounted && id == generation) {
        setState(() {
          searchError = pt(context, 'Unavailable');
          searching = false;
        });
      }
    }
  }

  Future<void> jam([String? id]) async {
    final c = widget.controller;
    final data = await c.api.call(
      id == null ? '/api/jams' : '/api/jams/${Uri.encodeComponent(id)}/join',
      method: 'POST',
      data: {},
    );
    await c.enterRoom(object(data['room']));
    widget.onRoom();
  }

  @override
  void dispose() {
    generation++;
    timer?.cancel();
    search.dispose();
    super.dispose();
  }

  Widget person(Json user, {String? subtitle, Widget? trailing}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        InkWell(
          onTap: () => openPublicProfile(context, widget.controller, user),
          child: Artwork(
            controller: widget.controller,
            url: user['avatarUrl']?.toString(),
            size: 48,
            radius: 24,
            icon: Icons.person_outline,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                user['displayName']?.toString() ??
                    user['username']?.toString() ??
                    '',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle ?? '@${user['username'] ?? ''}',
                style: TextStyle(
                  fontSize: 12,
                  color: waveVisuals(context).muted,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        if (trailing != null) trailing,
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      PageHeading(
        pt(context, 'Friends'),
        pt(context, 'Friends subtitle'),
        eyebrow: 'GLUKWAVE',
      ),
      Surface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.spatial_audio_rounded,
                  color: waveVisuals(context).accent,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    pt(context, 'Start jam'),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              pt(context, 'Jam detail'),
              style: TextStyle(color: waveVisuals(context).muted, height: 1.6),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('jam-create'),
              onPressed: widget.controller.online
                  ? () => parityRun(widget.controller, jam)
                  : null,
              icon: const Icon(Icons.waves),
              label: Text(pt(context, 'Start jam')),
            ),
          ],
        ),
      ),
      const SizedBox(height: 28),
      TextField(
        key: const Key('friends-search'),
        controller: search,
        decoration: InputDecoration(
          labelText: pt(context, 'Find friends'),
          hintText: pt(context, 'Search people'),
          prefixIcon: const Icon(Icons.search),
        ),
        onChanged: (_) {
          timer?.cancel();
          timer = Timer(const Duration(milliseconds: 350), find);
        },
      ),
      if (searching) const LinearProgressIndicator(),
      if (searchError != null)
        Padding(padding: const EdgeInsets.all(12), child: Text(searchError!)),
      for (final user in results)
        person(
          user,
          trailing: IconButton(
            tooltip: pt(
              context,
              user['relationship'] == 'none' ? 'Add friend' : 'Pending',
            ),
            onPressed: user['relationship'] == 'none'
                ? () => parityRun(widget.controller, () async {
                    await widget.controller.api.call(
                      '/api/friends/requests',
                      method: 'POST',
                      data: {'userId': user['id']},
                    );
                    await find();
                  })
                : null,
            icon: Icon(
              user['relationship'] == 'friend'
                  ? Icons.check
                  : user['relationship'] == 'pending'
                  ? Icons.schedule
                  : Icons.person_add_outlined,
            ),
          ),
        ),
      const SizedBox(height: 28),
      ApiPanel(
        controller: widget.controller,
        path: '/api/friends',
        refresh: widget.parity,
        loadData: widget.parity == null
            ? null
            : () async {
                if (widget.parity!.friends.isEmpty) {
                  await widget.parity!.refreshFriends();
                }
                return widget.parity!.friends;
              },
        builder: (data, reloadPanel) {
          Future<void> reload() async {
            if (widget.parity != null) await widget.parity!.refreshFriends();
            await reloadPanel();
          }

          final friends = objects(data['friends']),
              incoming = objects(data['incoming']),
              outgoing = objects(data['outgoing']);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (incoming.isNotEmpty)
                Text(
                  pt(context, 'Requests'),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              for (final invite in incoming)
                person(
                  object(invite['from']),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final accept in [true, false])
                        IconButton(
                          tooltip: pt(context, accept ? 'Accept' : 'Decline'),
                          icon: Icon(
                            accept ? Icons.check_rounded : Icons.close_rounded,
                          ),
                          onPressed: () =>
                              parityRun(widget.controller, () async {
                                await widget.controller.api.call(
                                  '/api/friends/requests/${invite['id']}',
                                  method: 'PUT',
                                  data: {'accept': accept},
                                );
                                await reload();
                              }),
                        ),
                    ],
                  ),
                ),
              for (final invite in outgoing)
                person(object(invite['to']), subtitle: pt(context, 'Pending')),
              if (friends.isEmpty)
                EmptyState(
                  pt(context, 'No friends'),
                  pt(context, 'No friends detail'),
                  icon: Icons.people_outline,
                ),
              for (final friend in friends) ...[
                person(
                  object(friend['user']),
                  subtitle:
                      object(
                        object(friend['activity'])['track'],
                      )['title']?.toString() ??
                      pt(
                        context,
                        friend['online'] == true ? 'Online' : 'Offline',
                      ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (_) => parityRun(widget.controller, () async {
                      await widget.controller.api.call(
                        '/api/friends/${object(friend['user'])['id']}',
                        method: 'DELETE',
                      );
                      await reload();
                    }),
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'remove',
                        child: Text(pt(context, 'Remove friend')),
                      ),
                    ],
                  ),
                ),
                if (object(friend['activity'])['jamId'] != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 62, bottom: 8),
                    child: OutlinedButton.icon(
                      onPressed: () => parityRun(
                        widget.controller,
                        () =>
                            jam(object(friend['activity'])['jamId'].toString()),
                      ),
                      icon: const Icon(Icons.waves),
                      label: Text(pt(context, 'Join jam')),
                    ),
                  ),
                Divider(color: waveVisuals(context).line),
              ],
              TextButton.icon(
                onPressed: reload,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(pt(context, 'Retry')),
              ),
            ],
          );
        },
      ),
    ],
  );
}

class PrivacyPanel extends StatelessWidget {
  final WaveController controller;
  const PrivacyPanel({super.key, required this.controller});
  @override
  Widget build(BuildContext context) => ApiPanel(
    controller: controller,
    path: '/api/account/privacy',
    builder: (data, reload) => Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            pt(context, 'Privacy'),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 21),
          ),
          const SizedBox(height: 14),
          for (final entry in {
            'showActivity': 'Show activity',
            'profileStats': 'Profile stats',
            'allowFriendRequests': 'Allow requests',
          }.entries)
            SwitchListTile(
              key: Key('privacy-${entry.key}'),
              contentPadding: EdgeInsets.zero,
              title: Text(pt(context, entry.value)),
              value: object(data['privacy'])[entry.key] == true,
              onChanged: (value) => parityRun(controller, () async {
                await controller.api.call(
                  '/api/account/privacy',
                  method: 'PATCH',
                  data: {entry.key: value},
                );
                await reload();
              }),
            ),
        ],
      ),
    ),
  );
}

class ListeningStats extends StatelessWidget {
  final WaveController controller;
  const ListeningStats({super.key, required this.controller});
  @override
  Widget build(BuildContext context) => ApiPanel(
    controller: controller,
    path: '/api/account/stats',
    builder: (data, reload) {
      if (data['stats'] is! Map) {
        return EmptyState(
          pt(context, 'Unavailable'),
          pt(context, 'Unavailable detail'),
        );
      }
      final stats = object(data['stats']);
      return Surface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              pt(context, 'Stats'),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 22),
            ),
            const SizedBox(height: 24),
            LayoutBuilder(
              builder: (context, box) => Wrap(
                spacing: 16,
                runSpacing: 22,
                children: [
                  for (final entry in {
                    'Plays': number(stats['plays']).round(),
                    'Minutes': (number(stats['listeningSeconds']) / 60).floor(),
                    'Tracks': number(stats['trackCount']).round(),
                    'Artists': number(stats['artistCount']).round(),
                  }.entries)
                    SizedBox(
                      width:
                          (box.maxWidth - 16) / (box.maxWidth < 500 ? 2 : 4) -
                          8,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            localizedNumber(entry.value, context: context),
                            style: const TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -1,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            pt(context, entry.key),
                            style: TextStyle(
                              color: waveVisuals(context).muted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            if (number(stats['plays']) == 0)
              Padding(
                padding: const EdgeInsets.only(top: 24),
                child: Text(
                  pt(context, 'No stats'),
                  style: TextStyle(color: waveVisuals(context).muted),
                ),
              ),
            if (objects(stats['topArtists']).isNotEmpty) ...[
              const Divider(height: 40),
              Text(
                pt(context, 'Top artists'),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              for (final artist in objects(stats['topArtists']).take(5))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      Expanded(child: Text(artist['name'].toString())),
                      Text(
                        '${localizedNumber(number(artist['plays']).round(), context: context)} · ${pt(context, 'Plays')}',
                        style: TextStyle(
                          color: waveVisuals(context).muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      );
    },
  );
}

class AccountActions extends StatelessWidget {
  final WaveController controller;
  const AccountActions({super.key, required this.controller});
  @override
  Widget build(BuildContext context) => Surface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          pt(context, 'Account'),
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 21),
        ),
        const SizedBox(height: 16),
        for (final kind in ['password', 'email', 'delete'])
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              kind == 'password'
                  ? Icons.password_rounded
                  : kind == 'email'
                  ? Icons.alternate_email_rounded
                  : Icons.delete_outline,
            ),
            title: Text(
              pt(
                context,
                kind == 'password'
                    ? 'Change password'
                    : kind == 'email'
                    ? 'Change email'
                    : 'Delete account',
              ),
            ),
            trailing: const Icon(Icons.arrow_forward_rounded, size: 18),
            onTap: () => showWaveDialog<void>(
              context: context,
              builder: (_) => AccountForm(controller: controller, kind: kind),
            ),
          ),
      ],
    ),
  );
}

class AccountForm extends StatefulWidget {
  final WaveController controller;
  final String kind;
  const AccountForm({super.key, required this.controller, required this.kind});
  @override
  State<AccountForm> createState() => _AccountFormState();
}

class _AccountFormState extends State<AccountForm> {
  final password = TextEditingController(), value = TextEditingController();
  final form = GlobalKey<FormState>();
  bool busy = false;
  String? error;
  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    final c = widget.controller, kind = widget.kind;
    try {
      await c.api.call(
        kind == 'delete' ? '/api/account' : '/api/account/$kind',
        method: kind == 'delete' ? 'DELETE' : 'POST',
        data: {
          'currentPassword': password.text,
          kind == 'delete'
              ? 'confirmation'
              : kind == 'email'
              ? 'email'
              : 'password': kind == 'password'
              ? value.text
              : value.text.trim(),
        },
      );
      if (kind == 'delete') await c.logout(remote: false);
      if (!mounted) return;
      c.tell(pt(context, kind == 'email' ? 'Email sent' : 'Saved'));
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
          busy = false;
        });
      }
    }
  }

  @override
  void dispose() {
    password.dispose();
    value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final kind = widget.kind;
    return AlertDialog(
      title: Text(
        pt(
          context,
          kind == 'delete'
              ? 'Delete account'
              : kind == 'email'
              ? 'Change email'
              : 'Change password',
        ),
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (kind == 'delete') ...[
                  Text(
                    pt(context, 'Delete warning'),
                    style: TextStyle(
                      color: waveVisuals(context).muted,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
                TextFormField(
                  key: const Key('account-current-password'),
                  controller: password,
                  obscureText: true,
                  autofillHints: const [AutofillHints.password],
                  decoration: InputDecoration(
                    labelText: pt(context, 'Current password'),
                  ),
                  validator: (v) => v == null || v.isEmpty
                      ? pt(context, 'Current password')
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('account-new-value'),
                  controller: value,
                  obscureText: kind == 'password',
                  keyboardType: kind == 'email'
                      ? TextInputType.emailAddress
                      : TextInputType.text,
                  decoration: InputDecoration(
                    labelText: pt(
                      context,
                      kind == 'delete'
                          ? 'Username'
                          : kind == 'email'
                          ? 'New email'
                          : 'New password',
                    ),
                  ),
                  validator: (v) => kind == 'delete'
                      ? v == widget.controller.user?.username
                            ? null
                            : pt(context, 'Username')
                      : kind == 'password'
                      ? (v?.length ?? 0) >= 8
                            ? null
                            : pt(context, 'New password')
                      : RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(v ?? '')
                      ? null
                      : pt(context, 'New email'),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: Text(pt(context, 'Cancel')),
        ),
        FilledButton(
          key: const Key('account-submit'),
          onPressed: busy ? null : submit,
          child: Text(
            pt(context, kind == 'delete' ? 'Delete account' : 'Save'),
          ),
        ),
      ],
    );
  }
}

class PlaylistArtwork extends StatelessWidget {
  final WaveController controller;
  final Json playlist;
  final double size;
  const PlaylistArtwork({
    super.key,
    required this.controller,
    required this.playlist,
    required this.size,
  });
  @override
  Widget build(BuildContext context) {
    final artwork = playlist['artwork']?.toString() ?? '';
    final covers = List<String>.from(playlist['coverArtworks'] ?? []);
    if (covers.isEmpty) {
      for (final id in List<String>.from(playlist['trackIds'] ?? [])) {
        final cover = controller.track(id)?.artwork;
        if (cover != null && cover.isNotEmpty && !covers.contains(cover)) {
          covers.add(cover);
        }
        if (covers.length == 4) break;
      }
    }
    if (artwork.isNotEmpty || covers.isEmpty) {
      return Artwork(
        controller: controller,
        url: artwork,
        size: size,
        radius: 17,
        icon: Icons.queue_music_rounded,
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(waveRadius(context, 17)),
      child: SizedBox(
        width: size,
        height: size,
        child: covers.length == 1
            ? Artwork(
                controller: controller,
                url: covers.first,
                size: size,
                radius: 0,
              )
            : Stack(
                children: [
                  for (var i = 0; i < 4; i++)
                    Positioned(
                      left: i % 2 * size / 2,
                      top: i ~/ 2 * size / 2,
                      child: Artwork(
                        controller: controller,
                        url: covers[i % covers.length],
                        size: size / 2,
                        radius: 0,
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class PlaylistPublishing extends StatelessWidget {
  final WaveController controller;
  final Json playlist;
  final ValueChanged<Json> onChanged;
  const PlaylistPublishing({
    super.key,
    required this.controller,
    required this.playlist,
    required this.onChanged,
  });
  Future<void> update(Json changes) async {
    final data = await controller.api.call(
      '/api/playlists/${playlist['id']}',
      method: 'PATCH',
      data: changes,
    );
    final saved = object(data['playlist']).isEmpty
        ? object(
            (await controller.api.call(
              '/api/playlists/${playlist['id']}',
            ))['playlist'],
          )
        : object(data['playlist']);
    if (saved.isEmpty) {
      throw StateError('Playlist update could not be verified');
    }
    onChanged(saved);
    await controller.refresh();
  }

  @override
  Widget build(BuildContext context) => Surface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          key: const Key('playlist-public'),
          contentPadding: EdgeInsets.zero,
          title: Text(pt(context, 'Public playlist')),
          subtitle: Text(
            pt(context, 'Public detail'),
            style: TextStyle(
              color: waveVisuals(context).muted,
              fontSize: 12,
              height: 1.5,
            ),
          ),
          value: playlist['public'] == true,
          onChanged: (v) => parityRun(controller, () => update({'public': v})),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            OutlinedButton.icon(
              onPressed: () => parityRun(controller, () async {
                final file = await FilePicker.pickFiles(
                  type: FileType.custom,
                  allowedExtensions: ['png', 'jpg', 'jpeg', 'webp', 'gif'],
                );
                final path = file?.files.first.path;
                if (path == null) return;
                final data = await controller.api.upload(
                  '/api/playlists/${playlist['id']}/cover',
                  path,
                );
                onChanged(object(data['playlist']));
                await controller.refresh();
              }),
              icon: const Icon(Icons.image_outlined),
              label: Text(pt(context, 'Change cover')),
            ),
            if ((playlist['artwork']?.toString() ?? '').isNotEmpty)
              TextButton(
                onPressed: () => parityRun(controller, () async {
                  final data = await controller.api.call(
                    '/api/playlists/${playlist['id']}/cover',
                    method: 'DELETE',
                  );
                  onChanged(object(data['playlist']));
                  await controller.refresh();
                }),
                child: Text(pt(context, 'Restore collage')),
              ),
          ],
        ),
      ],
    ),
  );
}

class PublicPlaylists extends StatelessWidget {
  final WaveController controller;
  const PublicPlaylists({super.key, required this.controller});
  @override
  Widget build(BuildContext context) => ApiPanel(
    controller: controller,
    path: '/api/playlists/discover',
    builder: (data, reload) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeading(
          pt(context, 'Discover playlists'),
          pt(context, 'Friends subtitle'),
        ),
        for (final playlist in objects(data['playlists']))
          ListTile(
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
            leading: PlaylistArtwork(
              controller: controller,
              playlist: playlist,
              size: 52,
            ),
            title: Text(
              playlist['name']?.toString() ?? '',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: Text(
              playlist['description']?.toString() ?? '',
              maxLines: 2,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (context) => Scaffold(
                  appBar: AppBar(
                    title: Text(playlist['name']?.toString() ?? ''),
                  ),
                  body: ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      ApiPanel(
                        controller: controller,
                        path: '/api/playlists/${playlist['id']}',
                        builder: (detail, _) {
                          final tracks = objects(
                            detail['tracks'],
                          ).map(WaveTrack.new).toList();
                          return Column(
                            children: [
                              PlaylistArtwork(
                                controller: controller,
                                playlist: object(detail['playlist']),
                                size: 200,
                              ),
                              const SizedBox(height: 28),
                              for (final track in tracks)
                                TrackRow(
                                  controller: controller,
                                  track: track,
                                  queue: tracks,
                                  onMore: () => parityTrackActions(
                                    context,
                                    controller,
                                    track,
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        if (objects(data['playlists']).isEmpty)
          EmptyState(
            pt(context, 'Discover playlists'),
            pt(context, 'Public detail'),
            icon: Icons.queue_music_rounded,
          ),
      ],
    ),
  );
}

class TypographyPanel extends StatelessWidget {
  final WaveController controller;
  const TypographyPanel({super.key, required this.controller});
  @override
  Widget build(BuildContext context) => Surface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (controller.user?.plan == 'free') ...[
          Text(
            pt(context, 'Advanced'),
            style: TextStyle(color: waveVisuals(context).muted, height: 1.6),
          ),
          const SizedBox(height: 16),
        ],
        Text(
          pt(context, 'Font'),
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final family in ['manrope', 'nunito', 'system'])
              ChoiceChip(
                label: Text(
                  family == 'system'
                      ? pt(context, 'System font')
                      : family == 'manrope'
                      ? 'Manrope'
                      : 'Nunito',
                ),
                selected: controller.customization.fontFamily == family,
                onSelected: controller.user?.plan == 'free'
                    ? null
                    : (_) => parityRun(
                        controller,
                        () => controller.customize({'fontFamily': family}),
                      ),
              ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(child: Text(pt(context, 'Font size'))),
            Text('${(controller.customization.fontScale * 100).round()}%'),
          ],
        ),
        Slider(
          key: const Key('font-scale'),
          min: .85,
          max: 1.25,
          divisions: 8,
          value: controller.customization.fontScale,
          onChanged: (v) => parityRun(
            controller,
            () => controller.customize({'fontScale': v}),
          ),
        ),
      ],
    ),
  );
}

class AdminParity extends StatelessWidget {
  final WaveController controller;
  const AdminParity({super.key, required this.controller});
  Future<void> remove(
    BuildContext context,
    Json user,
    Future<void> Function() reload,
  ) async {
    final typed = TextEditingController();
    final accepted = await showWaveDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(pt(context, 'Delete account')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(user['username']?.toString() ?? ''),
            const SizedBox(height: 12),
            TextField(
              controller: typed,
              decoration: InputDecoration(labelText: pt(context, 'Username')),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(pt(context, 'Cancel')),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, typed.text == user['username']),
            child: Text(pt(context, 'Delete account')),
          ),
        ],
      ),
    );
    typed.dispose();
    if (accepted == true) {
      await controller.api.call(
        '/api/admin/users/${user['id']}',
        method: 'DELETE',
        data: {'confirmation': user['username']},
      );
      await reload();
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ApiPanel(
        controller: controller,
        path: '/api/admin/registration',
        builder: (data, reload) => Column(
          children: [
            Surface(
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(pt(context, 'Registration')),
                value: object(data['registration'])['enabled'] == true,
                onChanged: (v) => parityRun(controller, () async {
                  await controller.api.call(
                    '/api/admin/registration',
                    method: 'PATCH',
                    data: {'enabled': v},
                  );
                  await reload();
                }),
              ),
            ),
            if (data['owner'] == true) ...[
              const SizedBox(height: 24),
              ReleaseForm(controller: controller),
            ],
          ],
        ),
      ),
      const SizedBox(height: 24),
      ApiPanel(
        controller: controller,
        path: '/api/admin/overview',
        builder: (data, reload) => Column(
          children: [
            for (final user in objects(data['users']))
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Surface(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user['displayName']?.toString() ??
                            user['username']?.toString() ??
                            '',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        user['email']?.toString() ?? '',
                        style: TextStyle(color: waveVisuals(context).muted),
                      ),
                      const SizedBox(height: 16),
                      LayoutBuilder(
                        builder: (context, box) => Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            for (final entry in {
                              'plan': ['free', 'beta', 'unbound'],
                              'role': ['user', 'admin'],
                            }.entries)
                              SizedBox(
                                width: box.maxWidth < 460
                                    ? box.maxWidth
                                    : (box.maxWidth - 12) / 2,
                                child: DropdownButtonFormField<String>(
                                  key: ValueKey(
                                    'admin-${entry.key}-${user['id']}-${user[entry.key]}',
                                  ),
                                  initialValue:
                                      entry.value.contains(user[entry.key])
                                      ? user[entry.key] as String
                                      : entry.value.first,
                                  decoration: InputDecoration(
                                    labelText: pt(
                                      context,
                                      entry.key == 'plan' ? 'Plan' : 'Role',
                                    ),
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                  dropdownColor: waveVisuals(context).surface,
                                  items: [
                                    for (final v in entry.value)
                                      DropdownMenuItem(
                                        value: v,
                                        child: Text(
                                          entry.key == 'role'
                                              ? pt(
                                                  context,
                                                  v == 'admin'
                                                      ? 'Administrator'
                                                      : 'User',
                                                )
                                              : switch (v) {
                                                  'beta' => 'Beta',
                                                  'unbound' => 'Unbound',
                                                  _ => 'Free',
                                                },
                                        ),
                                      ),
                                  ],
                                  onChanged: (v) =>
                                      parityRun(controller, () async {
                                        await controller.api.call(
                                          '/api/admin/users/${user['id']}',
                                          method: 'PATCH',
                                          data: {entry.key: v},
                                        );
                                        await reload();
                                      }),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: user['id'] == controller.user?.id
                                ? null
                                : () => parityRun(controller, () async {
                                    await controller.api.call(
                                      '/api/admin/users/${user['id']}',
                                      method: 'PATCH',
                                      data: {
                                        'blocked': user['blocked'] != true,
                                      },
                                    );
                                    await reload();
                                  }),
                            icon: const Icon(Icons.block_outlined),
                            label: Text(
                              pt(
                                context,
                                user['blocked'] == true ? 'Unblock' : 'Block',
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: user['id'] == controller.user?.id
                                ? null
                                : () => parityRun(
                                    controller,
                                    () => remove(context, user, reload),
                                  ),
                            child: Text(pt(context, 'Delete account')),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    ],
  );
}

class ReleaseForm extends StatefulWidget {
  final WaveController controller;
  const ReleaseForm({super.key, required this.controller});
  @override
  State<ReleaseForm> createState() => _ReleaseFormState();
}

class _ReleaseFormState extends State<ReleaseForm> {
  final version = TextEditingController(), signature = TextEditingController();
  String platform = 'android', channel = 'stable';
  String? path;
  bool busy = false;
  @override
  void dispose() {
    version.dispose();
    signature.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Surface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          pt(context, 'Release'),
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        Text(
          pt(context, 'Release warning'),
          style: TextStyle(
            color: waveVisuals(context).muted,
            fontSize: 12,
            height: 1.7,
          ),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 10,
          children: [
            for (final v in ['android', 'windows'])
              ChoiceChip(
                label: Text(v == 'android' ? 'Android' : 'Windows'),
                selected: platform == v,
                onSelected: (_) => setState(() {
                  platform = v;
                  path = null;
                }),
              ),
          ],
        ),
        const SizedBox(height: 14),
        TextField(
          controller: version,
          decoration: InputDecoration(labelText: pt(context, 'Version')),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: signature,
          decoration: InputDecoration(labelText: pt(context, 'Signature')),
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(
          initialValue: channel,
          decoration: const InputDecoration(labelText: 'Channel'),
          items: [
            for (final v in ['stable', 'beta'])
              DropdownMenuItem(value: v, child: Text(v)),
          ],
          onChanged: (v) => setState(() => channel = v ?? 'stable'),
        ),
        const SizedBox(height: 16),
        if (path != null) Text(path!.split(RegExp(r'[/\\]')).last, maxLines: 2),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            OutlinedButton.icon(
              onPressed: busy
                  ? null
                  : () async {
                      final result = await FilePicker.pickFiles(
                        type: FileType.custom,
                        allowedExtensions: platform == 'android'
                            ? ['apk']
                            : ['exe'],
                      );
                      if (mounted) {
                        setState(() => path = result?.files.first.path);
                      }
                    },
              icon: const Icon(Icons.attach_file),
              label: Text(pt(context, 'Choose file')),
            ),
            FilledButton(
              onPressed: busy || path == null
                  ? null
                  : () => parityRun(widget.controller, () async {
                      setState(() => busy = true);
                      try {
                        await widget.controller.api.upload(
                          '/api/admin/releases/$platform',
                          path!,
                          fields: {
                            'version': version.text.trim(),
                            'channel': channel,
                            'signature': signature.text.trim(),
                          },
                        );
                        if (context.mounted) {
                          widget.controller.tell(pt(context, 'Saved'));
                        }
                      } finally {
                        if (mounted) setState(() => busy = false);
                      }
                    }),
              child: Text(pt(context, 'Release')),
            ),
          ],
        ),
      ],
    ),
  );
}
