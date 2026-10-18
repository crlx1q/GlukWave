import 'provider_access.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/controller.dart';
import '../core/models.dart';
import '../l10n/wave_localizations.dart';
import 'widgets.dart';
import 'refinement20_strings.dart';
import 'public_import_strings.dart';

Future<void> showProviderImport(
  BuildContext context,
  WaveController controller,
  String provider, {
  bool connected = false,
  bool publicMode = true,
}) => showWaveDialog<void>(
  context: context,
  builder: (_) => ProviderImport(
    controller: controller,
    provider: provider,
    connected: connected,
    publicMode: publicMode,
  ),
);

class ProviderImport extends StatefulWidget {
  final WaveController controller;
  final String provider;
  final bool connected, publicMode;
  const ProviderImport({
    super.key,
    required this.controller,
    required this.provider,
    this.connected = false,
    this.publicMode = true,
  });
  @override
  State<ProviderImport> createState() => _ProviderImportState();
}

class _ProviderImportState extends State<ProviderImport> {
  WaveController get c => widget.controller;
  late String? account;
  late String origin;
  late bool publicMode;
  late bool authorized;
  final query = TextEditingController();
  final scroll = ScrollController();
  final selected = <String>{};
  List<Json> collections = [], tracks = [];
  Json? collection, result;
  Json exposure = {}, searchExposure = {};
  String? cursor, error;
  String destination = 'playlist', intentSignature = '', requestId = '';
  bool busy = false, saving = false, all = true, searched = false;
  int generation = 0;
  Future<void> Function()? retry;
  bool current(int version) =>
      mounted &&
      version == generation &&
      account == c.user?.id &&
      origin == c.api.server;
  String id(Json track) => track['id'].toString();
  List<String> warnings(Json value) => (value['warnings'] as List? ?? [])
      .map((item) => item.toString())
      .toList();
  Json combine(Json first, Json second) => {
    'partial': first['partial'] == true || second['partial'] == true,
    'warnings': {...warnings(first), ...warnings(second)}.toList(),
  };

  @override
  void initState() {
    super.initState();
    account = c.user?.id;
    origin = c.api.server;
    publicMode = widget.publicMode;
    authorized = widget.connected;
    c.addListener(checkScope);
    if (!publicMode) unawaited(loadCollections());
  }

  void reset() {
    generation++;
    collections = [];
    tracks = [];
    collection = result = null;
    exposure = {};
    searchExposure = {};
    selected.clear();
    cursor = error = null;
    busy = saving = searched = false;
    intentSignature = requestId = '';
    scrollToStart();
  }

