import 'dart:async';
import 'package:flutter/material.dart';
import '../core/controller.dart';
import '../core/models.dart';
import 'widgets.dart';
import 'parity_panels.dart' show PlaylistArtwork;
import 'playlist_strings.dart';

String membershipLabel(
  BuildContext context,
  WaveController c,
  WaveTrack track,
) {
  final lists = c.playlistsForTrack(track.id);
  return lists.isEmpty
      ? playlistText(context, 'add')
      : lists.length == 1
      ? playlistText(context, 'one', {
          'name': lists.first['name']?.toString() ?? '',
        })
      : playlistText(context, 'many', {'count': lists.length});
}

Future<void> showPlaylistMembership(
  BuildContext context,
  WaveController c,
  WaveTrack track,
) => showWaveDialog<void>(
  context: context,
  builder: (_) => PlaylistMembershipDialog(controller: c, track: track),
);
Future<void> showPlaylistEditor(
  BuildContext context,
  WaveController c, {
  Json? playlist,
}) => showWaveDialog<void>(
  context: context,
  builder: (_) => PlaylistEditDialog(controller: c, playlist: playlist),
);

class PlaylistMembershipDialog extends StatefulWidget {
  final WaveController controller;
  final WaveTrack track;
  const PlaylistMembershipDialog({
    super.key,
    required this.controller,
    required this.track,
  });
  @override
  State<PlaylistMembershipDialog> createState() =>
      _PlaylistMembershipDialogState();
}

class _PlaylistMembershipDialogState extends State<PlaylistMembershipDialog> {
  final name = TextEditingController(), search = TextEditingController();
  final pending = <String>{};
  final errors = <String, String>{};
  bool creating = false;
  late final String? account;
  WaveController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    account = c.user?.id;
  }

  @override
  void dispose() {
    name.dispose();
    search.dispose();
    super.dispose();
  }

  bool get active => mounted && account == c.user?.id;
  Future<void> perform(String key, Future<void> Function() operation) async {
    if (!active || pending.contains(key)) return;
    setState(() {
      pending.add(key);
      errors.remove(key);
    });
    try {
      await operation();
    } catch (error) {
      if (active) setState(() => errors[key] = error.toString());
    } finally {
      if (active) setState(() => pending.remove(key));
    }
  }

  Future<void> create() async {
    if (!active ||
        creating ||
        pending.contains('create') ||
        name.text.trim().isEmpty) {
      return;
    }
    setState(() => creating = true);
    await perform('create', () async {
      await c.createPlaylist(
        name.text.trim(),
        ids: [widget.track.id],
        knownTracks: [widget.track],
      );
      if (active) name.clear();
    });
    if (active) setState(() => creating = false);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DialogHeading(title: playlistText(context, 'manage')),
              const SizedBox(height: 14),
              Row(
                children: [
                  Artwork(controller: c, url: widget.track.artwork, size: 48),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          widget.track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
              const SizedBox(height: 20),
              TextField(
                controller: search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded, size: 19),
                  hintText: playlistText(context, 'find'),
                ),
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * .34,
                ),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final p in c.playlists.where(
                      (p) => p['name'].toString().toLowerCase().contains(
                        search.text.toLowerCase(),
                      ),
                    )) ...[
                      Builder(
                        builder: (context) {
                          final id = p['id'].toString(),
                              present = List<String>.from(
                                p['trackIds'] ?? [],
                              ).contains(widget.track.id),
                              saving =
                                  c.librarySaving.contains('playlist:$id') ||
                                  id.startsWith('pending:');
                          return ListTile(
                            key: ValueKey('playlist-membership-$id'),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 3,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                waveRadius(context, 12),
                              ),
                            ),
                            selected: present,
                            selectedTileColor: waveVisuals(
                              context,
                            ).accent.withValues(alpha: .08),
                            leading: PlaylistArtwork(
                              controller: c,
                              playlist: p,
                              size: 42,
                            ),
                            title: Text(
                              p['name'].toString(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              playlistText(
                                context,
                                saving ? 'saving' : 'tracks',
                                {
                                  'count': List.from(
                                    p['trackIds'] ?? [],
                                  ).length,
                                },
                              ),
                              style: TextStyle(
                                fontSize: 11,
                                color: waveVisuals(context).muted,
                              ),
                            ),
                            trailing: Icon(
                              present
                                  ? Icons.playlist_add_check_rounded
                                  : Icons.add_rounded,
                              color: present
                                  ? waveVisuals(context).accent
                                  : waveVisuals(context).muted,
                              size: 21,
                            ),
                            enabled: !id.startsWith('pending:'),
                            onTap: () => perform(id, () async {
                              await c.setPlaylistTrack(
                                id,
                                widget.track,
                                !present,
                              );
                            }),
                          );
                        },
                      ),
                      if (errors.containsKey(p['id']))
                        _OperationError(
                          message: errors[p['id']]!,
                          onRetry: () => perform(p['id'].toString(), () async {
                            await c.setPlaylistTrack(
                              p['id'].toString(),
                              widget.track,
                              !List<String>.from(
                                p['trackIds'] ?? [],
                              ).contains(widget.track.id),
                            );
                          }),
                        ),
                    ],
                    if (c.playlists.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(18),
                        child: Text(
                          playlistText(context, 'empty'),
                          style: TextStyle(color: waveVisuals(context).muted),
                        ),
                      ),
                    if (c.playlists.isNotEmpty &&
                        !c.playlists.any(
                          (p) => p['name'].toString().toLowerCase().contains(
                            search.text.toLowerCase(),
                          ),
                        ))
                      Padding(
                        padding: const EdgeInsets.all(18),
                        child: Text(playlistText(context, 'noMatch')),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 12),
              TextField(
                key: const Key('playlist-new-name'),
                controller: name,
                maxLength: 120,
                enabled: !creating,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: playlistText(context, 'create'),
                  counterText: '',
                ),
                onSubmitted: (_) => create(),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: creating || name.text.trim().isEmpty ? null : create,
                icon: creating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_rounded, size: 18),
                label: Text(
                  playlistText(context, creating ? 'saving' : 'create'),
                ),
              ),
              if (errors['create'] != null)
                _OperationError(message: errors['create']!, onRetry: create),
            ],
          ),
        ),
      ),
    ),
  );
}

