import {z} from 'zod';
import {createActionJobs} from './action-jobs.js';
import {asyncRoute,parse,text,fail,digest,now} from './util.js';
import {planLimits} from './plans.js';
import {systemText} from './system-text.js';

export async function seedImportedTaste(ctx,uid,ids){
  await ctx.store.update('taste',uid,previous=>({...previous,id:uid,
    importedTrackIds:[...new Set([...ids,...(!previous?.learnedResetAt||previous?.importedAt>previous.learnedResetAt?previous?.importedTrackIds||[]:[])])].slice(0,1000),
    importedAt:now(),revision:(previous?.revision||0)+1}));
  ctx.invalidateRecommendations?.();
}

export function setupLibraryImports(app,ctx,playlistTracks,publicImports){
  const jobs=createActionJobs(),active=new Set();let closed=false;
  ctx.closeImports=()=>{closed=true;jobs.close();publicImports?.close();};
  app.post('/api/integrations/:provider/import',ctx.requireAuth,asyncRoute(async(req,res)=>{
    if(req.headers['x-glukwave-account']&&req.headers['x-glukwave-account']!==req.auth.user.id)fail(409,'ACCOUNT_CHANGED','Аккаунт изменился. Повтори действие.');
    const provider=parse(z.enum(['spotify','soundcloud','youtube','yandex']),req.params.provider);
    if(!planLimits(req.auth.user).libraryImport)fail(403,'PLAN_LIMIT','Импорт доступен в Beta и Unbound.');
    const b=parse(z.object({publicSourceUrl:z.url().max(2048).optional(),playlistId:text(200),name:text(120).optional(),trackIds:z.array(text(200)).max(10000).optional(),
      destination:z.enum(['playlist','likes']).default('playlist'),requestId:z.string().regex(/^[\w-]{8,100}$/).optional()}).strict(),req.body);
    if(provider==='yandex'&&!b.publicSourceUrl)fail(400,'PUBLIC_IMPORT_QUERY','Для Яндекс Музыки укажи публичную коллекцию.');
    const uid=req.auth.user.id,sessionId=req.auth.session.id;
    const check=async()=>{const [user,session]=await Promise.all([ctx.store.get('users',uid),ctx.store.get('sessions',sessionId)]);
      if(closed||!session||session.expiresAt<=Date.now()||!user||user.blocked)fail(401,'AUTH_REQUIRED','Сессия завершена.');
      if(!planLimits(user).libraryImport)fail(403,'PLAN_LIMIT','Импорт доступен в Beta и Unbound.');return user;};
    const work=async()=>{
      if(active.has(uid)||active.size>=2)fail(503,'ACTION_BUSY','Другой импорт ещё выполняется.');
      active.add(uid);
      try{
        const tracks=new Map(),selected=b.trackIds?new Set(b.trackIds):null,cursors=new Set();let cursor='',pages=0,partial=false;const sourceWarnings=new Set();
        const deadline=Date.now()+240000;
        do{
          await check();if(Date.now()>=deadline)fail(504,'IMPORT_TIMEOUT','Импорт занял слишком много времени. Выбери меньше треков.');
          if(cursors.has(cursor))fail(502,'INVALID_CURSOR','Площадка повторила страницу. Импорт не завершён.');cursors.add(cursor);
          const page=b.publicSourceUrl?await publicImports.tracks(provider,b.publicSourceUrl,cursor,uid):await playlistTracks(provider,uid,b.playlistId,cursor);
          partial ||= page.partial===true;for(const warning of page.warnings||[])sourceWarnings.add(warning);
          for(const track of page.tracks)if(!selected||selected.has(track.id))tracks.set(track.id,track);
          cursor=page.nextCursor||'';pages++;
          if(tracks.size>10000)fail(413,'IMPORT_TOO_LARGE','Максимум 10 000 треков за импорт.');
          if(selected&&[...selected].every(id=>tracks.has(id)))break;
        }while(cursor&&pages<200);
        if(cursor&&(!selected||![...selected].every(id=>tracks.has(id))))fail(413,'IMPORT_TOO_LARGE','Плейлист слишком большой: выбери часть треков.');
        if(!tracks.size)fail(422,'EMPTY_IMPORT','В выбранном списке нет доступных треков.');
        const user=await check(),ids=[...tracks.keys()];let playlist=null,imported=ids.length,deduplicated=0;
        if(b.destination==='likes'){
          if(ctx.validateTracks)await ctx.validateTracks(ids,user);else for(let at=0;at<ids.length;at+=12)await Promise.all(ids.slice(at,at+12).map(id=>ctx.requireTrack(id,user)));
          await ctx.store.update('libraries',uid,previous=>{
            const existing=previous||{id:uid,likedIds:[],history:[]},before=new Set(existing.likedIds);
            deduplicated=ids.filter(id=>before.has(id)).length;
            return {...existing,likedIds:[...new Set([...before,...ids])],likedAt:{...existing.likedAt,...Object.fromEntries(ids.filter(id=>!before.has(id)).map(id=>[id,now()]))}};
          });imported-=deduplicated;
        }else playlist=await ctx.createPlaylist(uid,{name:b.name||systemText('importedTracks',req.language),trackIds:ids});
        await seedImportedTaste(ctx,uid,ids);
        ctx.io?.to(`user:${uid}`).emit('library:changed',{});
        await ctx.audit('library.import',uid,{provider,count:imported,destination:b.destination});
        return {playlist,imported,deduplicated,selected:ids.length,unavailable:selected?selected.size-ids.length:0,tasteSeeded:true,partial,warnings:[...sourceWarnings],destination:b.destination};
      }finally{active.delete(uid);}
    };
    res.set('Cache-Control','private, no-store');
    const intent=b.requestId||String(req.headers['x-glukwave-intent']||'');
    if(intent){
      if(!/^[\w-]{8,100}$/.test(intent))fail(400,'INVALID_COMMAND','Неверный идентификатор импорта.');
      const result=await jobs.wait(sessionId+':'+intent+':'+digest(JSON.stringify({provider,...b})),work);
      await check();if(result.pending)res.status(202).set('Retry-After','1');else res.status(201);res.json(result);
    }else res.status(201).json(await work());
  }));
}
