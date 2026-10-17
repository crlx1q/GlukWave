/** Coalesce only provider lookups. Permission-filtered local responses stay live. */
export function providerSearchCache({ttl=30000,limit=128,now=Date.now}={}) {
 const entries=new Map();
 return async function lookup(key,read) {
  let entry=entries.get(key);
  if(entry?.job)return structuredClone(await entry.job);
  if(entry&&now()-entry.at<ttl&&entry.value)return structuredClone(entry.value);
  entry={at:now()};entries.delete(key);entries.set(key,entry);
  while(entries.size>limit)entries.delete(entries.keys().next().value);
  entry.job=Promise.resolve().then(read).then(value=>{entry.value=structuredClone(value);entry.at=now();entry.job=null;return value;},error=>{if(entries.get(key)===entry)entries.delete(key);throw error;});
  return structuredClone(await entry.job);
 };
}

/** Optional first paint: slow providers finish into the shared lookup cache. */
export async function searchSnapshot(jobs,budgetMs) {
 if(budgetMs===undefined)return Promise.allSettled(jobs);
 const results=jobs.map(()=>({status:'pending'}));
 const complete=Promise.all(jobs.map((job,index)=>Promise.resolve(job).then(value=>{results[index]={status:'fulfilled',value};},reason=>{results[index]={status:'rejected',reason};})));
 let timer;try{await Promise.race([complete,new Promise(resolve=>{timer=setTimeout(resolve,budgetMs);})]);}finally{clearTimeout(timer);}
 return results.map(result=>({...result}));
}