class PlaylistEditDialog extends StatefulWidget {
  final WaveController controller;
  final Json? playlist;
  const PlaylistEditDialog({
    super.key,
    required this.controller,
    this.playlist,
  });
  @override
  State<PlaylistEditDialog> createState() => _PlaylistEditDialogState();
}

class _PlaylistEditDialogState extends State<PlaylistEditDialog> {
  late final name = TextEditingController(
        text: widget.playlist?['name']?.toString() ?? '',
      ),
      description = TextEditingController(
        text: widget.playlist?['description']?.toString() ?? '',
      );
  late bool public = widget.playlist?['public'] == true;
  bool pending = false, confirm = false;
  String? error;
  late final String? account = widget.controller.user?.id;
  @override
  void dispose() {
    name.dispose();
    description.dispose();
    super.dispose();
  }

  Future<void> save({bool remove = false}) async {
    if (pending || account != widget.controller.user?.id) return;
    setState(() {
      pending = true;
      error = null;
    });
    try {
      final c = widget.controller, p = widget.playlist;
      if (remove && p != null) {
        await c.deletePlaylist(p['id'].toString());
      } else if (p != null) {
        await c.updatePlaylist(p['id'].toString(), {
          'name': name.text.trim(),
          'description': description.text,
          'public': public,
        });
      } else {
        await c.createPlaylist(
          name.text.trim(),
          description: description.text,
          public: public,
        );
      }
      if (mounted && account == c.user?.id) Navigator.pop(context);
    } catch (e) {
      if (mounted && account == widget.controller.user?.id) {
        setState(() => error = e.toString());
      }
    } finally {
      if (mounted && account == widget.controller.user?.id) {
        setState(() => pending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DialogHeading(
              title: playlistText(
                context,
                widget.playlist == null ? 'create' : 'edit',
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              key: const Key('playlist-edit-name'),
              autofocus: true,
              controller: name,
              enabled: !pending,
              maxLength: 120,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: playlistText(context, 'name'),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: description,
              enabled: !pending,
              maxLength: 500,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: playlistText(context, 'description'),
              ),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(playlistText(context, public ? 'public' : 'private')),
              value: public,
              onChanged: pending
                  ? null
                  : (value) => setState(() => public = value),
            ),
            if (error != null)
              _OperationError(
                message: error!,
                onRetry: () => save(remove: confirm),
              ),
            const SizedBox(height: 16),
            if (confirm) ...[
              Text(
                playlistText(context, 'confirm', {'name': name.text}),
                style: const TextStyle(height: 1.5),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                children: [
                  FilledButton(
                    onPressed: pending ? null : () => save(remove: true),
                    child: Text(
                      playlistText(context, pending ? 'saving' : 'delete'),
                    ),
                  ),
                  TextButton(
                    onPressed: pending
                        ? null
                        : () => setState(() => confirm = false),
                    child: Text(playlistText(context, 'cancel')),
                  ),
                ],
              ),
            ] else
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: pending || name.text.trim().isEmpty
                        ? null
                        : save,
                    icon: pending
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_rounded, size: 18),
                    label: Text(
                      playlistText(context, pending ? 'saving' : 'save'),
                    ),
                  ),
                  if (widget.playlist != null)
                    TextButton.icon(
                      onPressed: pending
                          ? null
                          : () => setState(() => confirm = true),
                      icon: const Icon(Icons.delete_outline_rounded, size: 17),
                      label: Text(playlistText(context, 'delete')),
                    ),
                ],
              ),
          ],
        ),
      ),
    ),
  );
}

