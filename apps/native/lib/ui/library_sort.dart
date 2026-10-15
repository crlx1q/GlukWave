import 'package:flutter/material.dart';
import '../l10n/wave_localizations.dart';
import '../core/library_order.dart';
import 'widgets.dart';

const _copy = <String, List<String>>{
  "sort": [
    "Sort",
    "Сортировка",
    "Сұрыптау",
    "Сортування",
    "Sortieren",
    "Ordenar",
  ],
  "recent": [
    "Newest first",
    "Сначала новые",
    "Алдымен жаңалары",
    "Спочатку нові",
    "Neueste zuerst",
    "Más recientes",
  ],
  "oldest": [
    "Oldest first",
    "Сначала старые",
    "Алдымен ескілері",
    "Спочатку старі",
    "Älteste zuerst",
    "Más antiguas",
  ],
  "title": [
    "Track title",
    "По названию",
    "Атауы бойынша",
    "За назвою",
    "Titel",
    "Título",
  ],
  "artist": [
    "Artist",
    "По исполнителю",
    "Орындаушы бойынша",
    "За виконавцем",
    "Interpret",
    "Artista",
  ],
  "duration": [
    "Duration",
    "По длительности",
    "Ұзақтығы бойынша",
    "За тривалістю",
    "Dauer",
    "Duración",
  ],
  "original": [
    "Saved order",
    "Порядок плейлиста",
    "Плейлист реті",
    "Порядок плейлиста",
    "Playlist-Reihenfolge",
    "Orden de playlist",
  ],
};
String librarySortText(BuildContext context, String key) {
  final index = [
    'en',
    'ru',
    'kk',
    'uk',
    'de',
    'es',
  ].indexOf(WaveStrings.of(context).language);
  return _copy[key]![index < 0 ? 0 : index];
}

class LibrarySortControl extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final bool playlist;
  const LibrarySortControl({
    super.key,
    required this.value,
    required this.onChanged,
    this.playlist = false,
  });
  @override
  Widget build(BuildContext context) {
    final v = waveVisuals(context);
    return PopupMenuButton<String>(
      key: const Key('library-sort'),
      tooltip: librarySortText(context, 'sort'),
      initialValue: value,
      onSelected: onChanged,
      itemBuilder: (_) => [
        for (final sort in trackSorts.where((s) => playlist || s != 'original'))
          PopupMenuItem(
            value: sort,
            child: Row(
              children: [
                Expanded(child: Text(librarySortText(context, sort))),
                if (sort == value)
                  Icon(Icons.check_rounded, size: 17, color: v.accent),
              ],
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sort_rounded, size: 17, color: v.muted),
            const SizedBox(width: 8),
            Text(
              librarySortText(context, value),
              style: TextStyle(fontSize: 12, color: v.ink),
            ),
            const SizedBox(width: 6),
            Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: v.muted),
          ],
        ),
      ),
    );
  }
}
