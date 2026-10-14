import {useEffect,useLayoutEffect,useRef,useState,type PointerEvent} from 'react';
import {GripVertical,Plus,Search,X,Check} from 'lucide-react';
import {api} from './api';
import {t,useLocale} from './locale';
import {usePlayer} from './player';
import {useStore} from './store';
import {type Track,trackCount} from './types';
import {Art,Empty,IconButton,Loading} from './ui';

export function QueuePanel(){
 useLocale();const player=usePlayer(),store=useStore(),canControl=!player.room||store.user?.role==='admin'||player.room.canControl===true||player.room.ownerId===store.user?.id||!!player.room.members.find(member=>member.userId===store.user?.id)?.canControl;
 const [rows,setRows]=useState(player.queue),[leaving,setLeaving]=useState<string[]>([]),[dragging,setDragging]=useState<string|null>(null),[picker,setPicker]=useState(false);
 const list=useRef<HTMLDivElement>(null),positions=useRef(new Map<string,number>()),animations=useRef(new Map<string,Animation>()),wasLeaving=useRef(false),draft=useRef(player.queue),authoritative=useRef(player.queue),suppressed=useRef(false),drag=useRef<{id:string;pointer:number;startY:number;active:boolean;timer:ReturnType<typeof setTimeout>|undefined;original:Track[];element:HTMLElement}|null>(null);
 authoritative.current=player.queue;
 useEffect(()=>{if(drag.current)return;draft.current=player.queue;const removed=rows.filter(row=>!player.queue.some(item=>item.id===row.id));if(!removed.length){setRows(player.queue);setLeaving([]);return;}setLeaving(removed.map(item=>item.id));setRows(current=>{const next=[...player.queue];for(const item of removed){const old=current.findIndex(row=>row.id===item.id);next.splice(Math.min(old,next.length),0,item);}return next;});const timer=setTimeout(()=>{setRows(player.queue);setLeaving([]);},store.motion?240:0);return()=>clearTimeout(timer);},[player.queue,store.motion]);
 useLayoutEffect(()=>{
  const nodes=Array.from(list.current?.querySelectorAll<HTMLElement>('[data-queue-id]')||[]),next=new Map<string,number>(),collapsing=leaving.length>0||wasLeaving.current;
  for(const node of nodes){
   const id=node.dataset.queueId!,top=node.parentElement!.offsetTop,previous=positions.current.get(id),animation=animations.current.get(id);
   // Read only this row's remaining visual offset, then replace its animation.
   // Viewport rectangles include scrolling and previous animations, so they
   // cannot be used as the next layout's baseline or drag hit boxes.
   const transform=animation?getComputedStyle(node).transform:'none',offset=transform==='none'?0:new DOMMatrixReadOnly(transform).m42;
   animation?.cancel();animations.current.delete(id);next.set(id,top);
   const delta=(previous??top)+offset-top;
   if(store.motion&&typeof node.animate==='function'&&document.documentElement.dataset.browserProfile!=='tv-legacy'&&!collapsing&&previous!==undefined&&Math.abs(delta)>1&&id!==dragging){const active=node.animate([{transform:`translateY(${delta}px)`},{transform:'translateY(0)'}],{duration:200,easing:'cubic-bezier(.2,.8,.2,1)'});animations.current.set(id,active);active.onfinish=()=>{if(animations.current.get(id)===active)animations.current.delete(id);};}
  }
  for(const [id,animation] of animations.current)if(!next.has(id)){animation.cancel();animations.current.delete(id);}
  positions.current=next;wasLeaving.current=leaving.length>0;
 },[rows,leaving,store.motion,dragging]);
 useEffect(()=>()=>{clearTimeout(drag.current?.timer);for(const animation of animations.current.values())animation.cancel();},[]);
 const activate=()=>{const current=drag.current;if(!current)return;current.active=true;current.element.setPointerCapture(current.pointer);suppressed.current=true;setDragging(current.id);};
 const start=(event:PointerEvent<HTMLElement>,track:Track,handle=false)=>{if(!canControl||leaving.includes(track.id)||event.button!==0||(!handle&&event.pointerType==='mouse'))return;if(!handle&&(event.target as HTMLElement).closest('.queue-remove'))return;event.stopPropagation();if(handle)event.preventDefault();const current={id:track.id,pointer:event.pointerId,startY:event.clientY,active:false,timer:undefined as ReturnType<typeof setTimeout>|undefined,original:[...player.queue],element:event.currentTarget};drag.current=current;draft.current=[...player.queue];if(event.pointerType==='mouse')activate();else current.timer=setTimeout(activate,280);};
 const move=(event:PointerEvent<HTMLElement>)=>{
  const current=drag.current;if(!current||current.pointer!==event.pointerId)return;event.stopPropagation();
  if(!current.active){if(Math.abs(event.clientY-current.startY)>9){clearTimeout(current.timer);drag.current=null;}return;}
  event.preventDefault();const root=list.current;if(!root)return;const y=event.clientY-root.getBoundingClientRect().top;
  const nodes=Array.from(root.querySelectorAll<HTMLElement>('[data-queue-id]')),from=draft.current.findIndex(row=>row.id===current.id);
  let to=from;
  for(const node of nodes){const index=draft.current.findIndex(row=>row.id===node.dataset.queueId),slot=node.parentElement!,middle=slot.offsetTop+slot.offsetHeight/2;
   if(index<from&&y<middle){to=index;break;}if(index>from&&y>middle)to=index;
  }
  if(from<0||to===from)return;const next=[...draft.current],[item]=next.splice(from,1);next.splice(to,0,item);draft.current=next;setRows(next);
 };
 const end=(event:PointerEvent<HTMLElement>,cancel=false)=>{const current=drag.current;if(!current||current.pointer!==event.pointerId)return;event.stopPropagation();clearTimeout(current.timer);drag.current=null;setDragging(null);if(event.currentTarget.hasPointerCapture(event.pointerId))event.currentTarget.releasePointerCapture(event.pointerId);if(cancel){draft.current=player.queue;setRows(player.queue);suppressed.current=false;return;}if(current.active&&draft.current.some((track,index)=>track.id!==current.original[index]?.id))void store.run(async()=>{try{await player.setQueue(draft.current);}catch(error){draft.current=authoritative.current;setRows(authoritative.current);throw error;}});setTimeout(()=>{suppressed.current=false;},0);};
 const play=(item:Track)=>{if(suppressed.current)return;void player.playTrack(item,player.queue,player.waveActive?'wave':undefined);};
 return <section className="np-queue queue-editor"><div className="section-heading"><div><h2>{t('copy.670')}</h2><span className="muted">{trackCount(player.queue.length)}</span></div><IconButton title={t('ecosystem.queueAdd')} className={`icon-btn queue-add ${picker?'selected':''}`} aria-expanded={picker} disabled={!canControl} onClick={()=>setPicker(!picker)}><Plus size={20}/></IconButton></div>{picker&&<QueuePicker/>}<p className="queue-help">{t(canControl?'ecosystem.queueDrag':'v7.rooms.listenOnly')}</p><div ref={list} className="queue-rows">{rows.length?rows.map((item,index)=><div className={`queue-slot ${leaving.includes(item.id)?'is-leaving':''}`} key={item.id}><div className={`queue-row ${item.id===player.track?.id?'is-current':''} ${dragging===item.id?'is-dragging':''}`} data-queue-id={item.id} onPointerDown={event=>start(event,item)} onPointerMove={move} onPointerUp={event=>end(event)} onPointerCancel={event=>end(event,true)}>
 <IconButton title={t('ecosystem.queueMove',{track:item.title})} className="icon-btn queue-grip" disabled={!canControl} onPointerDown={event=>start(event,item,true)} onPointerMove={move} onPointerUp={event=>end(event)} onPointerCancel={event=>end(event,true)} onKeyDown={event=>{if(!canControl||!['ArrowUp','ArrowDown'].includes(event.key))return;event.preventDefault();const to=Math.min(rows.length-1,Math.max(0,index+(event.key==='ArrowUp'?-1:1)));if(to!==index)void store.run(()=>player.moveQueue(index,to));}}><GripVertical size={16}/></IconButton>
 <Art track={item} onClick={()=>play(item)}/><button className="track-main" onClick={()=>play(item)}><b>{item.title}</b><small>{item.artist}</small></button><IconButton className="icon-btn queue-remove" title={t('copy.671')} disabled={!canControl||leaving.includes(item.id)} onClick={()=>void store.run(()=>player.removeQueue(item.id))}><X size={17}/></IconButton></div></div>):<Empty title={t('ecosystem.queueEmpty')}/>}</div></section>;
}
function QueuePicker(){
 const player=usePlayer(),store=useStore(),[query,setQuery]=useState(''),[tracks,setTracks]=useState<Track[]>(store.library.tracks.slice(0,8)),[loading,setLoading]=useState(false),[error,setError]=useState(''),[pending,setPending]=useState<string|null>(null);
 useEffect(()=>{const q=query.trim();setError('');if(q.length<2){setLoading(false);setTracks(store.library.tracks.slice(0,8));return;}const controller=new AbortController();setLoading(true);const timer=setTimeout(()=>{void api<{tracks:Track[]}>(`/search?q=${encodeURIComponent(q)}&source=all`,{signal:controller.signal}).then(result=>{if(!controller.signal.aborted)setTracks(result.tracks||[]);}).catch(()=>{if(!controller.signal.aborted){setError(t('ecosystem.queueSearchError'));setTracks([]);}}).finally(()=>{if(!controller.signal.aborted)setLoading(false);});},280);return()=>{clearTimeout(timer);controller.abort();};},[query,store.library.tracks]);
 return <div className="queue-picker"><label><Search size={15}/><input value={query} onChange={event=>setQuery(event.target.value)} placeholder={t('ecosystem.queueSearch')} aria-label={t('ecosystem.queueSearch')}/></label>{loading?<Loading/>:error?<p role="alert">{error}</p>:<div className="queue-picker-results">{tracks.map(track=>{const queued=player.queue.some(row=>row.id===track.id);return <button key={track.id} disabled={queued||pending!==null} onClick={()=>{setPending(track.id);void store.run(()=>player.addQueue(track)).finally(()=>setPending(null));}}><Art track={track}/><span><b>{track.title}</b><small>{track.artist}</small></span>{queued?<Check size={16}/>:pending===track.id?<i className="loader"/>:<Plus size={16}/>}</button>;})}{!tracks.length&&<p>{t('ecosystem.queueEmptySearch')}</p>}</div>}</div>;
}
