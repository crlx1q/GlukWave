import { useEffect, useState, useSyncExternalStore, type RefObject } from 'react';

const documentListeners=new Set<()=>void>();
const documentSnapshot=()=>!document.hidden;
function documentChanged(){document.documentElement.dataset.visuals=document.hidden?'paused':'visible';for(const listener of documentListeners)listener();}
function subscribeDocument(listener:()=>void){
 if(!documentListeners.size){document.addEventListener('visibilitychange',documentChanged);documentChanged();}
 documentListeners.add(listener);
 return()=>{documentListeners.delete(listener);if(!documentListeners.size)document.removeEventListener('visibilitychange',documentChanged);};
}

/** Decorative work follows visibility. Playback is deliberately independent. */
export function useDocumentVisible(){
 return useSyncExternalStore(subscribeDocument,documentSnapshot,()=>true);
}

export function useVisualVisibility<T extends Element>(ref:RefObject<T|null>,enabled=true){
 const documentVisible=useDocumentVisible(),[inView,setInView]=useState(false);
 useEffect(()=>{const element=ref.current;if(!element||!enabled){setInView(false);return;}const observer=new IntersectionObserver(entries=>setInView(entries[0]?.isIntersecting||false));observer.observe(element);return()=>observer.disconnect();},[ref,enabled]);
 return enabled&&documentVisible&&inView;
}
