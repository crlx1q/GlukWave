import type {Library,Track} from './types';

export type TrackSort='recent'|'oldest'|'title'|'artist'|'duration'|'original';
export const trackSorts:TrackSort[]=['recent','oldest','title','artist','duration','original'];
export function normalizeLibraryOrder(library:Library):Library {
 const ids=[...new Set(library.likedIds)],modern=library.likedAt!==undefined;
 return {...library,likedIds:modern?ids:ids.reverse(),likedAt:{...library.likedAt}};
}
/** Input is a view's chronological or saved order, never the catalog's order. */
export function sortTracks(tracks:Track[],sort:TrackSort,recent:Track[]):Track[]{
 if(sort==='original')return [...tracks];
 if(sort==='recent')return [...recent];
 if(sort==='oldest')return [...recent].reverse();
 const compare=typeof Intl!=='undefined'&&typeof Intl.Collator==='function'?new Intl.Collator(undefined,{numeric:true,sensitivity:'base'}):{compare:(a:string,b:string)=>a.toLocaleLowerCase().localeCompare(b.toLocaleLowerCase())};
 return tracks.map((track,index)=>({track,index})).sort((a,b)=>
  (sort==='duration'?a.track.duration-b.track.duration:compare.compare(a.track[sort],b.track[sort]))||a.index-b.index
 ).map(value=>value.track);
}
export function likedTracks(library:Library):Track[]{
 const byId=new Map(library.tracks.map(track=>[track.id,track]));
 return library.likedIds.map(id=>byId.get(id)).filter((track):track is Track=>!!track);
}

export function byRecentDates(tracks:Track[],dates:Record<string,string>={}):Track[]{
 const fallback=[...tracks].reverse(),index=new Map(fallback.map((track,i)=>[track.id,i]));
 const stamps=new Map(fallback.map(track=>{const value=Date.parse(dates[track.id]);return [track.id,Number.isFinite(value)?value:0] as const;}));
 return fallback.sort((a,b)=>stamps.get(b.id)!-stamps.get(a.id)!||index.get(a.id)!-index.get(b.id)!);
}
