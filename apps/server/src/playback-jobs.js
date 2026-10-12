import {HttpError} from './util.js';

// Slow extraction outlives an edge HTTP request, never the bounded job table.
// Keys are session-scoped because issued HLS grants belong to one session.
export function createPlaybackJobs({waitMs=7000,ttlMs=30000,limit=32}={}) {
  const jobs=new Map(); let closed=false;
  async function wait(key,operation){
    const now=Date.now();
    for(const [id,job] of jobs)if(job.done&&job.expiresAt<=now)jobs.delete(id);
    let job=jobs.get(key);
    if(!job){
      if(closed||jobs.size>=limit)throw new HttpError(503,'EXTRACTOR_BUSY','Музыка загружается. Повтори чуть позже.');
      job={done:false};jobs.set(key,job);
      job.task=Promise.resolve().then(operation).then(value=>{job.value=value;},error=>{job.error=error;}).finally(()=>{job.done=true;job.expiresAt=Date.now()+(job.error?500:ttlMs);});
    }
    let timer;
    try{if(!job.done)await Promise.race([job.task,new Promise(resolve=>{timer=setTimeout(resolve,waitMs);timer.unref?.();})]);}
    finally{clearTimeout(timer);}
    if(!job.done)return {pending:true,retryAfter:2};
    if(job.error)throw job.error;
    // Keep the promise just long enough to deliver it to concurrent polls.
    // A later explicit replay or URL renewal gets a fresh descriptor.
    job.expiresAt=Math.min(job.expiresAt,Date.now()+250);
    return {playback:job.value};
  }
  return {wait,close(){closed=true;jobs.clear();}};
}
