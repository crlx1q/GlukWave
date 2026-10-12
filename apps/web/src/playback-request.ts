const cancelled=()=>new DOMException('Playback changed','AbortError');
export function abortableDelay(ms:number,signal?:AbortSignal|null):Promise<void>{
 return new Promise((resolve,reject)=>{
  if(signal?.aborted){reject(cancelled());return;}
  const abort=()=>{clearTimeout(timer);signal?.removeEventListener('abort',abort);reject(cancelled());};
  const timer=setTimeout(()=>{signal?.removeEventListener('abort',abort);resolve();},ms);
  signal?.addEventListener('abort',abort,{once:true});
 });
}
export async function playbackRequest(url:string,init:RequestInit,fetcher:typeof fetch=fetch,delay=abortableDelay):Promise<Response>{
 const deadline=Date.now()+120000;let retries=0;
 while(true){
  if(init.signal?.aborted)throw cancelled();
  if(Date.now()>=deadline)throw new Error('Audio resolution timed out');
  const timeout=AbortSignal.timeout(Math.max(1,Math.min(15000,deadline-Date.now()))),signal=init.signal?AbortSignal.any([init.signal,timeout]):timeout;
  let response:Response;
  try{response=await fetcher(url,{...init,signal});}
  catch(error){
   if(init.signal?.aborted)throw cancelled();
   if(retries++>=2||Date.now()>=deadline)throw error;
   await delay(600*retries,init.signal);continue;
  }
  if(response.status===202){
   await response.body?.cancel();
   if(Date.now()>=deadline)throw new Error('Audio resolution timed out');
   await delay(Math.min(4000,Math.max(1000,(Number(response.headers.get('Retry-After'))||2)*1000)),init.signal);continue;
  }
  if([502,503,504].includes(response.status)&&retries<2&&Date.now()<deadline){await response.body?.cancel();await delay(600*++retries,init.signal);continue;}
  return response;
 }
}
