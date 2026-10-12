import {useEffect,useRef,type ComponentProps} from 'react';
import {RangeInput} from './range-input';
import {useStore} from './store';
/** Preview appearance throughout a gesture, then send its one final settings patch. */
export function SettingsRange(props:ComponentProps<typeof RangeInput>){
 const store=useStore(),release=useRef<(()=>void)|null>(null),timer=useRef<ReturnType<typeof setTimeout>|undefined>(undefined),held=useRef(false);
 const finish=()=>{clearTimeout(timer.current);timer.current=undefined;held.current=false;release.current?.();release.current=null;},begin=()=>{clearTimeout(timer.current);timer.current=undefined;if(!release.current)release.current=store.beginSettingsEdit();};
 useEffect(()=>{const end=()=>{if(held.current)finish();};window.addEventListener('pointerup',end);window.addEventListener('pointercancel',end);return()=>{window.removeEventListener('pointerup',end);window.removeEventListener('pointercancel',end);finish();};},[]);
 return <RangeInput {...props} onPointerDown={event=>{held.current=true;begin();props.onPointerDown?.(event);}} onPointerUp={event=>{finish();props.onPointerUp?.(event);}} onPointerCancel={event=>{finish();props.onPointerCancel?.(event);}} onKeyDown={event=>{if(['ArrowUp','ArrowDown','ArrowLeft','ArrowRight','PageUp','PageDown','Home','End'].includes(event.key))begin();props.onKeyDown?.(event);}} onKeyUp={event=>{if(release.current&&!held.current){clearTimeout(timer.current);timer.current=setTimeout(finish,240);}props.onKeyUp?.(event);}} onBlur={event=>{finish();props.onBlur?.(event);}}/>;
}
