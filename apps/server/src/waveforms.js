import {spawn} from 'node:child_process';
import {pipeline} from 'node:stream/promises';
import ffmpeg from 'ffmpeg-static';
import {asyncRoute,fail,digest} from './util.js';
import {soundcloudWaveformUrl} from './soundcloud-public.js';

const maxSamples=4096,rate=4000,maxBytes=128*1024*1024;
const unavailable=duration=>({available:false,duration,samples:[],source:null});

export function soundcloudEnvelope(value){
  if(!value||!Array.isArray(value.samples)||!value.samples.length||value.samples.length>20000||!Number.isFinite(value.height)||value.height<=0||value.height>100000)return null;
  if(value.samples.some(sample=>!Number.isFinite(sample)||sample<0||sample>100000))return null;
  const count=Math.min(maxSamples,value.samples.length),samples=[];
  for(let index=0;index<count;index++){
    const start=Math.floor(index*value.samples.length/count),end=Math.max(start+1,Math.floor((index+1)*value.samples.length/count));let peak=0;
    for(let cursor=start;cursor<end;cursor++)peak=Math.max(peak,value.samples[cursor]);
    samples.push(Number(Math.min(1,peak/value.height).toFixed(4)));
  }
  return samples;
}

export async function readSoundcloudEnvelope(value,fetcher=fetch){
  const url=soundcloudWaveformUrl(value);if(!url)fail(400,'WAVEFORM_URL','Форма звука недоступна.');
  const response=await fetcher(url,{redirect:'manual',signal:AbortSignal.timeout(8000),headers:{Accept:'application/json'}});
  if(!response.ok||!response.headers.get('content-type')?.includes('json')){await response.body?.cancel();return null;}
  if(Number(response.headers.get('content-length'))>256*1024){await response.body?.cancel();return null;}
  const reader=response.body.getReader(),chunks=[];let size=0;
  try{for(;;){const {done,value}=await reader.read();if(done)break;size+=value.length;if(size>256*1024)return null;chunks.push(Buffer.from(value));}}
  finally{await reader.cancel().catch(()=>{});}
  try{return soundcloudEnvelope(JSON.parse(Buffer.concat(chunks).toString('utf8')));}catch{return null;}
}

// The input is a protected local/R2 stream, never a user-supplied URL or shell command.
export async function decodeAudioEnvelope(readable,duration,{binary=ffmpeg,timeout=30000}={}){
  if(!binary||!Number.isFinite(duration)||duration<=0){readable.destroy();return null;}
  const bins=Math.min(maxSamples,Math.max(32,Math.ceil(duration*20))),squares=new Float64Array(bins),counts=new Uint32Array(bins);
  const child=spawn(binary,['-hide_banner','-loglevel','error','-nostdin','-threads','1','-protocol_whitelist','file,pipe','-i','pipe:0','-map','0:a:0','-vn','-sn','-dn','-ac','1','-ar',String(rate),'-f','f32le','pipe:1'],{stdio:['pipe','pipe','pipe'],windowsHide:true});
  let failure=false,bytes=0,position=0,remainder=Buffer.alloc(0);
  const timer=setTimeout(()=>{failure=true;readable.destroy();child.kill();},timeout);timer.unref();
  const finished=new Promise(resolve=>{child.once('error',()=>{failure=true;resolve(false);});child.once('close',code=>resolve(code===0&&!failure));});
  child.stderr.resume();
  const input=pipeline(readable,child.stdin).catch(()=>{failure=true;child.kill();});
  try{
    for await(const data of child.stdout){
      bytes+=data.length;if(bytes>maxBytes){failure=true;child.kill();break;}
      const chunk=remainder.length?Buffer.concat([remainder,data]):data,aligned=chunk.length-chunk.length%4;
      for(let offset=0;offset<aligned;offset+=4){const sample=chunk.readFloatLE(offset),bin=Math.min(bins-1,Math.floor(position++/(rate*duration)*bins));if(Number.isFinite(sample)){squares[bin]+=sample*sample;counts[bin]++;}}
      remainder=chunk.subarray(aligned);
    }
    const success=await finished;await input;if(!success||!position)return null;
    return [...squares].map((sum,index)=>Number(Math.min(1,Math.sqrt(sum/Math.max(1,counts[index]))).toFixed(4)));
  }catch{failure=true;child.kill();return null;}
  finally{clearTimeout(timer);readable.destroy();child.stdin.destroy();child.stdout.destroy();}
}

export function setupWaveforms(app,ctx){
  const pending=new Map(),queue=[];let active=0;
  async function limited(operation){if(queue.length>=20)fail(503,'WAVEFORM_BUSY','Попробуй ещё раз через минуту.');if(active>=2)await new Promise(resolve=>queue.push(resolve));else active++;try{return await operation();}finally{if(queue.length)queue.shift()();else active--;}}
  async function envelope(track){
    const fingerprint=digest([track.id,track.mediaKey,track.size,track.waveformUrl,track.duration].join(':'));
    const cached=await ctx.store.get('waveforms',track.id);if(cached?.fingerprint===fingerprint&&cached.expiresAt>Date.now())return cached.data;
    if(pending.has(fingerprint))return pending.get(fingerprint);
    const task=limited(async()=>{
      let samples=null,source=null,duration=track.duration;
      try{
        if(track.source==='local'){samples=await decodeAudioEnvelope(await ctx.openAudioStream(track),track.duration);source='decoded-pcm';}
        else if(track.source==='soundcloud'){
          const metadata=track.waveformUrl?track:await ctx.publicSoundcloudTrack(track.sourceUrl),url=track.waveformUrl||metadata.waveform_url;
          if(!duration&&metadata.duration)duration=metadata.duration/1000;
          if(url)samples=await readSoundcloudEnvelope(url);source='soundcloud-envelope';
        }
      }catch(error){ctx.log.warn({trackId:track.id,message:error.message},'Waveform unavailable');}
      const data=samples?{available:true,duration,samples,source}:unavailable(duration);
      if(await ctx.store.get('tracks',track.id))await ctx.store.put('waveforms',track.id,{id:track.id,fingerprint,data,expiresAt:Date.now()+(samples?7*86400000:60000)});
      return data;
    });
    pending.set(fingerprint,task);try{return await task;}finally{pending.delete(fingerprint);}
  }
  app.get('/api/tracks/:id/waveform',asyncRoute(async(req,res)=>{
    const track=await ctx.requireTrack(req.params.id,req.auth?.user),data=await envelope(track);
    await ctx.requireTrack(req.params.id,req.auth?.user);
    res.set('Cache-Control',track.public?'public, max-age=3600':'private, no-store').json(data);
  }));
}
