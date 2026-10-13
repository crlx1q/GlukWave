// Re-send the same intent while a server job prepares audio/imports. Ordinary
// controls still complete immediately; retries cannot duplicate a transfer.
export async function actionRequest(url:string,init:RequestInit,fetcher:typeof fetch=fetch,sleep?:(ms:number)=>Promise<void>):Promise<Response>{
  const headers=new Headers(init.headers);
  headers.set('X-GlukWave-Command-Wait','poll');
  let requestId='';try{requestId=JSON.parse(String(init.body||'{}')).requestId||'';}catch{}
  headers.set('X-GlukWave-Intent',/^[\w-]{8,100}$/.test(requestId)?requestId:crypto.randomUUID());
  const deadline=Date.now()+300000;let retries=0;
  const delay=(ms:number)=>new Promise<void>((resolve,reject)=>{
    const abort=()=>{clearTimeout(timer);reject(new DOMException('Aborted','AbortError'));};
    const timer=setTimeout(()=>{init.signal?.removeEventListener('abort',abort);resolve();},ms);
    if(init.signal?.aborted)abort();else init.signal?.addEventListener('abort',abort,{once:true});
  });
  while(true){
    init.signal?.throwIfAborted();
    if(Date.now()>=deadline)throw new Error('Action did not complete');
    const request=new AbortController(),abort=()=>request.abort(init.signal?.reason);
    init.signal?.addEventListener('abort',abort,{once:true});
    const timer=setTimeout(()=>request.abort(),15000);
    try{
      const response=await fetcher(url,{...init,headers,signal:request.signal});
      if(response.status!==202 && !(response.status>=502&&response.status<=504&&retries++<2))return response;
      await response.body?.cancel();
    }catch(error){if(init.signal?.aborted||retries++>=2)throw error;}
    finally{clearTimeout(timer);init.signal?.removeEventListener('abort',abort);}
    await (sleep||delay)(1000);
  }
}
