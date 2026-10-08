import {digest} from './util.js';

export const searchText = value => String(value || '').normalize('NFKD')
  .replace(/\p{M}/gu, '').toLowerCase().replace(/[^\p{L}\p{N}]+/gu, ' ').trim();
export const lyricsSignature = track => digest(JSON.stringify([track.title, track.artist, track.album, track.duration]));
export function matchedFields(track, query, lyrics = '') {
  const words = searchText(query).split(' ').filter(Boolean);
  const fields = {title: track.title, artist: track.artist,
    album: track.album, genre: [track.genre, ...(track.tags || [])].join(' '), lyrics};
  const normalized = Object.fromEntries(Object.entries(fields).map(([key, value]) => [key, searchText(value)]));
  if (!words.length || !words.every(word => Object.values(normalized).some(value => value.includes(word)))) return [];
  return Object.entries(normalized).filter(([, value]) => words.some(word => value.includes(word))).map(([key]) => key);
}
export function artistsFromTracks(tracks, query, providerArtists = []) {
  const found = new Map();
  for (const track of tracks) {
    const artists = track.artists?.length ? track.artists : [{name: track.artist, artwork: track.artistArtwork || '', sourceUrl: track.artistUrl || ''}];
    for (const artist of artists) {
      if (!artist.name) continue;
      const key = `${track.source}:${artist.sourceId || searchText(artist.name)}`;
      const previous = found.get(key);
      found.set(key, {...artist, id: artist.id || `artist-${digest(key).slice(0,24)}`,
        name: artist.name, source: track.source, artwork: artist.artwork || previous?.artwork || '',
        trackIds: [...new Set([...(previous?.trackIds || []), track.id])]});
    }
  }
  for (const artist of providerArtists) {
    if (!artist?.name || !artist.source) continue;
    const key = `${artist.source}:${artist.sourceId || searchText(artist.name)}`;
    found.set(key, {...found.get(key), ...artist, trackIds: found.get(key)?.trackIds || []});
  }
  const words = searchText(query).split(' ').filter(Boolean);
  return [...found.values()].filter(artist => words.every(word => searchText(artist.name).includes(word)))
    .sort((a,b) => b.trackIds.length-a.trackIds.length).slice(0,12);
}
