import 'package:flutter/material.dart';
import '../core/controller.dart';
import '../core/models.dart';
import '../l10n/wave_localizations.dart';
import 'motion_icons.dart';
import 'native19_strings.dart';
import 'widgets.dart';

class NativeSavedView extends StatelessWidget {
  final WaveController controller;
  final ValueChanged<WaveTrack> onMore;
  final VoidCallback onBrowse;
  const NativeSavedView({
    super.key,
    required this.controller,
    required this.onMore,
    required this.onBrowse,
  });
  Future<void> perform(Future<dynamic> Function() action) async {
    try {
      await action();
    } catch (error) {
      controller.tell(error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = controller, v = waveVisuals(context), tracks = c.savedTracks;
    final pinned = tracks
        .where((track) => object(c.cache.entries[track.id])['manual'] == true)
        .toList();
    final temporary = tracks
        .where((track) => object(c.cache.entries[track.id])['manual'] != true)
        .toList();
    Widget list(List<WaveTrack> items, String title) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 26, bottom: 10),
          child: Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
        ),
        for (final track in items)
          Row(
            children: [
              Expanded(
                child: TrackRow(
                  controller: c,
                  track: track,
                  queue: tracks,
                  onPlay: () => c.playSaved(track, list: tracks),
                  onMore: () => onMore(track),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: nativeText(context, 'more'),
                icon: WaveControlIcon(
                  object(c.cache.entries[track.id])['manual'] == true
                      ? Icons.offline_pin_outlined
                      : Icons.more_horiz_rounded,
                  color: v.accent,
                  size: 19,
                ),
                onSelected: (value) => perform(
                  () => value == 'save'
                      ? c.downloadTrack(track)
                      : c.cache.remove(track.id),
                ),
                itemBuilder: (_) => [
                  if (object(c.cache.entries[track.id])['manual'] != true)
                    PopupMenuItem(
                      value: 'save',
                      child: Text(nativeText(context, 'save')),
                    ),
                  PopupMenuItem(
                    value: 'remove',
                    child: Text(nativeText(context, 'remove')),
                  ),
                ],
              ),
            ],
          ),
      ],
    );
    return Column(
      key: const Key('saved-view'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeading(
          nativeText(context, 'saved'),
          nativeText(context, 'savedDetail'),
          eyebrow: nativeText(context, 'storage').toUpperCase(),
        ),
        Surface(
          padding: const EdgeInsets.all(19),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  WaveControlIcon(
                    Icons.download_for_offline_outlined,
                    size: 24,
                    color: v.accent,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${tracks.length} · ${nativeText(context, 'savedShort')}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              ClipRRect(
                borderRadius: BorderRadius.circular(v.corners(4)),
                child: LinearProgressIndicator(
                  minHeight: 4,
                  value: (c.cache.bytes / (c.cache.limitMB * 1024 * 1024))
                      .clamp(0, 1),
                  color: v.accent,
                  backgroundColor: v.line,
                ),
              ),
              const SizedBox(height: 9),
              Text(
                '${localizedNumber(c.cache.bytes / 1024 / 1024, decimalDigits: 1, context: context)} / ${c.cache.limitMB} MB',
                style: TextStyle(fontSize: 11, color: v.muted),
              ),
              if (tracks.isNotEmpty) ...[
                const SizedBox(height: 18),
                FilledButton.icon(
                  key: const Key('saved-play'),
                  onPressed: () =>
                      perform(() => c.playSaved(tracks.first, list: tracks)),
                  icon: const WavePlayPauseIcon(playing: false, size: 18),
                  label: Text(nativeText(context, 'playSaved')),
                ),
              ],
            ],
          ),
        ),
        for (final entry in c.cache.progress.entries)
          Padding(
            padding: const EdgeInsets.only(top: 18),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.track(entry.key)?.title ??
                            nativeText(context, 'downloading'),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: entry.value > 0 ? entry.value : null,
                        color: v.accent,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: nativeText(context, 'cancel'),
                  onPressed: () => c.cache.cancel(entry.key),
                  icon: const WaveControlIcon(Icons.close_rounded, size: 18),
                ),
              ],
            ),
          ),
        for (final failure in c.cache.failures.entries)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Surface(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.track(failure.key)?.title ??
                              nativeText(context, 'downloading'),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          failure.value,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: v.muted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: c.online && c.track(failure.key) != null
                        ? () => perform(
                            () => c.downloadTrack(c.track(failure.key)!),
                          )
                        : null,
                    child: Text(nativeText(context, 'retry')),
                  ),
                ],
              ),
            ),
          ),
        if (tracks.isEmpty && c.cache.progress.isEmpty)
          EmptyState(
            nativeText(context, 'savedEmpty'),
            nativeText(context, 'savedEmptyDetail'),
            icon: Icons.download_for_offline_outlined,
            action: OutlinedButton(
              onPressed: onBrowse,
              child: Text(wt('native.6433b522a1', context: context)),
            ),
          ),
        if (pinned.isNotEmpty) list(pinned, nativeText(context, 'pinned')),
        if (temporary.isNotEmpty)
          list(temporary, nativeText(context, 'temporary')),
        const SizedBox(height: 24),
        if (temporary.isNotEmpty)
          TextButton(
            onPressed: () => perform(() => c.cache.clear()),
            child: Text(nativeText(context, 'clearCache')),
          ),
      ],
    );
  }
}
