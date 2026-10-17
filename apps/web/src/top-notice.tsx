import { useEffect, useRef, useState } from 'react';
import { Check, Info, X } from 'lucide-react';
import { t } from './locale';
import { useStore } from './store';

export function TopNotice(){
 const {toast}=useStore(),[dismissed,setDismissed]=useState<number|null>(null),previous=useRef<{text:string;at:number;id:number}|null>(null),[visible,setVisible]=useState<typeof toast>(null);
 useEffect(()=>{if(!toast){setVisible(null);return;}const now=Date.now();if(previous.current?.text===toast.text&&now-previous.current.at<3000)return;previous.current={text:toast.text,at:now,id:toast.id};setVisible(toast);setDismissed(null);const timer=setTimeout(()=>setVisible(null),toast.text.length>100?7000:4000);return()=>clearTimeout(timer);},[toast]);
 if(!visible||visible.id===dismissed)return null;
 return <div className={`toast top-notice ${visible.error?'error':''}`} role={visible.error?'alert':'status'} aria-live="polite">{visible.error?<Info size={18}/>:<Check size={18}/>}<span>{visible.text}</span><button type="button" aria-label={t('copy.736')} onClick={()=>setDismissed(visible.id)}><X size={16}/></button></div>;
}
