import webpush from 'web-push';
import {importPKCS8,SignJWT} from 'jose';
import {languageCodes} from './locale.js';
import {notificationFor} from './system-text.js';
import {z} from 'zod';
import {id,now,digest,parse,text,fail,asyncRoute,remoteJson} from './util.js';

export function setupPush(app,ctx){const {store,config,requireAuth}=ctx;
  const webEnabled=!!(config.vapidPublic&&config.vapidPrivate),fcmEnabled=!!(config.fcmProject&&config.fcmEmail&&config.fcmKey);
  if(webEnabled)webpush.setVapidDetails(config.vapidSubject,config.vapidPublic,config.vapidPrivate);
  let fcmToken=null;
  async function googleToken(){if(fcmToken?.expiresAt>Date.now()+30000)return fcmToken.token;const key=await importPKCS8(config.fcmKey,'RS256'),assertion=await new SignJWT({scope:'https://www.googleapis.com/auth/firebase.messaging'}).setProtectedHeader({alg:'RS256'}).setIssuer(config.fcmEmail).setSubject(config.fcmEmail).setAudience('https://oauth2.googleapis.com/token').setIssuedAt().setExpirationTime('1h').sign(key);const r=await remoteJson('https://oauth2.googleapis.com/token',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({grant_type:'urn:ietf:params:oauth:grant-type:jwt-bearer',assertion})});fcmToken={token:r.access_token,expiresAt:Date.now()+r.expires_in*1000};return fcmToken.token;}
  app.post('/api/push/subscribe',requireAuth,asyncRoute(async(req,res)=>{if(!webEnabled)fail(503,'PUSH_NOT_CONFIGURED','Уведомления сейчас недоступны.');const b=parse(z.object({subscription:z.object({endpoint:z.url().max(2048),expirationTime:z.number().nullable().optional(),keys:z.object({p256dh:text(300),auth:text(100)})})}).strict(),req.body);const url=new URL(b.subscription.endpoint);if(url.protocol!=='https:'||url.username||url.password||url.port||!(/^(fcm\.googleapis\.com|updates\.push\.services\.mozilla\.com|[a-z0-9.-]+\.push\.apple\.com|[a-z0-9.-]+\.notify\.windows\.com)$/.test(url.hostname)))fail(400,'PUSH_ENDPOINT','Неизвестный сервер push-подписки.');const uid=req.auth.user.id,key=digest(b.subscription.endpoint),existing=await store.get('pushSubscriptions',key);if(existing&&existing.userId!==uid)fail(409,'PUSH_OWNER','Подписка уже привязана к другому аккаунту.');await store.put('pushSubscriptions',key,{id:key,userId:uid,subscription:b.subscription,language:req.language,createdAt:now()});res.json({ok:true});}));
  app.delete('/api/push/subscribe',requireAuth,asyncRoute(async(req,res)=>{const entries=await store.list('pushSubscriptions',r=>r.userId===req.auth.user.id);for(const e of entries)await store.remove('pushSubscriptions',e.id);res.json({ok:true});}));
  app.post('/api/push/device',requireAuth,asyncRoute(async(req,res)=>{if(!fcmEnabled)fail(503,'FCM_NOT_CONFIGURED','Уведомления сейчас недоступны.');const b=parse(z.object({token:text(4096),platform:z.enum(['android','ios'])}).strict(),req.body),key=digest(b.token),existing=await store.get('fcmDevices',key);if(existing&&existing.userId!==req.auth.user.id)fail(409,'PUSH_OWNER','Это устройство уже связано с другим аккаунтом.');await store.put('fcmDevices',key,{id:key,userId:req.auth.user.id,...b,language:req.language,createdAt:now()});res.json({ok:true});}));
  ctx.notifyUser=async(uid,message)=>{
    const settings=await store.get('settings',uid);
    const language=fallback=>languageCodes.includes(settings?.language)?settings.language:languageCodes.includes(fallback)?fallback:'en';
    // Auto follows each receiving device; a manual account choice applies to all.
    for(const socketId of ctx.io?.sockets.adapter.rooms.get(`user:${uid}`)||[]){
      const socket=ctx.io.sockets.sockets.get(socketId);
      socket?.emit('notification',notificationFor(message,language(socket.data.language)));
    }
    if(!settings?.notifications)return;
    const jobs=[];
    if(webEnabled)for(const sub of await store.list('pushSubscriptions',s=>s.userId===uid)){
      const payload=notificationFor(message,language(sub.language));
      jobs.push(webpush.sendNotification(sub.subscription,JSON.stringify(payload)).catch(async err=>{if([404,410].includes(err.statusCode))await store.remove('pushSubscriptions',sub.id);else ctx.log.warn({status:err.statusCode},'Web push delivery failed');}));
    }
    if(fcmEnabled)for(const device of await store.list('fcmDevices',s=>s.userId===uid))jobs.push((async()=>{
      const payload=notificationFor(message,language(device.language)),token=await googleToken();
      const r=await fetch(`https://fcm.googleapis.com/v1/projects/${encodeURIComponent(config.fcmProject)}/messages:send`,{method:'POST',headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json'},body:JSON.stringify({message:{token:device.token,notification:{title:payload.title,body:payload.body},data:{url:payload.url||'/app/'}}}),signal:AbortSignal.timeout(10000)});
      if(!r.ok){const error=await r.json().catch(()=>({}));if(error.error?.details?.some(x=>x.errorCode==='UNREGISTERED'))await store.remove('fcmDevices',device.id);else ctx.log.warn({status:r.status},'FCM delivery failed');}
    })().catch(err=>ctx.log.warn({message:err.message},'FCM unavailable')));
    await Promise.allSettled(jobs);
  };
}