class PlaylistDetailHeader extends StatelessWidget {
  final WaveController controller;
  final Json playlist;
  final List<WaveTrack> tracks;
  final VoidCallback onAdd, onEdit;
  const PlaylistDetailHeader({
    super.key,
    required this.controller,
    required this.playlist,
    required this.tracks,
    required this.onAdd,
    required this.onEdit,
  });
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final compact = box.maxWidth < 500,
          size = compact ? 104.0 : 160.0,
          total = tracks.fold<double>(0, (sum, t) => sum + t.duration);
      return Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PlaylistArtwork(
              controller: controller,
              playlist: playlist,
              size: size,
            ),
            SizedBox(width: compact ? 16 : 26),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    playlistText(
                      context,
                      playlist['public'] == true ? 'public' : 'private',
                    ),
                    style: TextStyle(
                      color: waveVisuals(context).muted,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    playlist['name'].toString(),
                    style: TextStyle(
                      fontSize: compact ? 24 : 36,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.8,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if ((playlist['description']?.toString() ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 7),
                      child: Text(
                        playlist['description'].toString(),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: waveVisuals(context).muted,
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      '${playlistText(context, 'tracks', {'count': List.from(playlist['trackIds'] ?? []).length})}${total > 0 && tracks.length == List.from(playlist['trackIds'] ?? []).length && tracks.every((t) => t.duration > 0) ? ' · ${clock(total)}' : ''}',
                      style: TextStyle(
                        color: waveVisuals(context).muted,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: tracks.isEmpty
                            ? null
                            : () => unawaited(
                                controller
                                    .play(tracks.first, list: tracks)
                                    .catchError(
                                      (Object e) =>
                                          controller.tell(e.toString()),
                                    ),
                              ),
                        icon: const Icon(Icons.play_arrow_rounded, size: 19),
                        label: Text(playlistText(context, 'play')),
                      ),
                      OutlinedButton.icon(
                        onPressed: onAdd,
                        icon: const Icon(Icons.add_rounded, size: 17),
                        label: Text(playlistText(context, 'addTracks')),
                      ),
                      IconButton(
                        onPressed: onEdit,
                        tooltip: playlistText(context, 'edit'),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

Future<void> showPlaylistTracks(
  BuildContext context,
  WaveController c,
  String id,
) => showWaveDialog<void>(
  context: context,
  builder: (_) => _PlaylistTracks(controller: c, id: id),
);

class _PlaylistTracks extends StatefulWidget {
  final WaveController controller;
  final String id;
  const _PlaylistTracks({required this.controller, required this.id});
  @override
  State<_PlaylistTracks> createState() => _PlaylistTracksState();
}

class _PlaylistTracksState extends State<_PlaylistTracks> {
  late final account = widget.controller.user?.id;
  Future<void> Function()? retry;
  String query = '';
  String? error;
  final pending = <String>{};
  Future<void> toggle(WaveTrack track, bool present) async {
    if (account != widget.controller.user?.id || pending.contains(track.id)) {
      return;
    }
    setState(() {
      pending.add(track.id);
      error = null;
      retry = () => toggle(track, present);
    });
    try {
      await widget.controller.setPlaylistTrack(widget.id, track, present);
    } catch (e) {
      if (mounted && account == widget.controller.user?.id) {
        setState(() => error = e.toString());
      }
    } finally {
      if (mounted && account == widget.controller.user?.id) {
        setState(() => pending.remove(track.id));
      }
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final c = widget.controller,
          p = c.playlists.where((p) => p['id'] == widget.id).firstOrNull ?? {},
          ids = List<String>.from(p['trackIds'] ?? []),
          tracks = c.tracks
              .where(
                (t) => '${t.title} ${t.artist}'.toLowerCase().contains(
                  query.toLowerCase(),
                ),
              )
              .toList();
      return Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DialogHeading(title: playlistText(context, 'addTracks')),
                const SizedBox(height: 14),
                TextField(
                  onChanged: (v) => setState(() => query = v),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded, size: 18),
                    hintText: playlistText(context, 'searchTracks'),
                  ),
                ),
                if (error != null)
                  _OperationError(
                    message: error!,
                    onRetry: () => retry?.call(),
                  ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * .48,
                  ),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final track in tracks)
                        ListTile(
                          key: ValueKey('playlist-library-${track.id}'),
                          contentPadding: EdgeInsets.zero,
                          leading: Artwork(
                            controller: c,
                            url: track.artwork,
                            size: 42,
                          ),
                          title: Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            track.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Icon(
                            ids.contains(track.id)
                                ? Icons.playlist_add_check_rounded
                                : Icons.add_rounded,
                            color: ids.contains(track.id)
                                ? waveVisuals(context).accent
                                : waveVisuals(context).muted,
                          ),
                          onTap: () => toggle(track, !ids.contains(track.id)),
                        ),
                      if (tracks.isEmpty)
                        Text(playlistText(context, 'noMatch')),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _DialogHeading extends StatelessWidget {
  final String title;
  const _DialogHeading({required this.title});
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
      ),
      IconButton(
        onPressed: () => Navigator.pop(context),
        tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
        icon: const Icon(Icons.close_rounded, size: 20),
      ),
    ],
  );
}

class _OperationError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _OperationError({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            message,
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontSize: 12,
            ),
          ),
        ),
        TextButton(
          onPressed: onRetry,
          child: Text(playlistText(context, 'retry')),
        ),
      ],
    ),
  );
}

