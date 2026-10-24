import {monitorEventLoopDelay} from 'node:perf_hooks';
import {readFile} from 'node:fs/promises';
import {getHeapStatistics} from 'node:v8';
import {z} from 'zod';
import {asyncRoute,parse,fail} from './util.js';

const mb=bytes=>Number((bytes/1048576).toFixed(2));
const finiteLimit=value=>{const n=Number(value);return Number.isFinite(n)&&n>0&&n<2**60?n:null;};
export async function readResourceLimits(read=path=>readFile(path,'utf8')){
  const text=async path=>{try{return (await read(path)).trim();}catch{return '';}};
  let basePath='/sys/fs/cgroup';
  const selfCgroup=await text('/proc/self/cgroup');
  const cgroupMatch=selfCgroup.match(/^0::(.*)$/m);
  if(cgroupMatch&&cgroupMatch[1]){
    const sub=cgroupMatch[1].replace(/^\/+|\/+$/g,'');
    if(sub){
      const candidate=`/sys/fs/cgroup/${sub}`;
      const probe=await text(candidate+'/cgroup.controllers');
      if(probe||await text(candidate+'/cpu.max')||await text(candidate+'/memory.max'))basePath=candidate;
    }
  }
  const [cpu,memory,current,pids,stat]=await Promise.all(['cpu.max','memory.max','memory.current','pids.max','cpu.stat'].map(name=>text(`${basePath}/${name}`)));
  let [quota,period]=cpu.split(/\s+/).map(Number),bytes=finiteLimit(memory),used=finiteLimit(current),maxPids=finiteLimit(pids),usage=Number(stat.match(/^usage_usec\s+(\d+)/m)?.[1]);
  if(!cpu){const old=await Promise.all(['/sys/fs/cgroup/cpu/cpu.cfs_quota_us','/sys/fs/cgroup/cpu/cpu.cfs_period_us','/sys/fs/cgroup/memory/memory.limit_in_bytes','/sys/fs/cgroup/memory/memory.usage_in_bytes','/sys/fs/cgroup/pids/pids.max','/sys/fs/cgroup/cpuacct/cpuacct.usage'].map(text));quota=Number(old[0]);period=Number(old[1]);bytes=finiteLimit(old[2]);used=finiteLimit(old[3]);maxPids=finiteLimit(old[4]);usage=old[5]?Number(old[5])/1000:NaN;}
  const cpuCores=quota>0&&period>0?Number((quota/period).toFixed(3)):null;
  return {scope:cpuCores||bytes?'container':'unrestricted',cpuCores,memoryMB:bytes?mb(bytes):null,pidsMax:maxPids,containerMemoryMB:used?mb(used):null,containerCpuUsageMicros:Number.isFinite(usage)?usage:null,heapLimitMB:mb(getHeapStatistics().heap_size_limit)};
}
export function containerCpuSample(previous,current,elapsedMs){
  if(previous===null||current===null||elapsedMs<=0||current<previous)return null;
  return Number(((current-previous)/(elapsedMs*10)).toFixed(2));
}
export function setupResources(app,ctx){
  const histogram=monitorEventLoopDelay({resolution:20});histogram.enable();
  let previous=process.cpuUsage(),at=performance.now(),sample=null,limits=null,limitsAt=0,limitsFlight=null,containerCPU=null,previousContainer=null,previousContainerAt=0,restartPending=false,restartAt=0;
  const history=[];
  const refreshLimits=()=>{if(limitsFlight)return limitsFlight;if(Date.now()-limitsAt<5000)return Promise.resolve();limitsFlight=readResourceLimits().then(value=>{const now=performance.now();containerCPU=containerCpuSample(previousContainer,value.containerCpuUsageMicros,now-previousContainerAt);previousContainer=value.containerCpuUsageMicros;previousContainerAt=now;limits=value;limitsAt=Date.now();}).finally(()=>{limitsFlight=null;});return limitsFlight;};
  const read=()=>{const elapsed=performance.now()-at;if(elapsed>=1000||!sample){const usage=process.cpuUsage(),memory=process.memoryUsage(),ready=elapsed>=1000;sample={scope:'server-process',cpuOneCorePercent:ready?Number((((usage.user-previous.user)+(usage.system-previous.system))/(elapsed*1000)*100).toFixed(2)):null,rssMB:mb(memory.rss),heapUsedMB:mb(memory.heapUsed),heapTotalMB:mb(memory.heapTotal),externalMB:mb(memory.external),eventLoopP99Ms:ready?Number((histogram.percentile(99)/1e6).toFixed(2)):null,intervalMs:Math.round(elapsed),sampledAt:new Date().toISOString()};if(ready){previous=usage;at=performance.now();histogram.reset();}}return {...sample};};
  ctx.resourceSnapshot=()=>({...read(),limits,containerCpuOneCorePercent:containerCPU,containerCpuBudgetPercent:containerCPU!==null&&limits?.cpuCores?Number((containerCPU/limits.cpuCores).toFixed(2)):null,containerMemoryBudgetPercent:limits?.memoryMB&&limits.containerMemoryMB!==null?Number((limits.containerMemoryMB/limits.memoryMB*100).toFixed(2)):null});
  const collect=async()=>{await refreshLimits();history.push(ctx.resourceSnapshot());if(history.length>120)history.shift();};
  const timer=setInterval(()=>{void collect();},5000);timer.unref();void collect();
  const serviceStatus=user=>({name:'GlukWave',scope:'glukwave-service',managed:!!ctx.config.serviceRestartEnabled,owner:!!ctx.isOwner(user),canRestart:!!ctx.config.serviceRestartEnabled&&!!ctx.restartService&&!!ctx.isOwner(user)&&!restartPending,pending:restartPending,uptime:process.uptime()});
  app.get('/api/admin/resources',ctx.requireAdmin,asyncRoute(async(_req,res)=>{await refreshLimits();res.set('Cache-Control','no-store').json({resources:ctx.resourceSnapshot(),history:[...history],realtime:ctx.realtimeStats?.()||null,extractors:ctx.extractorStats?.()||null,uptime:process.uptime()});}));
  app.get('/api/admin/service',ctx.requireAdmin,asyncRoute(async(req,res)=>res.set('Cache-Control','no-store').json({service:serviceStatus(req.auth.user)})));
  app.post('/api/admin/service/restart',ctx.requireAdmin,asyncRoute(async(req,res)=>{
    if(!ctx.isOwner(req.auth.user))fail(403,'OWNER_REQUIRED','Перезапустить сервис может только владелец.');
    const {confirmation}=parse(z.object({confirmation:z.literal('RESTART_GLUKWAVE')}).strict(),req.body);
    if(!ctx.config.serviceRestartEnabled||!ctx.restartService)fail(409,'SERVICE_RESTART_UNAVAILABLE','Перезапуск включается только под менеджером сервиса.');
    if(restartPending||restartAt&&Date.now()-restartAt<60000)fail(409,'SERVICE_RESTART_PENDING','Перезапуск уже запрошен.');
    restartPending=true;restartAt=Date.now();
    try{await ctx.audit('admin.serviceRestart',req.auth.user.id,{service:'glukwave',confirmation});}catch(error){restartPending=false;restartAt=0;throw error;}
    res.once('finish',()=>setImmediate(()=>Promise.resolve().then(()=>ctx.restartService()).catch(error=>{restartPending=false;ctx.log.error({message:error.message},'Service restart failed');})));
    res.status(202).set('Cache-Control','no-store').json({ok:true,service:serviceStatus(req.auth.user)});
  }));
  ctx.closeResources=()=>{clearInterval(timer);histogram.disable();};
}
