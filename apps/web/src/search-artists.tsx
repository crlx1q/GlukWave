import { useState } from 'react';
import { ArrowUpRight, UserRound } from 'lucide-react';
import { t } from './locale';
import { sourceNames, type Source } from './types';
import './search-artists.css';

export type SearchArtist = {
  id: string;
  name: string;
  artwork: string;
  source: string;
  trackIds: string[];
  sourceUrl?: string;
};

function ArtistResult({ artist, onSelect }: {
  artist: SearchArtist;
  onSelect: (artist: SearchArtist) => void;
}) {
  const [failed, setFailed] = useState(false);
  return <button className="search-artist" onClick={() => onSelect(artist)}>
    <span className="search-artist-image">
      {artist.artwork && !failed
        ? <img src={artist.artwork} alt="" loading="lazy" onError={() => setFailed(true)} />
        : <UserRound size={28} aria-hidden="true" />}
    </span>
    <span className="search-artist-name"><b>{artist.name}</b>
      <small>{sourceNames[artist.source as Source] || t('search.artist')}</small>
    </span>
    <ArrowUpRight size={16} aria-hidden="true" />
  </button>;
}

export function SearchArtists({ artists, onSelect }: {
  artists: SearchArtist[];
  onSelect: (artist: SearchArtist) => void;
}) {
  if (!artists.length) return null;
  return <section className="search-artists" aria-labelledby="search-artists-heading">
    <div className="section-heading"><h2 id="search-artists-heading">{t('search.artists')}</h2></div>
    <div className="search-artists-strip">{artists.map(artist =>
      <ArtistResult key={`${artist.source}:${artist.id}`} artist={artist} onSelect={onSelect} />
    )}</div>
  </section>;
}
