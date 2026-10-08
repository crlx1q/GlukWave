import crypto from 'node:crypto';
import rateLimit from 'express-rate-limit';
import {z} from 'zod';
import {asyncRoute,parse,fail,now} from './util.js';

// Never persist cookies, account input, query parameters or local user paths.
export function scrubDiagnostic(value,max=2000){
  return String(value??'').slice(0,12000)
    .replace(/\bBearer\s+[^\s,;"']+/gi,'Bearer [redacted]')
    .replace(/(["']?(?:password|passwd|token|secret|authorization|cookie|api[_-]?key|captchaToken)["']?\s*[:=]\s*)(?:"[^"\r\n]*"|'[^'\r\n]*'|[^\s,;}"']+)/gi,'$1[redacted]')
    .replace(/(?:mongodb(?:\+srv)?|postgres(?:ql)?|redis):\/\/[^\s<>"')]+/gi,'[connection]')
    .replace(/\b(?:cmp_live_|sk_live_)[\w-]+/g,'[redacted]')
    .replace(/\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/gi,'[email]')
    .replace(/(?:[A-Z]:[\\/]Users[\\/]|\/Users\/|\/home\/)[^\s\\/]+/gi,'[user-path]')
    .replace(/https?:\/\/[^\s<>"')]+/gi,url=>{try{const parsed=new URL(url);return `${parsed.origin}${parsed.pathname}`;}catch{return '[url]';}})
    .replace(/\?[^\s)\]]+/g,'?[redacted]')
    .replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/g,'')
    .slice(0,max);
}
const platforms=['web','android','windows','ios','server'];
const kinds=['runtime','framework','network','playback','socket','background','resource'];
const schema=z.object({platform:z.enum(platforms.filter(platform=>platform!=='server')),kind:z.enum(kinds),message:z.string().min(1).max(4000),stack:z.string().max(12000).optional(),version:z.string().max(100).optional(),route:z.string().max(300).optional(),code:z.string().max(100).optional(),status:z.number().int().min(0).max(599).optional(),occurredAt:z.string().max(40).optional()}).strict();
const hash=value=>crypto.createHash('sha256').update(value).digest('hex');
export function diagnosticEvent(input){
  const event={platform:input.platform,kind:input.kind,message:scrubDiagnostic(input.message),stack:scrubDiagnostic(input.stack,8000),version:scrubDiagnostic(input.version,100),route:scrubDiagnostic(input.route,200).replace(/#[^\s]*/g,''),code:scrubDiagnostic(input.code,100),...(input.status?{status:input.status}:{})};
  // Session-specific line numbers and UUIDs must not create endless new groups.
  const normalized=event.message.replace(/[a-f\d]{8}-[a-f\d-]{27,}/gi,'[id]').replace(/\b\d{4,}\b/g,'#');
  event.id=hash([event.platform,event.kind,event.code,event.version,normalized].join('|')).slice(0,40);
  return event;
}
export function setupDiagnostics(app,ctx){
  const {store,requireAdmin}=ctx;
  let closed=false;
  ctx.reportError=async input=>{
    if(closed)return;
    const event=diagnosticEvent(input),at=now();
    await ctx.withLock('diagnostics:write',async()=>{
      if(!await store.get('errorLogs',event.id)){
        const groups=await store.list('errorLogs');
        if(groups.length>=1000){const oldest=groups.sort((a,b)=>a.lastSeen.localeCompare(b.lastSeen))[0];await store.remove('errorLogs',oldest.id);}
      }
      await store.update('errorLogs',event.id,previous=>({...previous,...event,firstSeen:previous?.firstSeen||at,lastSeen:at,count:(previous?.count||0)+1,state:previous?.state==='ignored'?'ignored':'open',lastResolvedAt:previous?.lastResolvedAt||null,samples:[{at,stack:event.stack,route:event.route,...(input.userId?{userId:input.userId}:{}),...(event.status?{status:event.status}:{})},...(previous?.samples||[])].slice(0,10)}));
    });
  };
  const limiter=rateLimit({windowMs:60000,limit:12,standardHeaders:'draft-8',legacyHeaders:false});
  app.post('/api/diagnostics/events',limiter,asyncRoute(async(req,res)=>{
    const {events}=parse(z.object({events:z.array(schema).min(1).max(10)}).strict(),req.body);
    for(const event of events)await ctx.reportError({...event,userId:req.auth?.user?.id});
    res.status(202).json({accepted:events.length});
  }));
  app.get('/api/admin/errors',requireAdmin,asyncRoute(async(req,res)=>{
    const query=parse(z.object({platform:z.enum(platforms).optional(),state:z.enum(['open','resolved','ignored']).optional(),q:z.string().max(100).optional(),page:z.coerce.number().int().min(1).max(100).default(1)}).strict(),req.query);
    const all=await store.list('errorLogs'),q=query.q?.toLowerCase();
    const selected=all.filter(event=>(!query.platform||event.platform===query.platform)&&(!query.state||event.state===query.state)&&(!q||`${event.message} ${event.code}`.toLowerCase().includes(q))).sort((a,b)=>b.lastSeen.localeCompare(a.lastSeen));
    res.set('Cache-Control','private, no-store').json({errors:selected.slice((query.page-1)*50,query.page*50),total:selected.length,page:query.page,counts:{open:all.filter(e=>e.state==='open').length,resolved:all.filter(e=>e.state==='resolved').length,ignored:all.filter(e=>e.state==='ignored').length}});
  }));
  app.patch('/api/admin/errors/:id',requireAdmin,asyncRoute(async(req,res)=>{
    const body=parse(z.object({state:z.enum(['open','resolved','ignored'])}).strict(),req.body);
    const event=await store.update('errorLogs',req.params.id,previous=>{if(!previous)fail(404,'NOT_FOUND','Запись не найдена.');return {...previous,state:body.state,...(body.state==='resolved'?{lastResolvedAt:now()}:{}),updatedBy:req.auth.user.id};});
    await ctx.audit('admin.errorState',req.auth.user.id,{errorId:event.id,state:body.state});res.json({error:event});
  }));
  const prune=setInterval(()=>{void ctx.withLock('diagnostics:write',async()=>{for(const event of await store.list('errorLogs'))if(Date.parse(event.lastSeen)<Date.now()-30*86400000)await store.remove('errorLogs',event.id);}).catch(()=>{});},3600000);prune.unref();
  const originalError=ctx.log.error.bind(ctx.log);
  ctx.log.error=(...args)=>{originalError(...args);const item=args[0],err=item?.err||item;void ctx.reportError({platform:'server',kind:'background',message:err?.message||String(args[1]||args[0]),stack:err?.stack||'',version:'0.1.0',route:item?.path||'',code:item?.code||''}).catch(()=>{});};
  ctx.closeDiagnostics=async()=>{closed=true;clearInterval(prune);ctx.log.error=originalError;await ctx.withLock('diagnostics:write',async()=>{});};
}
