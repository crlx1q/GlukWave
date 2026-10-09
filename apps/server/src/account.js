import fs from 'node:fs/promises';
import path from 'node:path';
import nodemailer from 'nodemailer';
import rateLimit from 'express-rate-limit';
import {z} from 'zod';
import {id,now,secret,digest,parse,text,publicUser,verifyPassword,fail,asyncRoute} from './util.js';

export function setupAccount(app,ctx){
 const {store,config,requireAuth,requireAdmin}=ctx;
 const limited=rateLimit({windowMs:15*60000,limit:15,standardHeaders:'draft-8',legacyHeaders:false});
 ctx.registrationEnabled=async()=>((await store.get('siteSettings','registration'))?.enabled!==false);
 const registration=async()=>({enabled:await ctx.registrationEnabled()});
 ctx.isOwner=user=>user?.role==='admin'&&config.adminEmails.includes(user.email);
 app.get('/api/admin/registration',requireAdmin,asyncRoute(async(req,res)=>res.json({registration:await registration(),owner:ctx.isOwner(req.auth.user)})));
 app.patch('/api/admin/registration',requireAdmin,asyncRoute(async(req,res)=>{const value=parse(z.object({enabled:z.boolean()}).strict(),req.body);await store.put('siteSettings','registration',{id:'registration',...value});await ctx.audit('admin.registration',req.auth.user.id,value);res.json({registration:value,owner:ctx.isOwner(req.auth.user)});}));
 async function credential(user,password){if(!user?.passwordHash)fail(409,'PASSWORD_REQUIRED','Сначала установи пароль через восстановление доступа по почте.');if(!await verifyPassword(password,user.passwordHash))fail(401,'INVALID_CREDENTIALS','Текущий пароль не подходит.');}
 app.post('/api/account/email',requireAuth,limited,asyncRoute(async(req,res)=>{
  const body=parse(z.object({email:z.email().max(254).transform(value=>value.toLowerCase()),currentPassword:text(128)}).strict(),req.body);
  if(!config.smtp&&config.env!=='test')fail(503,'MAIL_UNAVAILABLE','Отправка писем сейчас недоступна. Попробуй позже.');
  await ctx.withLock('credentials:'+req.auth.user.id,async()=>{
   const user=await store.get('users',req.auth.user.id);await credential(user,body.currentPassword);
   if(body.email===user.email||(await store.list('users',entry=>entry.email===body.email)).length)fail(409,'ACCOUNT_EXISTS','Этот адрес уже используется.');
   const token=secret(),key=digest(token),entry={id:key,userId:user.id,type:'emailChange',email:body.email,previousEmail:user.email,expiresAt:Date.now()+30*60000};await store.create('emailTokens',key,entry);
   const link=`${config.appUrl}/?emailConfirm=${token}`,mail={id:id(),userId:user.id,to:body.email,subject:'GlukWave — confirm your email',text:`Confirm your new GlukWave email address: ${link}\nThis link expires in 30 minutes. If you did not request this change, ignore this email.`,createdAt:now()};
   try{if(config.smtp){const transport=nodemailer.createTransport(config.smtp,{disableFileAccess:true,disableUrlAccess:true});try{await transport.sendMail({from:config.mailFrom,to:mail.to,subject:mail.subject,text:mail.text});}finally{transport.close();}}else{const directory=path.join(config.dataDir,'mailbox');await fs.mkdir(directory,{recursive:true});await fs.writeFile(path.join(directory,mail.id+'.json'),JSON.stringify(mail));}}
   catch(error){await store.remove('emailTokens',key);ctx.log.warn({message:error.message},'Email confirmation delivery failed');fail(503,'MAIL_UNAVAILABLE','Письмо не удалось отправить. Попробуй позже.');}
  });res.json({ok:true,confirmationRequired:true});
 }));
 app.post('/api/account/email/confirm',requireAuth,limited,asyncRoute(async(req,res)=>{
  const {token}=parse(z.object({token:text(150)}).strict(),req.body),key=digest(token),uid=req.auth.user.id;
  const user=await ctx.withLock('credentials:'+uid,async()=>{
   const entry=await store.get('emailTokens',key),current=await store.get('users',uid);
   if(!entry||entry.type!=='emailChange'||entry.userId!==uid||entry.used||entry.expiresAt<=Date.now()||entry.previousEmail!==current.email)fail(400,'TOKEN_EXPIRED','Ссылка недействительна или устарела.');
   let changed;try{changed=await store.update('users',uid,value=>({...value,email:entry.email,emailVerified:true}));}catch(error){if(error.code===11000||String(error.message).includes('UNIQUE'))fail(409,'ACCOUNT_EXISTS','Этот адрес уже используется.');throw error;}
   await store.remove('emailTokens',key);for(const pending of await store.list('emailTokens',value=>value.userId===uid))await store.remove('emailTokens',pending.id);
   // Old Google identities must not silently recover an account after its address changes.
   for(const identity of await store.list('identities',value=>value.userId===uid))await store.remove('identities',identity.id);
   for(const session of await store.list('sessions',value=>value.userId===uid&&value.id!==req.auth.session.id))await ctx.revokeSession(session,'email_changed');
   await ctx.audit('account.email',uid,{});return changed;
  });res.json({ok:true,user:publicUser(user)});
 }));
 // Shared, resumable purge: mark blocked before revocation; media failures remain in durable cleanup.
 ctx.deleteAccount=async(uid,check)=>ctx.withLock('credentials:'+uid,async()=>{
  const user=await store.get('users',uid);if(!user)return;await check?.(user);
  await store.update('users',uid,value=>({...value,blocked:true}));
  await ctx.discordDisconnect?.(uid);
  for(const {value:session} of await store.entries('sessions'))if(session.userId===uid)await ctx.revokeSession(session,'account_deleted');
  for(const {value:room} of await store.entries('rooms'))if(room.members?.some(member=>member.userId===uid)){
   if(room.ownerId===uid){ctx.io?.to(`room:${room.id}`).emit('room:closed',{roomId:room.id});for(const member of room.members)await ctx.leaveAccountRoom?.(member.userId,room.id);await store.remove('rooms',room.id);for(const {id:key,value} of await store.entries('messages'))if(value.roomId===room.id)await store.remove('messages',key);}
   else{await ctx.leaveAccountRoom?.(uid,room.id);await store.update('rooms',room.id,value=>value?{...value,members:value.members.filter(member=>member.userId!==uid)}:undefined);await ctx.refreshRoomPresence?.(room.id);}
  }
  ctx.forgetListening?.(uid);await ctx.flushListening?.();
  for(const {value:track} of await store.entries('tracks'))if(track.uploadedBy===uid)await ctx.purgeTrack(track);
  for(const {value:asset} of await store.entries('assets'))if(asset.ownerId===uid)await ctx.cleanProfileAsset('/api/profile-assets/'+asset.id,uid);
  const collections=['playlists','libraries','settings','connect','devices','connections','identities','emailTokens','challenges','oauthStates','pushSubscriptions','fcmDevices','comments','messages','taste','privacy','friendRequests','friendships','listeningStats','billingCheckouts','checkouts','subscriptions'];
  for(const collection of collections)for(const {id:key,value} of await store.entries(collection))if(key===uid||value.userId===uid||value.ownerId===uid||value.fromId===uid||value.toId===uid||value.userIds?.includes(uid))await store.remove(collection,key);
  for(const {id:key,value} of await store.entries('artists'))if(value.ownerIds?.includes(uid)){const ownerIds=value.ownerIds.filter(owner=>owner!==uid);if(!value.public&&!ownerIds.length)await store.remove('artists',key);else await store.put('artists',key,{...value,ownerIds});}
  for(const {id:key} of await store.entries('lyrics'))if(key.startsWith(uid+':'))await store.remove('lyrics',key);
  for(const {id:key,value} of await store.entries('errorLogs'))if(value.samples?.some(sample=>sample.userId===uid))await store.put('errorLogs',key,{...value,samples:value.samples.map(sample=>sample.userId===uid?{...sample,userId:null}:sample)});
  const mailbox=path.join(config.dataDir,'mailbox');for(const name of await fs.readdir(mailbox).catch(()=>[]))if(name.endsWith('.json')){const file=path.join(mailbox,name);try{const mail=JSON.parse(await fs.readFile(file,'utf8'));if(mail.userId===uid||mail.to===user.email)await fs.unlink(file);}catch{}}
  await store.remove('users',uid);
 });
 app.delete('/api/account',requireAuth,limited,asyncRoute(async(req,res)=>{const body=parse(z.object({currentPassword:text(128),confirmation:text(24)}).strict(),req.body);await ctx.deleteAccount(req.auth.user.id,async current=>{await credential(current,body.currentPassword);if(body.confirmation!==current.username)fail(400,'CONFIRMATION_REQUIRED','Введи своё имя пользователя для подтверждения.');});res.clearCookie('gw_session',{httpOnly:true,secure:config.production,sameSite:'lax',path:'/'});res.json({ok:true});}));
 app.delete('/api/admin/users/:id',requireAdmin,limited,asyncRoute(async(req,res)=>{const {confirmation}=parse(z.object({confirmation:text(24)}).strict(),req.body);if(req.params.id===req.auth.user.id)fail(400,'SELF_ADMIN','Нельзя удалить себя через админ-панель.');const user=await store.get('users',req.params.id);if(!user)fail(404,'USER_NOT_FOUND','Пользователь не найден.');if(config.adminEmails.includes(user.email)&&!ctx.isOwner(req.auth.user))fail(403,'OWNER_REQUIRED','Владельца удаляет только владелец сервиса.');if(confirmation!==user.username)fail(400,'CONFIRMATION_REQUIRED','Подтверди имя пользователя.');await ctx.deleteAccount(user.id);await ctx.audit('admin.userDelete',req.auth.user.id,{targetUserId:user.id});res.json({ok:true});}));
}
