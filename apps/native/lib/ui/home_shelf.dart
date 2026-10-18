import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/controller.dart';
import '../core/models.dart';
import '../l10n/glukwave27_ui_strings.dart';
import '../l10n/wave_localizations.dart';
import 'widgets.dart';

class NativeHomeShelf extends StatefulWidget {
  final WaveController controller;
  final VoidCallback onLikes;
  final ValueChanged<Json> onPlaylist;
  const NativeHomeShelf({
    super.key,
    required this.controller,
    required this.onLikes,
    required this.onPlaylist,
  });
  @override
  State<NativeHomeShelf> createState() => _NativeHomeShelfState();
}

class _NativeHomeShelfState extends State<NativeHomeShelf> {
  WaveController get c => widget.controller;
  String? pending;
  String title(Json pin) => pin['type'] == 'likes'
      ? wt('native.d3aa3fa13d', context: context)
      : pin['type'] == 'mix'
      ? pin['genre'].toString()
      : c.playlists
                .where((list) => list['id'] == pin['playlistId'])
                .map((list) => list['name'].toString())
                .firstOrNull ??
            wave27Text(context, 'addPlaylist');
  String get day {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  Future<void> playMix(String id, Json query) async {
    if (pending != null) return;
    final account = c.user?.id, origin = c.api.server;
    setState(() => pending = id);
    try {
      final data = await c.api.call(
        '/api/recommendations',
        query: {...query, 'day': day, 'limit': 30},
      );
      if (!mounted || account != c.user?.id || origin != c.api.server) return;
      final tracks = objects(data['tracks']).map(WaveTrack.new).toList();
      if (tracks.isEmpty) {
        c.tell(wave27Text(context, 'noTracks'));
        return;
      }
      await c.play(tracks.first, list: tracks);
    } catch (error) {
      c.tell(error.toString());
    } finally {
      if (mounted) setState(() => pending = null);
    }
  }

  void open(Json pin) {
    if (pin['type'] == 'mix') {
      playMix(pin['id'].toString(), {
        'genre': pin['genre'],
        'mood': pin['mood'] ?? 'personal',
      });
      return;
    }
    if (pin['type'] == 'likes') {
      widget.onLikes();
      return;
    }
    final playlist = c.playlists
        .where((item) => item['id'] == pin['playlistId'])
        .firstOrNull;
    if (playlist != null) widget.onPlaylist(playlist);
  }

  Future<void> edit() async {
    final result = await showWaveDialog<List<Json>>(
      context: context,
      builder: (_) => HomeShelfEditor(controller: c),
    );
    if (result != null) {
      try {
        await c.updateSettings({'homePins': result});
      } catch (error) {
        c.tell(error.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = waveVisuals(context), pins = objects(c.settings['homePins']);
    String text(String key) => wave27Text(context, key);
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Text(
                text('yourShelf'),
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.5,
                ),
              ),
              TextButton.icon(
                key: const Key('home-edit-shelf'),
                onPressed: edit,
                icon: const Icon(Icons.tune_rounded, size: 17),
                label: Text(text('editHome')),
              ),
            ],
          ),
          if (pins.isEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: edit,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(
                  text('emptyShelf'),
                  style: TextStyle(fontSize: 11, height: 1.6, color: v.muted),
                ),
              ),
            )
          else
            SizedBox(
              height: 88,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: pins.length,
                separatorBuilder: (_, index) => const SizedBox(width: 12),
                itemBuilder: (_, index) {
                  final pin = pins[index],
                      icon = pin['type'] == 'likes'
                          ? Icons.favorite_border_rounded
                          : pin['type'] == 'mix'
                          ? Icons.radio_rounded
                          : Icons.queue_music_rounded;
                  return SizedBox(
                    width: 248,
                    child: Material(
                      color: v.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(v.corners(12)),
                        side: BorderSide(color: v.line),
                      ),
                      child: InkWell(
                        key: Key('home-pin-${pin['id']}'),
                        onTap: pending == null ? () => open(pin) : null,
                        borderRadius: BorderRadius.circular(v.corners(12)),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              Icon(icon, color: v.accent, size: 25),
                              const SizedBox(width: 13),
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title(pin),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      pending == pin['id']
                                          ? '…'
                                          : pin['type'] == 'mix'
                                          ? text('mix')
                                          : pin['type'] == 'likes'
                                          ? '${c.likedIds.length}'
                                          : wave27Text(context, 'addPlaylist'),
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: v.muted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.north_east_rounded,
                                size: 17,
                                color: v.muted,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                text('daily'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(day, style: TextStyle(fontSize: 10, color: v.muted)),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (_, constraints) {
              final columns = constraints.maxWidth < 600 ? 2 : 4;
              return Wrap(
                children: [
                  for (final item in [
                    ('morning', Icons.wb_sunny_outlined),
                    ('focus', Icons.adjust_rounded),
                    ('evening', Icons.nightlight_outlined),
                    ('discovery', Icons.auto_awesome_outlined),
                  ])
                    SizedBox(
                      width: constraints.maxWidth / columns,
                      child: InkWell(
                        onTap: pending == null
                            ? () => playMix(item.$1, {'mix': item.$1})
                            : null,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 18,
                            horizontal: 10,
                          ),
                          decoration: BoxDecoration(
                            border: Border(
                              top: BorderSide(color: v.line),
                              bottom: BorderSide(color: v.line),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(item.$2, size: 21, color: v.accent),
                              const SizedBox(width: 11),
                              Expanded(
                                child: Text(
                                  text(item.$1),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              if (pending == item.$1)
                                Text('…', style: TextStyle(color: v.muted))
                              else
                                Icon(
                                  Icons.north_east_rounded,
                                  size: 15,
                                  color: v.muted,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class HomeShelfEditor extends StatefulWidget {
  final WaveController controller;
  const HomeShelfEditor({super.key, required this.controller});
  @override
  State<HomeShelfEditor> createState() => _HomeShelfEditorState();
}

class _HomeShelfEditorState extends State<HomeShelfEditor> {
  WaveController get c => widget.controller;
  late List<Json> draft;
  final genre = TextEditingController();
  String? playlist;
  int counter = 0;
  @override
  void initState() {
    super.initState();
    draft = objects(
      c.settings['homePins'],
    ).map((item) => Json.of(item)).toList();
  }

  @override
  void dispose() {
    genre.dispose();
    super.dispose();
  }

  String title(Json pin) => pin['type'] == 'likes'
      ? wave27Text(context, 'addLikes')
      : pin['type'] == 'mix'
      ? pin['genre'].toString()
      : c.playlists
                .where((item) => item['id'] == pin['playlistId'])
                .map((item) => item['name'].toString())
                .firstOrNull ??
            wave27Text(context, 'addPlaylist');
  void add(Json pin) {
    if (draft.length >= 12) return;
    setState(
      () => draft.add({
        'id': 'pin-${DateTime.now().microsecondsSinceEpoch}-${++counter}',
        ...pin,
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final v = waveVisuals(context),
        size = MediaQuery.sizeOf(context),
        available = c.playlists
            .where(
              (item) => !draft.any(
                (pin) =>
                    pin['type'] == 'playlist' &&
                    pin['playlistId'] == item['id'],
              ),
            )
            .toList();
    String text(String key) => wave27Text(context, key);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 24),
      child: SizedBox(
        width: 560,
        height: math.min(740, size.height - 48),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      text('editHome'),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).closeButtonTooltip,
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, size: 19),
                  ),
                ],
              ),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        text('pickup'),
                        style: TextStyle(
                          fontSize: 11,
                          color: v.muted,
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (draft.isNotEmpty)
                        SizedBox(
                          height: math.min(280, draft.length * 68),
                          child: ReorderableListView.builder(
                            key: const Key('home-pins-order'),
                            buildDefaultDragHandles: false,
                            itemCount: draft.length,
                            onReorder: (from, to) {
                              if (to > from) to--;
                              setState(() {
                                final item = draft.removeAt(from);
                                draft.insert(to, item);
                              });
                            },
                            proxyDecorator: (child, index, animation) =>
                                AnimatedBuilder(
                                  animation: animation,
                                  child: child,
                                  builder: (_, child) => Transform.scale(
                                    scale: 1 + .025 * animation.value,
                                    child: Material(
                                      elevation: 14 * animation.value,
                                      color: v.surface,
                                      borderRadius: BorderRadius.circular(12),
                                      child: child,
                                    ),
                                  ),
                                ),
                            itemBuilder: (_, index) {
                              final pin = draft[index];
                              return ReorderableDelayedDragStartListener(
                                key: ValueKey(pin['id']),
                                index: index,
                                child: Container(
                                  height: 68,
                                  decoration: BoxDecoration(
                                    border: Border(
                                      bottom: BorderSide(color: v.line),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      ReorderableDragStartListener(
                                        index: index,
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 5,
                                            vertical: 16,
                                          ),
                                          child: Icon(
                                            Icons.drag_indicator_rounded,
                                            size: 18,
                                            color: v.muted,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          title(pin),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: text('up'),
                                        onPressed: index == 0
                                            ? null
                                            : () => setState(() {
                                                final item = draft.removeAt(
                                                  index,
                                                );
                                                draft.insert(index - 1, item);
                                              }),
                                        icon: const Icon(
                                          Icons.arrow_upward_rounded,
                                          size: 16,
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: text('remove'),
                                        onPressed: () => setState(
                                          () => draft.removeAt(index),
                                        ),
                                        icon: const Icon(
                                          Icons.close_rounded,
                                          size: 17,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      const SizedBox(height: 18),
                      OutlinedButton.icon(
                        key: const Key('home-pin-add-likes'),
                        onPressed:
                            draft.length >= 12 ||
                                draft.any((pin) => pin['type'] == 'likes')
                            ? null
                            : () => add({'type': 'likes'}),
                        icon: const Icon(
                          Icons.favorite_border_rounded,
                          size: 17,
                        ),
                        label: Text(text('addLikes')),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        key: ValueKey('home-playlist-${available.length}'),
                        isExpanded: true,
                        initialValue:
                            available.any((item) => item['id'] == playlist)
                            ? playlist
                            : null,
                        decoration: InputDecoration(
                          labelText: text('addPlaylist'),
                        ),
                        items: [
                          for (final item in available)
                            DropdownMenuItem(
                              value: item['id'].toString(),
                              child: Text(
                                item['name'].toString(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (value) => setState(() => playlist = value),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: playlist == null || draft.length >= 12
                              ? null
                              : () {
                                  add({
                                    'type': 'playlist',
                                    'playlistId': playlist,
                                  });
                                  setState(() => playlist = null);
                                },
                          icon: const Icon(Icons.add_rounded, size: 17),
                          label: Text(text('addPlaylist')),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        key: const Key('home-pin-genre'),
                        controller: genre,
                        maxLength: 40,
                        decoration: InputDecoration(
                          labelText: text('genre'),
                          hintText: 'Ambient, phonk, indie…',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          key: const Key('home-pin-add-mix'),
                          onPressed:
                              genre.text.trim().isEmpty || draft.length >= 12
                              ? null
                              : () {
                                  add({
                                    'type': 'mix',
                                    'genre': genre.text.trim(),
                                    'mood': 'personal',
                                  });
                                  genre.clear();
                                },
                          icon: const Icon(Icons.add_rounded, size: 17),
                          label: Text(text('addMix')),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              FilledButton(
                key: const Key('home-save-shelf'),
                onPressed: () => Navigator.pop(context, draft),
                child: Text(text('save')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
