import {monitorEventLoopDelay} from 'node:perf_hooks';
import {readFile} from 'node:fs/promises';
import {getHeapStatistics} from 'node:v8';
import {asyncRoute} from './util.js';

const mb=bytes=>Number((bytes/1048576).toFixed(2));
const finiteLimit=value=>{const n=Number(value);return Number.isFinite(n)&&n>0&&n<2**60?n:null;};
export async function readResourceLimits(read=path=>readFile(path,'utf8')){
  const text=async path=>{try{return (await read(path)).trim();}catch{return '';}};
  const [cpu,memory,current,pids]=await Promise.all(['cpu.max','memory.max','memory.current','pids.max'].map(name=>text('/sys/fs/cgroup/'+name)));
  let [quota,period]=cpu.split(/\s+/).map(Number),bytes=finiteLimit(memory),used=finiteLimit(current),maxPids=finiteLimit(pids);
  if(!cpu){const old=await Promise.all(['/sys/fs/cgroup/cpu/cpu.cfs_quota_us','/sys/fs/cgroup/cpu/cpu.cfs_period_us','/sys/fs/cgroup/memory/memory.limit_in_bytes','/sys/fs/cgroup/memory/memory.usage_in_bytes','/sys/fs/cgroup/pids/pids.max'].map(text));quota=Number(old[0]);period=Number(old[1]);bytes=finiteLimit(old[2]);used=finiteLimit(old[3]);maxPids=finiteLimit(old[4]);}
  const cpuCores=quota>0&&period>0?Number((quota/period).toFixed(3)):null;
  return {scope:cpuCores||bytes?'container':'unrestricted',cpuCores,memoryMB:bytes?mb(bytes):null,pidsMax:maxPids,containerMemoryMB:used?mb(used):null,heapLimitMB:mb(getHeapStatistics().heap_size_limit)};
}

export function setupResources(app,ctx){
  const histogram=monitorEventLoopDelay({resolution:20});histogram.enable();
  let previous=process.cpuUsage(),at=performance.now(),sample=null,limits=null,limitsAt=0,limitsFlight=null;
  const refreshLimits=()=>{if(limitsFlight)return limitsFlight;if(Date.now()-limitsAt<5000)return Promise.resolve();limitsFlight=readResourceLimits().then(value=>{limits=value;limitsAt=Date.now();}).finally(()=>{limitsFlight=null;});return limitsFlight;};
  const read=()=>{const elapsed=performance.now()-at;if(elapsed>=1000||!sample){const usage=process.cpuUsage(),memory=process.memoryUsage(),ready=elapsed>=1000;sample={scope:'server-process',cpuOneCorePercent:ready?Number((((usage.user-previous.user)+(usage.system-previous.system))/(elapsed*1000)*100).toFixed(2)):null,rssMB:Number((memory.rss/1048576).toFixed(2)),heapUsedMB:Number((memory.heapUsed/1048576).toFixed(2)),heapTotalMB:Number((memory.heapTotal/1048576).toFixed(2)),externalMB:Number((memory.external/1048576).toFixed(2)),eventLoopP99Ms:ready?Number((histogram.percentile(99)/1e6).toFixed(2)):null,intervalMs:Math.round(elapsed),sampledAt:new Date().toISOString()};if(ready){previous=usage;at=performance.now();histogram.reset();}}return {...sample};};
  ctx.resourceSnapshot=()=>({...read(),limits});
  const timer=setInterval(()=>{read();void refreshLimits();},5000);timer.unref();void refreshLimits();
  app.get('/api/admin/resources',ctx.requireAdmin,asyncRoute(async(_req,res)=>{await refreshLimits();res.set('Cache-Control','no-store').json({resources:ctx.resourceSnapshot(),realtime:ctx.realtimeStats?.()||null,extractors:ctx.extractorStats?.()||null,uptime:process.uptime()});}));
  ctx.closeResources=()=>{clearInterval(timer);histogram.disable();};
}
