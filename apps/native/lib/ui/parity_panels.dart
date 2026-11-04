import 'playlist_manager.dart';
import 'client32_content.dart';
import 'client32_workspace.dart';
import 'discovery.dart' show openDiscoveryPlaylist;
import '../l10n/glukwave26_strings.dart';
import 'package:audio_service/audio_service.dart';
import 'wave18_strings.dart';
import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../core/controller.dart';
import '../core/models.dart';
import '../core/parity.dart';
import '../l10n/parity_strings.dart';
import '../l10n/wave_localizations.dart';
import 'widgets.dart';
import 'settings_edit.dart';

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
) {
  final body = _TrackActionsBody(
    controller: c,
    track: track,
    account: c.user?.id,
  );
  return MediaQuery.sizeOf(context).width < 720
      ? showModalBottomSheet<void>(
          context: context,
          useSafeArea: true,
          isScrollControlled: true,
          showDragHandle: true,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .88,
          ),
          builder: (_) => body,
        )
      : showWaveDialog<void>(
          context: context,
          builder: (_) => Dialog(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: body,
            ),
          ),
        );
}

class _TrackActionsBody extends StatelessWidget {
  final WaveController controller;
  final WaveTrack track;
  final String? account;
  const _TrackActionsBody({
    required this.controller,
    required this.track,
    this.account,
  });
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final c = controller,
          v = waveVisuals(context),
          active = account == controller.user?.id;
      void perform(Future<void> Function() action) {
        Navigator.pop(context);
        if (active) unawaited(parityRun(c, action));
      }

      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                children: [
                  Artwork(
                    controller: c,
                    url: track.artwork,
                    size: 62,
                    radius: 12,
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          track.artist,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: v.muted),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          track.sourceName,
                          style: TextStyle(fontSize: 10, color: v.muted),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).closeButtonTooltip,
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, size: 20),
                  ),
                ],
              ),
            ),
            Divider(color: v.line),
            ListTile(
              key: const Key('track-action-like'),
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                c.likedIds.contains(track.id)
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                color: c.likedIds.contains(track.id) ? v.accent : v.ink,
              ),
              title: Text(
                wt(
                  c.likedIds.contains(track.id)
                      ? 'native.4ddf34c036'
                      : 'native.5633e5c745',
                  context: context,
                ),
              ),
              enabled: active && c.online,
              onTap: () => perform(() => c.like(track)),
            ),
            ListTile(
              key: const Key('track-action-queue'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.queue_music_rounded),
              title: Text(wt('native.f130436a3b', context: context)),
              enabled: active && c.canControl,
              onTap: () =>
                  perform(() => c.audio.addQueueItem(c.audio.item(track))),
            ),
            ListTile(
              key: const Key('track-action-playlist'),
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                c.playlistsForTrack(track.id).isEmpty
                    ? Icons.playlist_add_rounded
                    : Icons.playlist_add_check_rounded,
                color: c.playlistsForTrack(track.id).isEmpty ? v.ink : v.accent,
              ),
              title: Text(membershipLabel(context, c, track)),
              enabled: active && c.online,
              onTap: () {
                Navigator.pop(context);
                if (active) showPlaylistMembership(context, c, track);
              },
            ),
            if (track.playable || c.cache.contains(track.id))
              ListTile(
                key: const Key('track-action-download'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.download_outlined),
                title: Text(wt('native.5fbca5dea7', context: context)),
                enabled: active && (c.online || c.cache.contains(track.id)),
                onTap: () => perform(() => c.downloadTrack(track)),
              ),
            if (track.sourceUrl.isNotEmpty) ...[
              Divider(color: v.line),
              ListTile(
                key: const Key('track-action-source'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.open_in_new_rounded),
                title: Text(
                  wt(
                    'native.22618d4822',
                    context: context,
                    values: {'p0': track.sourceName},
                  ),
                ),
                enabled: active,
                onTap: () => perform(() => c.openUrl(track.sourceUrl)),
              ),
            ],
          ],
        ),
      );
    },
  );
}

