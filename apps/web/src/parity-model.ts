import type { Artist, Playlist, Settings, SettingsPatch } from './types';

/** Provider IDs are scoped by source. A display name is never an identity. */
export const artistKey=(artist:Artist)=>`${artist.source}:${artist.id}`;
export function toggleArtist(selected:Artist[],artist:Artist):Artist[]{return selected.some(item=>artistKey(item)===artistKey(artist))?selected.filter(item=>artistKey(item)!==artistKey(artist)):[...selected,artist];}
export function playlistCovers(playlist:Playlist){return [...new Set((playlist.coverArtworks||[]).filter(Boolean))].slice(0,4);}
export function advancedSettingsChange(patch:SettingsPatch,current:Settings){
  if(patch.fontFamily!==undefined&&patch.fontFamily!==current.fontFamily)return true;
  const appearance=patch.appearance;if(!appearance)return false;
  for(const [key,value]of Object.entries(appearance)){
    if(key==='light'||key==='dark'||key==='amoled'){
      for(const [color,next]of Object.entries(value||{}))if(color!=='accent'&&next!==current.appearance[key][color as 'bg'|'surface'|'ink'|'accent'])return true;
    }else if(value!==current.appearance[key as keyof typeof current.appearance])return true;
  }
  return false;
}
export const recommendationMood=(mood:string)=>mood==='calm'?'relax':mood==='night'?'dream':mood;
