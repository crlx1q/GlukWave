import {HttpError} from './util.js';

// Slow user actions survive an edge request. A stable intent key prevents
// repeated polls from repeating the mutation; accounts never share results.
export function createActionJobs({waitMs=6000,ttlMs=300000,limit=64}={}) {
  const jobs=new Map();let closed=false;
  async function wait(key,work){
    for(const [id,job] of jobs)if(job.done&&job.expiresAt<=Date.now())jobs.delete(id);
    let job=jobs.get(key);
    if(!job){
      if(closed||jobs.size>=limit)throw new HttpError(503,'ACTION_BUSY','Действие ещё выполняется. Попробуй позже.');
      job={done:false};jobs.set(key,job);
      job.task=Promise.resolve().then(work).then(value=>{job.value=value;},error=>{job.error=error;}).finally(()=>{job.done=true;job.expiresAt=Date.now()+ttlMs;});
    }
    let timer;
    try{if(!job.done)await Promise.race([job.task,new Promise(resolve=>{timer=setTimeout(resolve,waitMs);timer.unref?.();})]);}finally{clearTimeout(timer);}
    if(!job.done)return {pending:true,retryAfter:1};
    if(job.error)throw job.error;
    return {...job.value,pending:false};
  }
  return {wait,close(){closed=true;jobs.clear();},stats:()=>({jobs:jobs.size,pending:[...jobs.values()].filter(job=>!job.done).length})};
}
