import {fail} from './util.js';

export const playbackRevision = 3;
export const playbackMode = 'native-audio';

// Resolve at playback time. Catalog embed metadata is never a playable fallback.
export function createPlaybackResolver(ctx) {
  const counts = {requests:0,local:0,licensed:0,soundcloud:0,unavailable:0,failed:0};
  const recent = [];
  function record(track, adapter, error) {
    const code = String(error.code || 'AUDIO_RESOLUTION_FAILED').slice(0,100);
    const upstreamStatus=Number(error.details?.upstreamStatus);
    recent.unshift({at:new Date().toISOString(),trackId:track.id,source:track.source,adapter,code,status:error.status||502,...(Number.isInteger(upstreamStatus)&&upstreamStatus>=400&&upstreamStatus<=599?{upstreamStatus}:{})});
    if(recent.length>20)recent.length=20;
    void ctx.reportError?.({platform:'server',kind:'playback',message:`Own audio resolution failed (${adapter})`,code,version:'0.1.0',route:'/tracks/:id/playback'}).catch(()=>{});
  }
  ctx.playbackDiagnostics=()=>({revision:playbackRevision,mode:playbackMode,counts:{...counts},recent:recent.map(item=>({...item})),soundcloud:ctx.soundcloudAudioStats?.()||null});
  return async (track,user,sessionId) => {
    counts.requests++;
    if(track.source==='local'&&track.playback?.kind==='audio'){counts.local++;return ctx.publicTrack(track,user).playback;}
    if(!user||!sessionId)fail(401,'AUTH_REQUIRED','Войди в GlukWave, чтобы слушать музыку.');
    const expected=await ctx.extractorExpected?.(track);
    let lastError;
    const attempt=async(adapter,operation)=>{
      try{
        const descriptor=await operation();
        if(descriptor?.kind==='audio'&&descriptor.url){counts[adapter]++;return descriptor;}
      }catch(error){lastError=error;record(track,adapter,error);}
      return null;
    };
    const extract=()=>attempt('licensed',()=>ctx.extractorPlayback?.(track,user,sessionId));
    let audio=expected?await extract():null;
    if(!audio)audio=await attempt('soundcloud',()=>ctx.soundcloudPlayback?.(track,user,sessionId));
    if(!audio&&!expected)audio=await extract();
    if(audio)return audio;
    if(lastError){counts.failed++;throw lastError;}
    counts.unavailable++;
    fail(422,'AUDIO_UNAVAILABLE','Этот трек пока недоступен для прослушивания в GlukWave. Выбери другой трек.');
  };
}