  void scrollToStart() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted && scroll.hasClients) scroll.jumpTo(0);
  });

  void checkScope() {
    if (!mounted || account == c.user?.id && origin == c.api.server) return;
    setState(() {
      reset();
      query.clear();
      account = c.user?.id;
      origin = c.api.server;
      publicMode = true;
    });
  }

  @override
  void didUpdateWidget(covariant ProviderImport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(checkScope);
      c.addListener(checkScope);
    }
    if (oldWidget.provider != widget.provider ||
        oldWidget.controller != widget.controller) {
      reset();
      account = c.user?.id;
      origin = c.api.server;
      publicMode = true;
      query.clear();
    }
  }

  @override
  void dispose() {
    generation++;
    c.removeListener(checkScope);
    query.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> loadCollections() async {
    if (account == null || publicMode && query.text.trim().isEmpty) return;
    FocusManager.instance.primaryFocus?.unfocus();
    retry = loadCollections;
    final version = ++generation;
    setState(() {
      busy = searched = true;
      error = null;
      collections = [];
      exposure = {};
      searchExposure = {};
    });
    try {
      final data = publicMode
          ? await c.api.call(
              '/api/public-import/search',
              method: 'POST',
              data: {'provider': widget.provider, 'query': query.text.trim()},
            )
          : await c.api.call('/api/integrations/${widget.provider}/playlists');
      if (current(version)) {
        setState(() {
          collections = [
            if (object(data['liked']).isNotEmpty) object(data['liked']),
            ...objects(data['playlists']),
          ];
          exposure = searchExposure = combine({}, data);
        });
      }
    } catch (e) {
      if (current(version)) setState(() => error = e.toString());
    } finally {
      if (current(version)) setState(() => busy = false);
    }
  }

  Future<void> loadTracks(Json value, [String? next]) async {
    if (saving) return;
    retry = () => loadTracks(value, next);
    final version = ++generation;
    setState(() {
      busy = true;
      error = null;
      if (next == null) {
        collection = value;
        tracks = [];
        selected.clear();
        cursor = null;
        all = true;
        exposure = searchExposure;
        destination = value['kind'] == 'likes' || value['id'] == 'liked'
            ? 'likes'
            : 'playlist';
        intentSignature = requestId = '';
        scrollToStart();
      }
    });
    try {
      final data = publicMode
          ? await c.api.call(
              '/api/public-import/tracks',
              method: 'POST',
              data: {
                'provider': widget.provider,
                'sourceUrl': value['sourceUrl'],
                if (next != null) 'cursor': next,
              },
            )
          : await c.api.call(
              '/api/integrations/${widget.provider}/playlists/${Uri.encodeComponent(value['id'].toString())}/tracks',
              query: {if (next != null) 'cursor': next},
            );
      if (current(version)) {
        setState(() {
          final loaded = objects(data['tracks']);
          final knownIds = tracks.map(id).toSet();
          tracks = {
            for (final track in [...tracks, ...loaded]) id(track): track,
          }.values.toList();
          selected.addAll(
            loaded.where((track) => !knownIds.contains(id(track))).map(id),
          );
          cursor = data['nextCursor']?.toString();
          if (cursor?.isEmpty == true) cursor = null;
          final total = data['total'];
          if (total is num && total.isFinite) {
            collection = {...?collection, 'trackCount': total.toInt()};
          } else if (cursor == null) {
            collection = {...?collection, 'trackCount': tracks.length};
          }
          exposure = combine(exposure, data);
        });
      }
    } catch (e) {
      if (current(version)) setState(() => error = e.toString());
    } finally {
      if (current(version)) setState(() => busy = false);
    }
  }

  Future<void> importTracks() async {
    if (collection == null || saving || result != null) return;
    retry = importTracks;
    final version = ++generation;
    final body = <String, dynamic>{
      'playlistId': collection!['id'],
      'destination': destination,
      if (destination == 'playlist')
        'name': collection!['name'].toString().substring(
          0,
          math.min(120, collection!['name'].toString().length),
        ),
      if (publicMode) 'publicSourceUrl': collection!['sourceUrl'],
      if (!all) 'trackIds': selected.toList()..sort(),
    };
    final signature = jsonEncode([account, origin, widget.provider, body]);
    if (signature != intentSignature) {
      intentSignature = signature;
      requestId =
          'native-${DateTime.now().microsecondsSinceEpoch}-${math.Random.secure().nextInt(1 << 30)}';
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final data = await c.api.call(
        '/api/integrations/${widget.provider}/import',
        method: 'POST',
        data: {...body, 'requestId': requestId},
      );
      if (current(version)) {
        setState(() {
          result = {...data, ...combine(exposure, data)};
          saving = false;
        });
        scrollToStart();
        try {
          await c.refreshLibrary();
        } catch (e) {
          if (current(version)) c.tell(e.toString());
        }
      }
    } catch (e) {
      if (current(version)) setState(() => error = e.toString());
    } finally {
      if (current(version)) setState(() => saving = false);
    }
  }

  Widget notice(Json value) {
    if (value['partial'] != true && warnings(value).isEmpty) {
      return const SizedBox.shrink();
    }
    final v = waveVisuals(context);
    final messages =
        warnings(value)
            .map(
              (warning) => warning == 'PUBLIC_UNAVAILABLE_TRACKS'
                  ? publicImportText(context, 'unavailableHint')
                  : RegExp(r'^[A-Z][A-Z0-9_]+$').hasMatch(warning)
                  ? publicImportText(context, 'partialHint')
                  : warning,
            )
            .toSet()
          ..remove(publicImportText(context, 'partialHint'));
    return Container(
      key: const Key('public-import-partial'),
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: v.surface,
        border: Border.all(color: v.accent.withValues(alpha: .35)),
        borderRadius: BorderRadius.circular(v.corners(12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            publicImportText(context, 'partial'),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 5),
          Text(
            publicImportText(context, 'partialHint'),
            style: TextStyle(color: v.muted, fontSize: 11, height: 1.5),
          ),
          for (final warning in messages)
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                warning,
                style: TextStyle(color: v.muted, fontSize: 11, height: 1.5),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final v = waveVisuals(context), size = MediaQuery.sizeOf(context);
    String text(String key) => refinementText(context, key);
    String copy(String key) => publicImportText(context, key);
    final children = <Widget>[];
    if (result != null) {
      children.addAll([
        const SizedBox(height: 20),
        Icon(Icons.check_circle_outline_rounded, color: v.accent, size: 46),
        const SizedBox(height: 14),
        Text(
          text('imported'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 9),
        Text(
          WaveStrings.of(
            context,
          ).plural('count.tracks', number(result!['imported']).toInt()),
          textAlign: TextAlign.center,
          style: TextStyle(color: v.muted),
        ),
        for (final count in ['deduplicated', 'unavailable'])
          if (number(result![count]) > 0)
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                '${text(count == 'deduplicated' ? 'duplicates' : 'unavailable')}: ${result![count]}',
                textAlign: TextAlign.center,
                style: TextStyle(color: v.muted, fontSize: 11),
              ),
            ),
        notice(result!),
        if (result!['tasteSeeded'] == true)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              text('tasteSeed'),
              textAlign: TextAlign.center,
              style: TextStyle(color: v.muted, height: 1.5, fontSize: 12),
            ),
          ),
        FilledButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          child: Text(wt('native.398c7d4f7b', context: context)),
        ),
      ]);
    } else if (collection == null) {
      children.addAll([
        ProviderAccess(
          key: ValueKey('$account:${widget.provider}'),
          controller: c,
          provider: widget.provider,
          onConnected: () {
            setState(() {
              reset();
              authorized = true;
              publicMode = false;
            });
            unawaited(loadCollections());
          },
        ),
        if (authorized)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in [true, false])
                  ChoiceChip(
                    label: Text(copy(option ? 'public' : 'connected')),
                    selected: publicMode == option,
                    onSelected: (_) {
                      setState(() {
                        reset();
                        query.clear();
                        publicMode = option;
                      });
                      if (!option) unawaited(loadCollections());
                    },
                  ),
              ],
            ),
          ),
        if (publicMode) ...[
          Text(
            copy('query'),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('public-import-query'),
            controller: query,
            textInputAction: TextInputAction.search,
            maxLength: 2048,
            decoration: InputDecoration(
              hintText: copy('placeholder'),
              counterText: '',
            ),
            onChanged: (_) => setState(() {
              generation++;
              searched = busy = false;
              collections = [];
              error = null;
              exposure = {};
              searchExposure = {};
            }),
            onSubmitted: (_) {
              if (!busy) unawaited(loadCollections());
            },
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            key: const Key('public-import-find'),
            onPressed: busy || query.text.trim().isEmpty
                ? null
                : loadCollections,
            icon: const Icon(Icons.search_rounded, size: 18),
            label: Text(copy('find')),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              copy('hint'),
              style: TextStyle(color: v.muted, fontSize: 11, height: 1.5),
            ),
          ),
        ],
        notice(exposure),
        if (busy)
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              copy('finding'),
              textAlign: TextAlign.center,
              style: TextStyle(color: v.muted),
            ),
          ),
        if (collections.isEmpty && searched && !busy && error == null) ...[
          Text(
            copy('empty'),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            copy('emptyHint'),
            style: TextStyle(color: v.muted, fontSize: 12, height: 1.5),
          ),
        ],
        for (final item in collections)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: v.surface,
              borderRadius: BorderRadius.circular(v.corners(14)),
              child: InkWell(
                onTap: busy ? null : () => loadTracks(item),
                borderRadius: BorderRadius.circular(v.corners(14)),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      if (item['kind'] == 'likes' || item['id'] == 'liked')
                        Icon(
                          Icons.favorite_border_rounded,
                          color: v.accent,
                          size: 28,
                        )
                      else if (item['artwork']?.toString().isNotEmpty == true)
                        Artwork(
                          controller: c,
                          url: item['artwork'].toString(),
                          size: 44,
                          radius: 8,
                        )
                      else
                        Icon(
                          item['id'] == 'liked'
                              ? Icons.favorite_border_rounded
                              : Icons.queue_music_rounded,
                          color: v.accent,
                          size: 28,
                        ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item['name'].toString(),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              publicMode && number(item['trackCount']) == 0
                                  ? copy('collection')
                                  : '${item['trackCount'] ?? ''}',
                              style: TextStyle(color: v.muted, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, size: 20),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ]);
    } else {
      children.addAll([
        notice(exposure),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in ['playlist', 'likes'])
              ChoiceChip(
                label: Text(
                  text(option == 'likes' ? 'importLikes' : 'importPlaylist'),
                ),
                selected: destination == option,
                onSelected: saving
                    ? null
                    : (_) => setState(() => destination = option),
              ),
          ],
        ),
        CheckboxListTile(
          key: const Key('import-all'),
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(text('importAll'), style: const TextStyle(fontSize: 12)),
          value: all,
          onChanged: saving
              ? null
              : (value) => setState(() => all = value == true),
        ),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '${text('selection')}: ${all ? collection!['trackCount'] ?? tracks.length : selected.length}',
              style: TextStyle(fontSize: 11, color: v.muted),
            ),
            if (!all)
              TextButton(
                onPressed: saving || busy
                    ? null
                    : () => setState(() {
                        selected.clear();
                        selected.addAll(tracks.map(id));
                      }),
                child: Text(text('selectAll')),
              ),
          ],
        ),
        const SizedBox(height: 8),
        for (final track in tracks)
          CheckboxListTile(
            key: Key('import-track-${id(track)}'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            secondary: Artwork(
              controller: c,
              url: track['artwork']?.toString(),
              size: 38,
              radius: 8,
            ),
            title: Text(
              track['title']?.toString() ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              track['artist']?.toString() ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            value: all || selected.contains(id(track)),
            onChanged: saving || all
                ? null
                : (value) => setState(() {
                    value == true
                        ? selected.add(id(track))
                        : selected.remove(id(track));
                  }),
          ),
        if (tracks.isEmpty && !busy && error == null)
          Text(copy('emptyTracks'), style: TextStyle(color: v.muted)),
        if (cursor != null)
          TextButton(
            onPressed: busy || saving
                ? null
                : () => loadTracks(collection!, cursor),
            child: Text(text('loadMore')),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(
            text('tasteSeed'),
            style: TextStyle(fontSize: 11, color: v.muted, height: 1.5),
          ),
        ),
        FilledButton(
          onPressed:
              busy ||
                  saving ||
                  error != null ||
                  tracks.isEmpty ||
                  !all && selected.isEmpty
              ? null
              : importTracks,
          child: Text(
            saving
                ? text('importing')
                : wt('native.e8b58dacdf', context: context),
          ),
        ),
      ]);
    }
    if (error != null) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                error!,
                style: TextStyle(color: v.muted, fontSize: 12, height: 1.4),
              ),
              TextButton(
                onPressed: busy || saving ? null : retry,
                child: Text(text('retry')),
              ),
            ],
          ),
        ),
      );
    }
    return PopScope(
      canPop: !saving,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        child: SizedBox(
          width: math.min(600.0, size.width - 24),
          height: math.max(
            100.0,
            math.min(
              670.0,
              size.height - MediaQuery.viewInsetsOf(context).bottom - 40,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (collection != null && result == null)
                      IconButton(
                        key: const Key('import-back'),
                        tooltip: wt('native.f6dab074d7', context: context),
                        onPressed: busy || saving
                            ? null
                            : () => setState(() {
                                generation++;
                                collection = null;
                                tracks = [];
                                error = null;
                                exposure = searchExposure;
                              }),
                        icon: const Icon(Icons.arrow_back_rounded, size: 20),
                      ),
                    Expanded(
                      child: Text(
                        collection?['name']?.toString() ??
                            switch (widget.provider) {
                              'spotify' => 'Spotify',
                              'soundcloud' => 'SoundCloud',
                              'youtube' => 'YouTube Music',
                              'yandex' => 'Yandex Music',
                              _ => widget.provider,
                            },
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      key: const Key('import-close'),
                      tooltip: wt('native.398c7d4f7b', context: context),
                      onPressed: saving ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded, size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (busy || saving)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: LinearProgressIndicator(
                      minHeight: 2,
                      color: v.accent,
                    ),
                  ),
                Expanded(
                  child: ListView(
                    key: const Key('provider-import-scroll'),
                    controller: scroll,
                    padding: EdgeInsets.zero,
                    children: children,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