/// Owns optional endpoint states independently of playback/library refresh.
class ApiPanel extends StatefulWidget {
  final WaveController controller;
  final String path;
  final Widget Function(Json, Future<void> Function()) builder;
  final Listenable? refresh;
  final Future<Json> Function()? loadData;
  final bool bounded;
  const ApiPanel({
    super.key,
    required this.controller,
    required this.path,
    required this.builder,
    this.refresh,
    this.loadData,
    this.bounded = false,
  });
  @override
  State<ApiPanel> createState() => _ApiPanelState();
}

class _ApiPanelState extends State<ApiPanel> {
  Json? data;
  bool failed = false;
  int generation = 0;
  String get scope =>
      '${widget.controller.api.server}|${widget.controller.api.token}|${widget.controller.user?.id}';
  late String accountScope;
  void scopeChanged() {
    if (accountScope == scope) return;
    accountScope = scope;
    unawaited(load());
  }

  @override
  void initState() {
    super.initState();
    accountScope = scope;
    widget.controller.addListener(scopeChanged);
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
    if (old.controller != widget.controller) {
      old.controller.removeListener(scopeChanged);
      widget.controller.addListener(scopeChanged);
      accountScope = scope;
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
    widget.controller.removeListener(scopeChanged);
    generation++;
    super.dispose();
  }

  void refresh() => unawaited(load());

  @override
  Widget build(BuildContext context) {
    final Widget child = failed
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
    return widget.bounded && data == null
        ? SingleChildScrollView(padding: const EdgeInsets.all(24), child: child)
        : child;
  }
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
  await openClientDetail(
    context,
    title: pt(context, 'Taste'),
    identity: 'taste',
    builder: (_) => TastePage(controller: c, parity: parity, embedded: true),
  );
  await parity.load();
}

class TastePage extends StatefulWidget {
  final WaveController controller;
  final WaveParity parity;
  final bool embedded;
  const TastePage({
    super.key,
    required this.controller,
    required this.parity,
    this.embedded = false,
  });
  @override
  State<TastePage> createState() => _TastePageState();
}

class _TastePageState extends State<TastePage> {
  final search = TextEditingController();
  final selected = <String, Json>{};
  List<Json> artists = [];
  final selectedGenres = <String>{};
  static const genres = [
    'pop',
    'hip hop',
    'rock',
    'electronic',
    'dance',
    'indie',
    'rnb',
    'jazz',
    'classical',
    'ambient',
    'lofi',
    'metal',
    'folk',
    'reggae',
  ];
  bool loading = true, saving = false, failed = false, automatic = true;
  Timer? timer;
  int request = 0;
  @override
  void initState() {
    super.initState();
    for (final a in objects(widget.parity.preference['artists'])) {
      selected[a['id'].toString()] = a;
    }
    selectedGenres.addAll(
      (widget.parity.preference['genres'] as List? ?? []).whereType<String>(),
    );
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
        'genres': skip ? <String>[] : selectedGenres.toList(),
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
  Widget build(BuildContext context) {
    final body = Center(
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
            const SizedBox(height: 22),
            Text(
              wave18Text(context, 'wave18.favoriteGenres'),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
            const SizedBox(height: 7),
            Text(
              wave18Text(context, 'wave18.genreCaption'),
              style: TextStyle(color: waveVisuals(context).muted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final genre in {...genres, ...selectedGenres})
                  FilterChip(
                    key: Key('taste-genre-$genre'),
                    label: Text(
                      genres.contains(genre)
                          ? wave18Text(context, 'wave18.genre.$genre')
                          : genre,
                    ),
                    selected: selectedGenres.contains(genre),
                    onSelected: (on) => setState(() {
                      if (on) {
                        if (selectedGenres.length < 20) {
                          selectedGenres.add(genre);
                        }
                      } else {
                        selectedGenres.remove(genre);
                      }
                    }),
                  ),
              ],
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
    );
    return widget.embedded
        ? body
        : Scaffold(
            appBar: AppBar(
              backgroundColor: waveVisuals(context).background,
              title: Text(pt(context, 'Taste')),
            ),
            body: body,
          );
  }
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

Future<void> openGenre(BuildContext context, WaveController c, String genre) =>
    openClientDetail(
      context,
      title: genre,
      identity: 'genre:$genre',
      builder: (_) => GenreDetailContent(controller: c, genre: genre),
    );

class GenreDetailContent extends StatelessWidget {
  final WaveController controller;
  final String genre;
  const GenreDetailContent({
    super.key,
    required this.controller,
    required this.genre,
  });
  @override
  Widget build(BuildContext context) => ApiPanel(
    controller: controller,
    path: '/api/search?q=${Uri.encodeQueryComponent(genre)}&source=all',
    bounded: true,
    builder: (data, _) {
      final tracks = objects(data['tracks']).map(WaveTrack.new).toList(),
          artists = objects(data['artists']);
      return ClientContentScroll(
        slivers: [
          clientBox(PageHeading(genre, '', eyebrow: pt(context, 'Artists'))),
          if (artists.isNotEmpty)
            clientBox(
              ArtistGrid(
                controller: controller,
                artists: artists,
                onTap: (a) => openArtist(context, controller, a),
              ),
            ),
          if (tracks.isNotEmpty)
            clientBox(
              ClientSectionHeading(wave26Text(context, 'artist.tracks')),
            ),
          clientTracks(
            controller: controller,
            tracks: tracks,
            onMore: (track) => parityTrackActions(context, controller, track),
          ),
          if (artists.isEmpty && tracks.isEmpty)
            clientBox(
              EmptyState(
                pt(context, 'No artists'),
                pt(context, 'No artists detail'),
              ),
            ),
        ],
      );
    },
  );
}

Future<void> openArtist(BuildContext context, WaveController c, Json artist) =>
    openClientDetail(
      context,
      title: artist['name']?.toString() ?? pt(context, 'Artists'),
      identity: 'artist:${artist['id']}',
      builder: (_) =>
          ArtistDetail(controller: c, artist: artist, embedded: true),
    );

class ArtistDetail extends StatefulWidget {
  final WaveController controller;
  final Json artist;
  final bool embedded;
  const ArtistDetail({
    super.key,
    required this.controller,
    required this.artist,
    this.embedded = false,
  });
  @override
  State<ArtistDetail> createState() => _ArtistDetailState();
}

class _ArtistDetailState extends State<ArtistDetail> {
  List<WaveTrack> tracks = [];
  Json data = {};
  bool loading = true, failed = false;
  int generation = 0;
  String get path =>
      '/api/artists/${Uri.encodeComponent(widget.artist['id'].toString())}';
  String get scope =>
      '${widget.controller.api.server}|${widget.controller.api.token}|${widget.controller.user?.id}';
  late String accountScope;
  Json get profile => {...widget.artist, ...object(data['artist'])};
  void adopt(Json result) {
    data = result;
    tracks = objects(result['tracks']).map(WaveTrack.new).toList();
  }

  @override
  void initState() {
    super.initState();
    accountScope = scope;
    widget.controller.addListener(changed);
    final saved = widget.controller.api.peekMetadata(path);
    if (saved != null) {
      adopt(saved);
      loading = false;
    }
    unawaited(load());
  }

  void changed() {
    if (!mounted) return;
    if (accountScope != scope) {
      generation++;
      accountScope = scope;
      setState(() {
        data = {};
        tracks = [];
        loading = false;
        failed = true;
      });
      return;
    }
    setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(changed);
    generation++;
    super.dispose();
  }

  Future<void> load({bool force = false}) async {
    final version = ++generation, requestScope = scope;
    setState(() {
      loading = true;
      failed = false;
    });
    try {
      var result = await widget.controller.api.cachedCall(
        path,
        force: force,
        maxAge: const Duration(minutes: 10),
      );
      var found = objects(result['tracks']);
      // Resolve sparse identities locally, retaining the workspace search.
      if (found.isEmpty && widget.controller.online && requestScope == scope) {
        final search = await widget.controller.api.cachedCall(
          '/api/search',
          query: {
            'q': widget.artist['name'],
            'source': widget.artist['source'],
          },
          maxAge: const Duration(minutes: 5),
        );
        final name = widget.artist['name'].toString().toLowerCase();
        found = objects(search['tracks'])
            .where(
              (track) =>
                  track['artist'].toString().toLowerCase().contains(name),
            )
            .toList();
        result = {...result, 'tracks': found};
      }
      if (!mounted || version != generation || requestScope != scope) return;
      setState(() {
        adopt(result);
        loading = false;
        failed = false;
      });
    } catch (_) {
      if (mounted && version == generation && requestScope == scope) {
        setState(() {
          loading = false;
          failed = true;
        });
      }
    }
  }

  Future<void> playAll({bool shuffle = false}) =>
      parityRun(widget.controller, () async {
        if (tracks.isEmpty) return;
        final order = tracks.toList();
        if (shuffle) order.shuffle();
        await widget.controller.play(order.first, list: order);
        await widget.controller.audio.setShuffleMode(
          shuffle ? AudioServiceShuffleMode.all : AudioServiceShuffleMode.none,
        );
      });
  void openAlbum(Json album) {
    final ids = ((album['trackIds'] as List?) ?? const [])
        .map((id) => id.toString())
        .toSet();
    final list = tracks.where((track) => ids.contains(track.id)).toList();
    unawaited(
      openClientDetail(
        context,
        title: album['name']?.toString() ?? '',
        identity:
            'album:${widget.artist['id']}:${album['id'] ?? album['name']}',
        builder: (_) => AlbumDetailContent(
          controller: widget.controller,
          album: album,
          artist: profile,
          tracks: list,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller, v = waveVisuals(context), artist = profile;
    final sourceUrl = artist['sourceUrl']?.toString() ?? '',
        uri = Uri.tryParse(artist['sourceUrl']?.toString() ?? '');
    final albums = objects(data['albums'])
        .where(
          (album) => ((album['trackIds'] as List?) ?? const []).any(
            (id) => tracks.any((track) => track.id == id.toString()),
          ),
        )
        .toList();
    final playlists = objects(data['playlists']);
    final size = MediaQuery.sizeOf(context).width < 600 ? 150.0 : 196.0;
    final body = ClientContentScroll(
      key: ValueKey('artist-detail-${artist['id']}'),
      slivers: [
        clientBox(
          ClientCollectionHero(
            artwork: ClipOval(
              child: Artwork(
                controller: c,
                url: artist['artwork']?.toString(),
                size: size,
                radius: 0,
                icon: Icons.person_outline_rounded,
              ),
            ),
            title: artist['name']?.toString() ?? '',
            eyebrow:
                '${pt(context, 'Artists')} · ${paritySourceName(context, artist['source'])}',
            description: artist['bio']?.toString(),
            actions: [
              if (tracks.isNotEmpty) ...[
                FilledButton.icon(
                  key: const Key('artist-play-all'),
                  onPressed: c.canControl ? playAll : null,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(wave26Text(context, 'artist.playAll')),
                ),
                OutlinedButton.icon(
                  key: const Key('artist-shuffle'),
                  onPressed: c.canControl ? () => playAll(shuffle: true) : null,
                  icon: const Icon(Icons.shuffle_rounded, size: 18),
                  label: Text(wave26Text(context, 'artist.shuffle')),
                ),
              ],
              if (uri?.scheme == 'https' && uri?.host.isNotEmpty == true)
                TextButton.icon(
                  onPressed: () => c.openUrl(sourceUrl),
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: Text(wave26Text(context, 'artist.source')),
                ),
            ],
          ),
        ),
        if (loading)
          clientBox(
            const Padding(
              padding: EdgeInsets.only(top: 20),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          ),
        if (failed)
          clientBox(
            EmptyState(
              pt(context, 'Unavailable'),
              pt(context, 'Unavailable detail'),
              action: OutlinedButton.icon(
                onPressed: () => load(force: true),
                icon: const Icon(Icons.refresh_rounded, size: 17),
                label: Text(pt(context, 'Retry')),
              ),
            ),
          ),
        if (!loading && !failed && tracks.isEmpty)
          clientBox(
            EmptyState(
              wave26Text(context, 'artist.tracks'),
              wave26Text(context, 'artist.empty'),
            ),
          ),
        if (tracks.isNotEmpty) ...[
          clientBox(ClientSectionHeading(wave26Text(context, 'artist.tracks'))),
          clientTracks(
            controller: c,
            tracks: tracks,
            onMore: (track) => parityTrackActions(context, c, track),
          ),
        ],
        if (albums.isNotEmpty) ...[
          clientBox(ClientSectionHeading(wave26Text(context, 'artist.albums'))),
          SliverList.builder(
            itemCount: albums.length,
            itemBuilder: (context, i) {
              final album = albums[i];
              return ListTile(
                key: ValueKey('artist-album-${album['id'] ?? album['name']}'),
                contentPadding: const EdgeInsets.symmetric(vertical: 6),
                leading: Artwork(
                  controller: c,
                  url: album['artwork']?.toString(),
                  size: 52,
                  radius: 9,
                ),
                title: Text(
                  album['name']?.toString() ?? '',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  artist['name']?.toString() ?? '',
                  style: TextStyle(color: v.muted, fontSize: 12),
                ),
                trailing: const Icon(Icons.chevron_right_rounded, size: 20),
                onTap: () => openAlbum(album),
              );
            },
          ),
        ],
        if (playlists.isNotEmpty) ...[
          clientBox(
            ClientSectionHeading(wave26Text(context, 'artist.playlists')),
          ),
          SliverList.builder(
            itemCount: playlists.length,
            itemBuilder: (context, i) {
              final playlist = playlists[i];
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(vertical: 6),
                leading: PlaylistArtwork(
                  controller: c,
                  playlist: playlist,
                  size: 52,
                ),
                title: Text(
                  playlist['name']?.toString() ?? '',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                trailing: const Icon(Icons.chevron_right_rounded, size: 20),
                onTap: () => openDiscoveryPlaylist(context, c, playlist),
              );
            },
          ),
        ],
      ],
    );
    return widget.embedded
        ? body
        : Scaffold(
            appBar: AppBar(
              backgroundColor: v.background,
              title: Text(pt(context, 'Artists')),
            ),
            body: body,
          );
  }
}

class AlbumDetailContent extends StatelessWidget {
  final WaveController controller;
  final Json album, artist;
  final List<WaveTrack> tracks;
  const AlbumDetailContent({
    super.key,
    required this.controller,
    required this.album,
    required this.artist,
    required this.tracks,
  });
  @override
  Widget build(BuildContext context) => ClientContentScroll(
    key: ValueKey('album-detail-${album['id'] ?? album['name']}'),
    slivers: [
      clientBox(
        ClientCollectionHero(
          artwork: Artwork(
            controller: controller,
            url: (album['artwork'] ?? artist['artwork'])?.toString(),
            size: MediaQuery.sizeOf(context).width < 600 ? 164 : 206,
            radius: 12,
          ),
          title: album['name']?.toString() ?? '',
          eyebrow: wave26Text(context, 'artist.albums'),
          description: artist['name']?.toString(),
          actions: [
            if (tracks.isNotEmpty)
              FilledButton.icon(
                key: const Key('album-play-all'),
                onPressed: controller.canControl
                    ? () => parityRun(
                        controller,
                        () => controller.play(tracks.first, list: tracks),
                      )
                    : null,
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(wave26Text(context, 'artist.playAll')),
              ),
            TextButton.icon(
              onPressed: () => openArtist(context, controller, artist),
              icon: const Icon(Icons.person_outline_rounded, size: 17),
              label: Text(artist['name']?.toString() ?? pt(context, 'Artists')),
            ),
          ],
        ),
      ),
      clientBox(ClientSectionHeading(wave26Text(context, 'artist.tracks'))),
      if (tracks.isEmpty)
        clientBox(
          EmptyState(
            wave26Text(context, 'artist.tracks'),
            wave26Text(context, 'artist.empty'),
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
}

Future<void> openPublicProfile(
  BuildContext context,
  WaveController c,
  Json user,
) => openClientDetail(
  context,
  title: user['displayName']?.toString() ?? user['username']?.toString() ?? '',
  identity: 'profile:${user['id']}',
  builder: (_) => PublicProfileContent(controller: c, user: user),
);

class PublicProfileContent extends StatelessWidget {
  final WaveController controller;
  final Json user;
  const PublicProfileContent({
    super.key,
    required this.controller,
    required this.user,
  });
  @override
  Widget build(BuildContext context) => ApiPanel(
    controller: controller,
    path: '/api/profile/${Uri.encodeComponent(user['id'].toString())}',
    bounded: true,
    builder: (data, _) {
      final profile = {...user, ...object(data['user'])},
          stats = object(data['stats']),
          playlists = objects(data['playlists']);
      final v = waveVisuals(context);
      return ClientContentScroll(
        key: ValueKey('public-profile-${user['id']}'),
        slivers: [
          if ((profile['bannerUrl']?.toString() ?? '').isNotEmpty)
            clientBox(
              Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(v.corners(18)),
                  child: AspectRatio(
                    aspectRatio: 3.5,
                    child: LayoutBuilder(
                      builder: (context, box) => FittedBox(
                        fit: BoxFit.cover,
                        clipBehavior: Clip.hardEdge,
                        child: Artwork(
                          controller: controller,
                          url: profile['bannerUrl']?.toString(),
                          size: box.maxWidth,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          clientBox(
            ClientCollectionHero(
              artwork: ClipOval(
                child: Artwork(
                  controller: controller,
                  url: profile['avatarUrl']?.toString(),
                  size: MediaQuery.sizeOf(context).width < 600 ? 100 : 144,
                  radius: 0,
                  icon: Icons.person_outline_rounded,
                ),
              ),
              title:
                  profile['displayName']?.toString() ??
                  profile['username']?.toString() ??
                  '',
              eyebrow: '@${profile['username'] ?? ''}',
              description: profile['bio']?.toString(),
              actions: [
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(
                    (profile['role'] == 'admin'
                            ? 'admin'
                            : profile['plan'] ?? 'free')
                        .toString()
                        .toUpperCase(),
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (data['stats'] is Map)
            clientBox(
              Padding(
                padding: const EdgeInsets.only(top: 28),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 22),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: v.line),
                      bottom: BorderSide(color: v.line),
                    ),
                  ),
                  child: Wrap(
                    spacing: 38,
                    runSpacing: 20,
                    children: [
                      for (final entry in <String, int>{
                        'Plays': number(stats['plays']).round(),
                        'Minutes': (number(stats['listeningSeconds']) / 60)
                            .floor(),
                        'Artists': number(stats['artistCount']).round(),
                      }.entries)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              localizedNumber(entry.value, context: context),
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -.7,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              pt(context, entry.key),
                              style: TextStyle(fontSize: 12, color: v.muted),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
          if (playlists.isNotEmpty) ...[
            clientBox(
              ClientSectionHeading(wave26Text(context, 'artist.playlists')),
            ),
            SliverList.builder(
              itemCount: playlists.length,
              itemBuilder: (context, i) {
                final playlist = playlists[i];
                return ListTile(
                  key: ValueKey('profile-playlist-${playlist['id']}'),
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  leading: PlaylistArtwork(
                    controller: controller,
                    playlist: playlist,
                    size: 54,
                  ),
                  title: Text(
                    playlist['name']?.toString() ?? '',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    playlist['description']?.toString() ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded, size: 20),
                  onTap: () =>
                      openDiscoveryPlaylist(context, controller, playlist),
                );
              },
            ),
          ],
        ],
      );
    },
  );
}

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
    onChanged(
      await controller.updatePlaylist(playlist['id'].toString(), changes),
    );
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
                final account = controller.user?.id,
                    token = controller.api.token,
                    server = controller.api.server;
                final data = await controller.api.upload(
                  '/api/playlists/${playlist['id']}/cover',
                  path,
                );
                if (account != controller.user?.id ||
                    token != controller.api.token ||
                    server != controller.api.server) {
                  return;
                }
                controller.acceptPlaylist(object(data['playlist']));
                onChanged(object(data['playlist']));
              }),
              icon: const Icon(Icons.image_outlined),
              label: Text(pt(context, 'Change cover')),
            ),
            if ((playlist['artwork']?.toString() ?? '').isNotEmpty)
              TextButton(
                onPressed: () => parityRun(controller, () async {
                  final account = controller.user?.id,
                      token = controller.api.token,
                      server = controller.api.server;
                  final data = await controller.api.call(
                    '/api/playlists/${playlist['id']}/cover',
                    method: 'DELETE',
                  );
                  if (account != controller.user?.id ||
                      token != controller.api.token ||
                      server != controller.api.server) {
                    return;
                  }
                  controller.acceptPlaylist(object(data['playlist']));
                  onChanged(object(data['playlist']));
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
            key: ValueKey('discover-public-playlist-${playlist['id']}'),
            onTap: () => openDiscoveryPlaylist(context, controller, playlist),
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
        SettingsEditBoundary(
          store: controller.appearanceStore,
          child: Slider(
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