class PlaylistOrder extends StatefulWidget {
  final WaveController controller;
  final String id;
  const PlaylistOrder({super.key, required this.controller, required this.id});
  @override
  State<PlaylistOrder> createState() => _PlaylistOrderState();
}

class _PlaylistOrderState extends State<PlaylistOrder> {
  String? error;
  Future<void> Function()? retry;
  bool pending = false;
  Future<void> perform(Future<void> Function() action) async {
    if (pending) return;
    setState(() {
      pending = true;
      error = null;
      retry = action;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => pending = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final c = widget.controller,
          p = c.playlists.where((p) => p['id'] == widget.id).firstOrNull ?? {},
          ids = List<String>.from(p['trackIds'] ?? []);
      return ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: Text(
          playlistText(context, 'edit'),
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        children: [
          if (error != null)
            _OperationError(message: error!, onRetry: () => perform(retry!)),
          for (var i = 0; i < ids.length; i++)
            if (c.track(ids[i]) != null)
              Builder(
                builder: (context) {
                  final index = i, track = c.track(ids[i])!;
                  Future<void> move(int direction) async {
                    final order = List<String>.from(
                          (c.playlists
                                      .where((p) => p['id'] == widget.id)
                                      .firstOrNull ??
                                  {})['trackIds'] ??
                              [],
                        ),
                        from = order.indexOf(track.id),
                        to = from + direction;
                    if (from < 0 || to < 0 || to >= order.length) return;
                    final moved = order[from];
                    order[from] = order[to];
                    order[to] = moved;
                    await c.updatePlaylist(widget.id, {'trackIds': order});
                  }

                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        color: waveVisuals(context).muted,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: playlistText(context, 'up'),
                          onPressed: pending || index == 0
                              ? null
                              : () => perform(() => move(-1)),
                          icon: const Icon(
                            Icons.arrow_upward_rounded,
                            size: 17,
                          ),
                        ),
                        IconButton(
                          tooltip: playlistText(context, 'down'),
                          onPressed: pending || index == ids.length - 1
                              ? null
                              : () => perform(() => move(1)),
                          icon: const Icon(
                            Icons.arrow_downward_rounded,
                            size: 17,
                          ),
                        ),
                        IconButton(
                          tooltip: playlistText(context, 'remove'),
                          onPressed: pending
                              ? null
                              : () => perform(() async {
                                  await c.setPlaylistTrack(
                                    widget.id,
                                    track,
                                    false,
                                  );
                                }),
                          icon: const Icon(Icons.close_rounded, size: 17),
                        ),
                      ],
                    ),
                  );
                },
              ),
        ],
      );
    },
  );
}
