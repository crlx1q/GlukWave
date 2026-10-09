/** Readiness must never outlive the media load that requested it. */
export function waitForPlayback(predicate:()=>boolean,signal:AbortSignal,message:string,timeout=7500,interval=100):Promise<void>{
 return new Promise((resolve,reject)=>{
  let timer:ReturnType<typeof setTimeout>|undefined;const deadline=Date.now()+timeout;
  const clear=()=>{clearTimeout(timer);signal.removeEventListener('abort',abort);};
  const abort=()=>{clear();reject(new DOMException(message,'AbortError'));};
  const check=()=>{if(signal.aborted){abort();return;}if(predicate()){clear();resolve();return;}if(Date.now()>=deadline){clear();reject(new Error(message));return;}timer=setTimeout(check,interval);};
  if(signal.aborted){abort();return;}signal.addEventListener('abort',abort,{once:true});check();
 });
}
