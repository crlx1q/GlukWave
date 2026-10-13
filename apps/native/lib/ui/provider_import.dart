import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/controller.dart';
import '../core/models.dart';
import '../l10n/wave_localizations.dart';
import 'widgets.dart';
import 'refinement20_strings.dart';

Future<void> showProviderImport(
  BuildContext context,
  WaveController controller,
  String provider,
) => showWaveDialog<void>(
  context: context,
  builder: (_) => ProviderImport(controller: controller, provider: provider),
);

class ProviderImport extends StatefulWidget {
  final WaveController controller;
  final String provider;
  const ProviderImport({
    super.key,
    required this.controller,
    required this.provider,
  });
  @override
  State<ProviderImport> createState() => _ProviderImportState();
}

class _ProviderImportState extends State<ProviderImport> {
  WaveController get c => widget.controller;
  late final account = c.user?.id, origin = c.api.server;
  List<Json> collections = [], tracks = [];
  Json? collection, result;
  final selected = <String>{};
  String? cursor, error;
  String destination = 'playlist', intentSignature = '', requestId = '';
  bool busy = false, saving = false, all = true;
  int generation = 0;
  Future<void> Function()? retry;
  bool current(int version) =>
      mounted &&
      version == generation &&
      account == c.user?.id &&
      origin == c.api.server;
  @override
  void initState() {
    super.initState();
    unawaited(loadCollections());
  }

  @override
  void dispose() {
    generation++;
    super.dispose();
  }

  String id(Json track) => (track['sourceId'] ?? track['id']).toString();
  Future<void> loadCollections() async {
    retry = loadCollections;
    final version = ++generation;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final data = await c.api.call(
        '/api/integrations/${widget.provider}/playlists',
      );
      if (current(version)) {
        setState(
          () => collections = [
            if (object(data['liked']).isNotEmpty) object(data['liked']),
            ...objects(data['playlists']),
          ],
        );
      }
    } catch (e) {
      if (current(version)) setState(() => error = e.toString());
    } finally {
      if (current(version)) setState(() => busy = false);
    }
  }

  Future<void> loadTracks(Json value, [String? next]) async {
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
        destination = value['id'] == 'liked' ? 'likes' : 'playlist';
      }
    });
    try {
      final data = await c.api.call(
        '/api/integrations/${widget.provider}/playlists/${Uri.encodeComponent(value['id'].toString())}/tracks',
        query: {if (next != null) 'cursor': next},
      );
      if (current(version)) {
        setState(() {
          final loaded = objects(data['tracks']);
          tracks = {
            for (final track in [...tracks, ...loaded]) id(track): track,
          }.values.toList();
          selected.addAll(loaded.map(id));
          cursor = data['nextCursor']?.toString();
        });
      }
    } catch (e) {
      if (current(version)) setState(() => error = e.toString());
    } finally {
      if (current(version)) setState(() => busy = false);
    }
  }

  Future<void> importTracks() async {
    if (collection == null || saving) return;
    retry = importTracks;
    final version = ++generation;
    final signature =
        '${collection!['id']}|$destination|$all|${(selected.toList()..sort()).join(',')}';
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
        data: {
          'playlistId': collection!['id'],
          'destination': destination,
          'requestId': requestId,
          if (!all) 'trackIds': selected.toList(),
        },
      );
      if (current(version)) {
        setState(() => result = data);
        await c.refresh();
      }
    } catch (e) {
      if (current(version)) setState(() => error = e.toString());
    } finally {
      if (current(version)) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = waveVisuals(context), size = MediaQuery.sizeOf(context);
    String text(String key) => refinementText(context, key);
    return PopScope(
      canPop: !saving,
      child: Dialog(
        child: SizedBox(
          width: math.min(600, size.width - 32),
          height: math.min(670, size.height - 54),
          child: Padding(
            padding: const EdgeInsets.all(18),
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
                                error = null;
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
                const SizedBox(height: 14),
                if (busy || saving)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: LinearProgressIndicator(
                      minHeight: 2,
                      color: v.accent,
                    ),
                  ),
                if (result != null)
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_circle_outline_rounded,
                            color: v.accent,
                            size: 46,
                          ),
                          const SizedBox(height: 14),
                          Text(
                            text('imported'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 9),
                          Text(
                            '${result!['imported']} ${wt('native.32b74a3c47', context: context)}',
                            style: TextStyle(color: v.muted),
                          ),
                          for (final count in ['deduplicated', 'unavailable'])
                            if (number(result![count]) > 0)
                              Padding(
                                padding: const EdgeInsets.only(top: 5),
                                child: Text(
                                  '${text(count == 'deduplicated' ? 'duplicates' : 'unavailable')}: ${result![count]}',
                                  style: TextStyle(
                                    color: v.muted,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                          if (result!['tasteSeeded'] == true)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Text(
                                text('tasteSeed'),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: v.muted,
                                  height: 1.5,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(
                              wt('native.398c7d4f7b', context: context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (collection == null)
                  Expanded(
                    child: collections.isEmpty && !busy && error == null
                        ? Center(child: Text(text('empty')))
                        : ListView.separated(
                            itemCount: collections.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
                            itemBuilder: (_, i) {
                              final item = collections[i];
                              return Material(
                                color: v.surface,
                                borderRadius: BorderRadius.circular(
                                  v.corners(14),
                                ),
                                child: InkWell(
                                  onTap: busy ? null : () => loadTracks(item),
                                  borderRadius: BorderRadius.circular(
                                    v.corners(14),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(13),
                                    child: Row(
                                      children: [
                                        if (item['artwork']
                                                ?.toString()
                                                .isNotEmpty ==
                                            true)
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
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                item['name'].toString(),
                                                maxLines: 2,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              const SizedBox(height: 3),
                                              Text(
                                                '${item['trackCount'] ?? ''}',
                                                style: TextStyle(
                                                  color: v.muted,
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const Icon(
                                          Icons.chevron_right_rounded,
                                          size: 20,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  )
                else ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final option in ['playlist', 'likes'])
                        ChoiceChip(
                          label: Text(
                            text(
                              option == 'likes'
                                  ? 'importLikes'
                                  : 'importPlaylist',
                            ),
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
                    title: Text(
                      text('importAll'),
                      style: const TextStyle(fontSize: 12),
                    ),
                    value: all,
                    onChanged: saving
                        ? null
                        : (value) => setState(() => all = value == true),
                  ),
                  Text(
                    '${text('selection')}: ${all ? collection!['trackCount'] ?? tracks.length : selected.length}',
                    style: TextStyle(fontSize: 11, color: v.muted),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: tracks.length + (cursor != null ? 1 : 0),
                      itemBuilder: (_, i) {
                        if (i == tracks.length) {
                          return TextButton(
                            onPressed: busy || saving
                                ? null
                                : () => loadTracks(collection!, cursor),
                            child: Text(text('loadMore')),
                          );
                        }
                        final track = tracks[i];
                        return CheckboxListTile(
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
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      text('tasteSeed'),
                      style: TextStyle(
                        fontSize: 11,
                        color: v.muted,
                        height: 1.5,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
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
                  ),
                ],
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            error!,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: v.muted,
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: busy || saving ? null : retry,
                          child: Text(text('retry')),
                        ),
                      ],
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
