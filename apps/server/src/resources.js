import {monitorEventLoopDelay} from 'node:perf_hooks';
import {asyncRoute} from './util.js';

export function setupResources(app,ctx){
  const histogram=monitorEventLoopDelay({resolution:20});histogram.enable();
  let previous=process.cpuUsage(),at=performance.now(),sample=null;
  const read=()=>{const elapsed=performance.now()-at;if(elapsed>=1000||!sample){const usage=process.cpuUsage(),memory=process.memoryUsage();sample={scope:'server-process',cpuOneCorePercent:Number((((usage.user-previous.user)+(usage.system-previous.system))/(Math.max(elapsed,1)*1000)*100).toFixed(2)),rssMB:Number((memory.rss/1048576).toFixed(2)),heapUsedMB:Number((memory.heapUsed/1048576).toFixed(2)),heapTotalMB:Number((memory.heapTotal/1048576).toFixed(2)),externalMB:Number((memory.external/1048576).toFixed(2)),eventLoopP99Ms:Number((histogram.percentile(99)/1e6).toFixed(2)),intervalMs:Math.round(elapsed),sampledAt:new Date().toISOString()};previous=usage;at=performance.now();histogram.reset();}return {...sample};};
  ctx.resourceSnapshot=read;
  const timer=setInterval(read,5000);timer.unref();
  app.get('/api/admin/resources',ctx.requireAdmin,asyncRoute(async(_req,res)=>res.set('Cache-Control','no-store').json({resources:read(),realtime:ctx.realtimeStats?.()||null,extractors:ctx.extractorStats?.()||null,uptime:process.uptime()})));
  ctx.closeResources=()=>{clearInterval(timer);histogram.disable();};
}
