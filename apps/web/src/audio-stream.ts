import type HlsType from 'hls.js';
/** One audio element owns decoding, EQ, MediaSession and queue completion.
 * A provider HLS stream is playable, not an offline download permission. */
export class AudioStreamLoader {
 private hls:HlsType|null=null;private generation=0;private abort:AbortController|null=null;
 destroy(audio?:HTMLAudioElement){
  this.generation++;this.abort?.abort();this.abort=null;
  if(this.hls){this.hls.destroy();this.hls=null;}
  if(audio){audio.removeAttribute('src');audio.load();}
 }
 async attach(audio:HTMLAudioElement,url:string,format:'hls'|undefined,signal:AbortSignal,onFatal:(error:Error)=>void){
  this.destroy(audio);const generation=this.generation,scope=new AbortController();this.abort=scope;
  const onAbort=()=>{if(generation===this.generation)this.destroy(audio);};signal.addEventListener('abort',onAbort,{once:true});
  const stale=()=>signal.aborted||scope.signal.aborted||generation!==this.generation;
  const active=()=>{if(stale())throw new DOMException('Playback changed','AbortError');};
  try{
   active();
   if(format==='hls'){
    const {default:Hls}=await import('hls.js');active();
    if(Hls.isSupported()){
     audio.removeAttribute('src');audio.load();
     const hls=new Hls({enableWorker:true,lowLatencyMode:false,maxBufferLength:24,maxMaxBufferLength:48,backBufferLength:12,maxBufferSize:24*1024*1024});
     this.hls=hls;
     let networkRetries=0,mediaRetries=0;
     await new Promise<void>((resolve,reject)=>{let ready=false,settled=false;const timeout=setTimeout(()=>fail(Error('Audio stream did not respond. Try again.')),15000);
      const cancelled=()=>{clearTimeout(timeout);if(!settled){settled=true;reject(new DOMException('Playback changed','AbortError'));}};
      const clean=()=>{clearTimeout(timeout);scope.signal.removeEventListener('abort',cancelled);};
      const fail=(error:Error)=>{if(stale())return;if(!ready){if(!settled){settled=true;clean();hls.destroy();if(this.hls===hls)this.hls=null;reject(error);}}else{hls.destroy();if(this.hls===hls)this.hls=null;onFatal(error);}};
      scope.signal.addEventListener('abort',cancelled,{once:true});
      hls.on(Hls.Events.MANIFEST_PARSED,()=>{if(stale())return;ready=true;settled=true;clean();resolve();});
      hls.on(Hls.Events.ERROR,(_,data)=>{if(stale()||!data.fatal)return;if(data.type===Hls.ErrorTypes.NETWORK_ERROR&&networkRetries++<2){hls.startLoad();return;}if(data.type===Hls.ErrorTypes.MEDIA_ERROR&&mediaRetries++<1){hls.recoverMediaError();return;}fail(Error('Audio stream interrupted. Select the track again to retry.'));});
      hls.on(Hls.Events.MEDIA_ATTACHED,()=>{if(!stale())hls.loadSource(url);});
      hls.attachMedia(audio);
     });active();
     return;
    }
    if(audio.canPlayType('application/vnd.apple.mpegurl')){audio.src=url;return;}
    throw Error('This browser cannot play this audio stream.');
   }
   audio.src=url;
  }finally{signal.removeEventListener('abort',onAbort);}
 }
}
