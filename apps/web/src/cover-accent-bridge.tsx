import {useEffect} from 'react';
import {useStore} from './store';
import {usePlayer} from './player';
import {mediaArtworkPath} from './media-download';
import {readCoverAccent} from './cover-accent';
export function CoverAccentBridge(){const store=useStore(),player=usePlayer(),track=player.track;useEffect(()=>{store.setCoverAccent(null);if(!store.settings.appearance.coverAccent||!track?.artwork)return;const controller=new AbortController(),key=`${store.user?.id||'guest'}:${track.id}:${track.artwork}`;void readCoverAccent(mediaArtworkPath(track.id,track.artwork,location.origin),key,controller.signal).then(tone=>{if(!controller.signal.aborted)store.setCoverAccent(tone);});return()=>controller.abort();},[track?.id,track?.artwork,store.user?.id,store.settings.appearance.coverAccent,store.setCoverAccent]);return null;}
