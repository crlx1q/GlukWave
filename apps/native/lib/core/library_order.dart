import 'models.dart';

/// Map presence is the new server's newest-first marker, including empty maps.
List<String> orderedLikeIds(Json value) {
  final ids = List<String>.from(value['likedIds'] ?? []).toSet().toList();
  return value.containsKey('likedAt') ? ids : ids.reversed.toList();
}

const trackSorts = [
  'recent',
  'oldest',
  'title',
  'artist',
  'duration',
  'original',
];

List<WaveTrack> sortedTracks(
  List<WaveTrack> original,
  String sort,
  List<WaveTrack> recent,
) {
  if (sort == 'original') return [...original];
  if (sort == 'recent') return [...recent];
  if (sort == 'oldest') return recent.reversed.toList();
  final positions = {
    for (var i = 0; i < original.length; i++) original[i].id: i,
  };
  return [...original]..sort((a, b) {
    final compared = sort == 'duration'
        ? a.duration.compareTo(b.duration)
        : (sort == 'artist' ? a.artist : a.title).toLowerCase().compareTo(
            (sort == 'artist' ? b.artist : b.title).toLowerCase(),
          );
    return compared != 0
        ? compared
        : positions[a.id]!.compareTo(positions[b.id]!);
  });
}

List<WaveTrack> byRecentDates(List<WaveTrack> tracks, Json dates) {
  final fallback = tracks.reversed.toList(),
      index = {
        for (var i = 0; i < tracks.length; i++)
          tracks[tracks.length - 1 - i].id: i,
      };
  final stamps = {
    for (final track in fallback)
      track.id:
          DateTime.tryParse(
            dates[track.id]?.toString() ?? '',
          )?.millisecondsSinceEpoch ??
          0,
  };
  return fallback..sort(
    (a, b) => stamps[b.id]! - stamps[a.id]! != 0
        ? stamps[b.id]! - stamps[a.id]!
        : index[a.id]! - index[b.id]!,
  );
}
