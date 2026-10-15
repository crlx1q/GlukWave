import 'models.dart';
import 'library_order.dart';

Json copyLibrary(Json value) => {
  'tracks': objects(
    value['tracks'],
  ).map((t) => Map<String, dynamic>.from(t)).toList(),
  'likedIds': orderedLikeIds(value),
  'likedAt': object(value['likedAt']),
  'addedAt': object(value['addedAt']),
  'playlists': objects(value['playlists'])
      .map((p) => {...p, 'trackIds': List<String>.from(p['trackIds'] ?? [])})
      .toList(),
  'history': objects(value['history']),
};

class LibraryEdit {
  int revision;
  final String key, kind, id;
  final Json data;
  bool pending = true;
  LibraryEdit(this.revision, this.key, this.kind, this.id, this.data);
}

/// A bounded optimistic journal. A late snapshot retains edits made after its
/// request began; rolling back one edit cannot undo a later user's intent.
class LibraryMutations {
  Json base;
  int revision = 0;
  final List<LibraryEdit> edits = [];
  LibraryMutations(Json initial) : base = copyLibrary(initial);
  List<String> get saving =>
      edits.where((e) => e.pending).map((e) => e.key).toSet().toList();
  LibraryEdit begin(String key, String kind, String id, Json data) {
    if (edits.where((e) => e.pending).length >= 128) {
      throw StateError('Too many pending library changes');
    }
    final edit = LibraryEdit(++revision, key, kind, id, data);
    edits.add(edit);
    return edit;
  }

  void apply(Json library, LibraryEdit edit) {
    final playlists = objects(library['playlists']),
        tracks = objects(library['tracks']),
        liked = List<String>.from(library['likedIds'] ?? []),
        likedAt = object(library['likedAt']),
        addedAt = object(library['addedAt']);
    for (final track in [
      object(edit.data['track']),
      ...objects(edit.data['knownTracks']),
    ]) {
      if (track.isNotEmpty && !tracks.any((t) => t['id'] == track['id'])) {
        tracks.add(track);
      }
    }
    final at = playlists.indexWhere((p) => p['id'] == edit.id);
    switch (edit.kind) {
      case 'like':
        if (edit.data['liked'] == true) {
          if (!liked.contains(edit.id)) liked.insert(0, edit.id);
          if (edit.data['likedAt'] is String) {
            likedAt[edit.id] = edit.data['likedAt'];
            addedAt.putIfAbsent(edit.id, () => edit.data['likedAt']);
          } else if (edit.data.containsKey('likedAt')) {
            likedAt.remove(edit.id);
          }
        } else {
          liked.remove(edit.id);
          likedAt.remove(edit.id);
        }
      case 'create':
        if (!playlists.any((p) => p['id'] == edit.data['playlist']['id'])) {
          playlists.add(object(edit.data['playlist']));
        }
      case 'update':
        if (at >= 0) playlists[at] = {...playlists[at], ...edit.data};
      case 'membership':
        if (at >= 0) {
          final ids = List<String>.from(playlists[at]['trackIds'] ?? []),
              dates = object(playlists[at]['trackAddedAt']);
          if (edit.data['present'] == true) {
            if (!ids.contains(edit.data['trackId'])) {
              ids.add(edit.data['trackId'] as String);
              if (edit.data['addedAt'] is String) {
                dates[edit.data['trackId']] = edit.data['addedAt'];
              }
            }
          } else {
            ids.remove(edit.data['trackId']);
            dates.remove(edit.data['trackId']);
          }
          playlists[at] = {
            ...playlists[at],
            'trackIds': ids,
            'trackAddedAt': dates,
          };
        }
      case 'delete':
        playlists.removeWhere((p) => p['id'] == edit.id);
    }
    library['tracks'] = tracks;
    library['likedIds'] = liked;
    library['likedAt'] = likedAt;
    for (final playlist in playlists) {
      for (final entry in object(playlist['trackAddedAt']).entries) {
        addedAt.putIfAbsent(entry.key, () => entry.value);
      }
    }
    library['addedAt'] = addedAt;
    library['playlists'] = playlists;
  }

  Json get visible {
    final value = copyLibrary(base);
    for (final edit in edits.where((e) => e.pending)) {
      apply(value, edit);
    }
    return value;
  }

  void acknowledge(LibraryEdit edit, {Json? playlist}) {
    if (playlist != null && playlist.isNotEmpty) {
      final list = objects(base['playlists']);
      final at = list.indexWhere(
        (p) => p['id'] == edit.id || p['id'] == playlist['id'],
      );
      if (at < 0) {
        list.add(playlist);
      } else {
        list[at] = playlist;
      }
      base['playlists'] = list;
      final addedAt = object(base['addedAt']);
      for (final entry in object(playlist['trackAddedAt']).entries) {
        addedAt.putIfAbsent(entry.key, () => entry.value);
      }
      base['addedAt'] = addedAt;
      // Old snapshots must retain the server identity, never the temporary id.
      if (edit.kind == 'create') edit.data['playlist'] = playlist;
    } else {
      apply(base, edit);
    }
    final values = objects(base['tracks']);
    for (final track in [
      object(edit.data['track']),
      ...objects(edit.data['knownTracks']),
    ]) {
      if (track.isNotEmpty && !values.any((t) => t['id'] == track['id'])) {
        values.add(track);
      }
    }
    base['tracks'] = values;
    edit.pending = false;
    edit.revision = ++revision;
    if (edits.length > 256) {
      edits.removeWhere((e) => !e.pending && e.revision < revision - 128);
    }
  }

  void reject(LibraryEdit edit) {
    edits.remove(edit);
    revision++;
  }

  void acceptSnapshot(Json value, int began) {
    if (began != revision) return;
    base = copyLibrary(value);
    for (final edit in edits.where((e) => !e.pending && e.revision > began)) {
      apply(base, edit);
    }
    edits.removeWhere((e) => !e.pending && e.revision <= began);
  }

  void acceptPlaylist(Json playlist) {
    final list = objects(base['playlists']);
    final at = list.indexWhere((p) => p['id'] == playlist['id']);
    if (at < 0) {
      return;
    } else {
      list[at] = {
        ...list[at],
        for (final key in ['artwork', 'coverArtworks', 'customCover'])
          if (playlist.containsKey(key)) key: playlist[key],
      };
    }
    base['playlists'] = list;
    revision++;
  }
}
