import type {Library, Playlist, Track} from './types';
import {normalizeLibraryOrder} from './library-order.ts';

type Edit = {key:string; apply:(library:Library)=>Library};
export const replacePlaylist=(library:Library,playlist:Playlist):Library=>{const addedAt={...library.addedAt};for(const id of playlist.trackIds){if(!addedAt[id]&&playlist.trackAddedAt?.[id])addedAt[id]=playlist.trackAddedAt[id];}return {...library,addedAt,playlists:library.playlists.some(item=>item.id===playlist.id)?library.playlists.map(item=>item.id===playlist.id?playlist:item):[playlist,...library.playlists]};};
export const rememberTrack=(library:Library,track:Track):Library=>({...library,tracks:library.tracks.some(item=>item.id===track.id)?library.tracks: [...library.tracks,track]});
export const setLiked=(library:Library,id:string,liked:boolean,at?:string|null):Library=>{const dates={...library.likedAt};if(liked){if(at)dates[id]=at;else if(at===null)delete dates[id];}else delete dates[id];const addedAt={...library.addedAt};if(liked&&at&&!addedAt[id])addedAt[id]=at;return {...library,likedAt:dates,addedAt,likedIds:liked?(library.likedIds.includes(id)?library.likedIds:[id,...library.likedIds]):library.likedIds.filter(value=>value!==id)};};
export const mergePlaylistCover=(library:Library,playlist:Playlist):Library=>{const previous=library.playlists.find(value=>value.id===playlist.id);return previous?replacePlaylist(library,{...previous,artwork:playlist.artwork,coverArtworks:playlist.coverArtworks}):library;};

/** Pending intentions are overlays, so a failed earlier request cannot undo a later click. */
export class LibraryEdits {
  private base:Library;
  private edits=new Map<number,Edit>();
  private tails=new Map<string,Promise<unknown>>();
  private next=0;
  private generation=0;
  revision=0;
  scope:string|null=null;
  get pending(){return this.edits.size>0;}
  get confirmed(){return this.base;}
  private changed:(library:Library,saving:string[])=>void;
  constructor(initial:Library,changed:(library:Library,saving:string[])=>void){this.base=normalizeLibraryOrder(initial);this.changed=changed;}
  get value(){let value=this.base;for(const edit of this.edits.values())value=edit.apply(value);return value;}
  private publish(){this.changed(this.value,[...new Set([...this.edits.values()].map(edit=>edit.key))]);}
  reset(scope:string|null,library:Library){this.generation++;this.revision++;this.scope=scope;this.base=normalizeLibraryOrder(library);this.edits.clear();this.tails.clear();this.publish();}
  snapshot(library:Library,revision:number){if(revision!==this.revision)return false;this.base=normalizeLibraryOrder(library);this.publish();return true;}
  accept(change:(library:Library)=>Library){this.revision++;this.base=change(this.base);this.publish();}
  mutate<T>(key:string,apply:Edit['apply'],request:()=>Promise<T>,commit:(library:Library,result:T)=>Library):Promise<T>{
    const id=++this.next,generation=this.generation;
    this.revision++;this.edits.set(id,{key,apply});this.publish();
    const previous=this.tails.get(key)||Promise.resolve();
    const task=previous.catch(()=>{}).then(async()=>{
      if(generation!==this.generation)throw new DOMException('Account changed','AbortError');
      try{
        const result=await request();
        if(generation!==this.generation)throw new DOMException('Account changed','AbortError');
        this.base=commit(this.base,result);return result;
      }finally{
        if(generation===this.generation){this.revision++;this.edits.delete(id);this.publish();}
      }
    });
    const tail=task.catch(()=>{});this.tails.set(key,tail);
    void tail.then(()=>{if(this.tails.get(key)===tail)this.tails.delete(key);});
    return task;
  }
}

export function playlistMembership(playlist:Playlist,ids:string[],at:string):Playlist{
 const prior=new Set(playlist.trackIds),dates={...playlist.trackAddedAt};for(const id of Object.keys(dates))if(!ids.includes(id))delete dates[id];for(const id of ids)if(!prior.has(id))dates[id]=at;return {...playlist,trackIds:ids,trackAddedAt:dates};
}
