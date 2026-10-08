import {z} from 'zod';
import rateLimit from 'express-rate-limit';
import nodemailer from 'nodemailer';
import {accountMail,resetConfirmation} from './mail-text.js';
import fs from 'node:fs/promises';
import path from 'node:path';
import {id,now,secret,digest,parse,text,publicUser,hashPassword,verifyPassword,fail,asyncRoute,remoteJson} from './util.js';

export function setupAuth(app,ctx){
  const {store,config,log}=ctx;
  const cookieOptions={httpOnly:true,secure:config.production,sameSite:'lax',path:'/',maxAge:30*86400000};
  async function authenticate(token){if(!token||typeof token!=='string'||token.length>200)return null;const session=await store.get('sessions',digest(token));if(!session||session.expiresAt<Date.now())return null;const user=await store.get('users',session.userId);if(!user||user.blocked)return null;return {user,session};}
  ctx.authenticate=authenticate;
  const getToken=req=>req.headers.authorization?.startsWith('Bearer ')?req.headers.authorization.slice(7):req.cookies.gw_session;
  app.use('/api',asyncRoute(async(req,res,next)=>{req.auth=await authenticate(getToken(req));next();}));
  const requireAuth=(req,res,next)=>{if(!req.auth)return next(new ctx.HttpError(401,'AUTH_REQUIRED','Войди в GlukWave, чтобы продолжить.'));if(config.emailVerify&&!req.auth.user.emailVerified)return next(new ctx.HttpError(403,'EMAIL_UNVERIFIED','Подтверди адрес электронной почты.'));next();};
  const requireAdmin=(req,res,next)=>requireAuth(req,res,err=>{if(err)return next(err);if(req.auth.user.role!=='admin')return next(new ctx.HttpError(403,'ADMIN_REQUIRED','Доступ только для администратора.'));next();});
  ctx.requireAuth=requireAuth;ctx.requireAdmin=requireAdmin;
  async function issue(user,req,res){const token=secret(),key=digest(token),installation=req.headers['x-glukwave-device'];const deviceId=typeof installation==='string'&&/^[\w-]{1,100}$/.test(installation)?installation:undefined;await store.create('sessions',key,{id:key,userId:user.id,expiresAt:Date.now()+30*86400000,createdAt:now(),deviceName:String(req.body?.deviceName||req.headers['user-agent']||'GlukWave').slice(0,150),...(deviceId?{deviceId,deviceIds:[deviceId]}:{})});if(res)res.cookie('gw_session',token,cookieOptions);return {user:publicUser(user),...(req.headers['x-glukwave-client']==='native'?{token}:{}),_token:token};}
  ctx.issue=issue;
  async function sendMail(user,type,language='en'){const token=secret(),key=digest(token);await store.create('emailTokens',key,{id:key,userId:user.id,type,expiresAt:Date.now()+30*60000});const link=type==='verify'?`${config.appUrl}/api/auth/verify?token=${token}`:`${config.appUrl}/?reset=${token}`;const mail={id:id(),to:user.email,...accountMail(user,type,link,language),createdAt:now()};if(config.smtp){const transport=nodemailer.createTransport(config.smtp,{disableFileAccess:true,disableUrlAccess:true});await transport.sendMail({from:config.mailFrom,to:mail.to,subject:mail.subject,text:mail.text});}else{await fs.mkdir(path.join(config.dataDir,'mailbox'),{recursive:true});await fs.writeFile(path.join(config.dataDir,'mailbox',`${mail.id}.json`),JSON.stringify(mail,null,2));log.info({mailId:mail.id},'Email saved to local mailbox');}return mail;}
  ctx.sendMail=sendMail;
  async function captcha(req){if(!config.turnstileSecret){if(config.production)fail(503,'CAPTCHA_UNAVAILABLE','Защита регистрации ещё не настроена.');return;}const token=req.body.captchaToken||req.body?.['cf-turnstile-response'];if(typeof token!=='string'||!token.trim()||token.length>2048)fail(400,'CAPTCHA_REQUIRED','Пройди проверку Cloudflare.');const r=await remoteJson('https://challenges.cloudflare.com/turnstile/v0/siteverify',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({secret:config.turnstileSecret,response:token,remoteip:req.ip})});if(!r.success)fail(400,'CAPTCHA_FAILED',`Проверка Cloudflare не пройдена: ${(r['error-codes']||[]).join(', ')||'повтори её'}.`);if(config.production&&r.hostname){const validHosts=[new URL(config.appUrl).hostname,...config.origins.map(o=>{try{return new URL(o).hostname;}catch{return '';}}).filter(Boolean)];if(!validHosts.includes(r.hostname))fail(400,'CAPTCHA_HOST',`Проверка выполнена на другом сайте (${r.hostname}).`);}}
  ctx.captcha=captcha;
  const authLimiter=rateLimit({windowMs:15*60000,limit:30,standardHeaders:'draft-8',legacyHeaders:false,message:{error:{code:'RATE_LIMIT',message:'Слишком много попыток. Попробуй через 15 минут.'}}});
  app.get('/api/auth/me',(req,res)=>res.json({user:publicUser(req.auth?.user)}));
  app.post('/api/auth/register',authLimiter,asyncRoute(async(req,res)=>{const b=parse(z.object({email:z.email().max(254).transform(x=>x.toLowerCase()),username:z.string().trim().regex(/^[a-zA-Z0-9_]{3,24}$/).transform(x=>x.toLowerCase()),password:z.string().min(10).max(128),displayName:text(60).optional(),captchaToken:z.string().optional(),'cf-turnstile-response':z.string().optional()}).strict(),req.body);await captcha(req);const user={id:id(),email:b.email,username:b.username,displayName:b.displayName||b.username,bio:'',tags:[],avatarUrl:'',bannerUrl:'',plan:'free',role:config.adminEmails.includes(b.email)?'admin':'user',emailVerified:!config.emailVerify,passwordHash:await hashPassword(b.password),blocked:false,createdAt:now()};try{await store.create('users',user.id,user);}catch(e){if(e.code===11000||String(e.message).includes('UNIQUE'))fail(409,'ACCOUNT_EXISTS','Почта или имя пользователя уже заняты.');throw e;}if(config.emailVerify){try{await sendMail(user,'verify',req.language);}catch(err){await store.remove('users',user.id);throw err;}}const {_token,...data}=await issue(user,req,res);await ctx.audit('auth.register',user.id,{username:user.username});res.status(201).json({...data,verificationRequired:config.emailVerify,emailDelivery:config.smtp?'smtp':'local'});}));
  app.post('/api/auth/login',authLimiter,asyncRoute(async(req,res)=>{const b=parse(z.object({email:text(254),password:z.string().min(1).max(128),captchaToken:z.string().optional(),'cf-turnstile-response':z.string().optional(),deviceName:text(100).optional()}).strict(),req.body);if(config.production)await captcha(req);const identifier=b.email.toLowerCase().replace(/^@/,'');const user=(await store.list('users',u=>u.email===identifier||u.username===identifier))[0];const valid=await verifyPassword(b.password,user?.passwordHash);if(!valid||user?.blocked)fail(401,'INVALID_CREDENTIALS','Логин или пароль не подходят.');const {_token,...data}=await issue(user,req,res);await ctx.audit('auth.login',user.id,{});res.json(data);}));
  app.post('/api/account/password',requireAuth,authLimiter,asyncRoute(async(req,res)=>{
    const b=parse(z.object({currentPassword:z.string().min(1).max(128),password:z.string().min(10).max(128)}).strict(),req.body);
    await ctx.withLock('credentials:'+req.auth.user.id,async()=>{
      const user=await store.get('users',req.auth.user.id);if(!await verifyPassword(b.currentPassword,user.passwordHash))fail(401,'INVALID_CREDENTIALS','Текущий пароль не подходит.');
      const passwordHash=await hashPassword(b.password);await store.update('users',user.id,v=>({...v,passwordHash}));
      for(const session of await store.list('sessions',s=>s.userId===user.id&&s.id!==req.auth.session.id)){await store.remove('sessions',session.id);ctx.io?.to(`session:${session.id}`).emit('session:revoked',{reason:'password_changed'});ctx.io?.in(`session:${session.id}`).disconnectSockets(true);}
      await ctx.audit('account.password',user.id,{});
    });res.json({ok:true});
  }));
  app.post('/api/auth/logout',asyncRoute(async(req,res)=>{const token=getToken(req);if(token)await store.remove('sessions',digest(token));res.clearCookie('gw_session',{...cookieOptions,maxAge:undefined});if(req.auth)ctx.io?.in(`session:${req.auth.session.id}`).disconnectSockets(true);res.json({ok:true});}));
  app.post('/api/auth/forgot',authLimiter,asyncRoute(async(req,res)=>{const b=parse(z.object({email:z.email().max(254),captchaToken:z.string().optional(),'cf-turnstile-response':z.string().optional()}).strict(),req.body);if(!config.smtp&&config.env!=='test')fail(503,'MAIL_UNAVAILABLE','Восстановление пароля сейчас недоступно. Попробуй позже.');await captcha(req);const user=(await store.list('users',u=>u.email===b.email.toLowerCase()))[0];if(user)await sendMail(user,'reset',req.language);res.json({ok:true,message:resetConfirmation(req.language)});}));
  app.post('/api/auth/reset',authLimiter,asyncRoute(async(req,res)=>{const b=parse(z.object({token:text(150),password:z.string().min(10).max(128)}).strict(),req.body);const key=digest(b.token);const entry=await store.get('emailTokens',key);if(!entry||entry.type!=='reset'||entry.expiresAt<Date.now())fail(400,'TOKEN_EXPIRED','Ссылка недействительна или устарела.');let consumed=false;await store.update('emailTokens',key,v=>{if(!v||v.used)fail(400,'TOKEN_USED','Ссылка уже использована.');consumed=true;return {...v,used:true};});if(!consumed)fail(400,'TOKEN_USED','Ссылка использована.');await store.update('users',entry.userId,async u=>({...u,passwordHash:await hashPassword(b.password)}));for(const s of await store.list('sessions',s=>s.userId===entry.userId))await store.remove('sessions',s.id);ctx.io?.in(`user:${entry.userId}`).disconnectSockets(true);res.json({ok:true});}));
  app.get('/api/auth/verify',asyncRoute(async(req,res)=>{const token=String(req.query.token||''),key=digest(token),entry=await store.get('emailTokens',key);if(!entry||entry.type!=='verify'||entry.expiresAt<Date.now()||entry.used)fail(400,'TOKEN_EXPIRED','Ссылка подтверждения недействительна.');await store.update('emailTokens',key,v=>{if(v.used)fail(400,'TOKEN_USED','Ссылка использована.');return {...v,used:true};});await store.update('users',entry.userId,u=>({...u,emailVerified:true}));res.redirect(`${config.appUrl}/?verified=1`);}));
  app.post('/api/auth/resend',authLimiter,asyncRoute(async(req,res)=>{if(!req.auth)fail(401,'AUTH_REQUIRED','Войди в свой аккаунт.');if(!req.auth.user.emailVerified)await sendMail(req.auth.user,'verify',req.language);res.json({ok:true});}));
  app.post('/api/auth/native-captcha',authLimiter,asyncRoute(async(req,res)=>{
    if(!config.turnstileSiteKey)fail(503,'CAPTCHA_UNAVAILABLE','Проверка сейчас недоступна.');
    const token=secret(),entry={id:id(),kind:'captcha',secretHash:digest(token),status:'pending',expiresAt:Date.now()+120000};
    await store.create('challenges',entry.id,entry);
    res.status(201).set('Cache-Control','no-store').json({id:entry.id,secret:token,expiresAt:entry.expiresAt,url:`${config.appUrl}/app/?nativeCaptcha=${entry.id}&secret=${token}`});
  }));
  app.post('/api/auth/native-captcha/:id/approve',authLimiter,asyncRoute(async(req,res)=>{
    const b=parse(z.object({secret:text(150),captchaToken:text(2048)}).strict(),req.body);
    await store.update('challenges',req.params.id,entry=>{
      if(!entry||entry.kind!=='captcha'||entry.status!=='pending'||entry.expiresAt<Date.now()||entry.secretHash!==digest(b.secret))fail(400,'CHALLENGE_EXPIRED','Проверка устарела.');
      // Do not validate here: Turnstile tokens are one-use. The native email
      // request validates it before creating a user or issuing a session.
      return {...entry,status:'approved',captchaToken:b.captchaToken};
    });res.json({ok:true});
  }));
  app.get('/api/auth/native-captcha/:id',asyncRoute(async(req,res)=>{
    const entry=await store.get('challenges',req.params.id);
    if(!entry||entry.kind!=='captcha'||entry.secretHash!==digest(String(req.query.secret||'')))fail(404,'CHALLENGE_NOT_FOUND','Проверка не найдена.');
    res.set('Cache-Control','no-store');
    if(entry.expiresAt<Date.now()||entry.status==='consumed')return res.json({status:'expired'});
    if(entry.status!=='approved')return res.json({status:'pending'});
    const token=await store.update('challenges',entry.id,value=>{
      if(value.status!=='approved')fail(409,'CHALLENGE_USED','Проверка уже использована.');
      const {captchaToken,...rest}=value;return {...rest,status:'consumed'};
    }).then(()=>entry.captchaToken);
    res.json({status:'approved',captchaToken:token});
  }));
  for(const kind of ['qr','native']){
    app.post(`/api/auth/${kind}`,authLimiter,asyncRoute(async(req,res)=>{const b=parse(z.object({deviceName:text(100).optional(),method:z.enum(['google','email']).optional()}).strict(),req.body||{});const token=secret(),entry={id:id(),secretHash:digest(token),deviceName:b.deviceName||'GlukWave',status:'pending',expiresAt:Date.now()+(kind==='qr'?120000:600000),createdAt:now(),kind};await store.create('challenges',entry.id,entry);const url=kind==='qr'?`${config.appUrl}/?qr=${entry.id}`:b.method==='email'?`${config.appUrl}/?native=${entry.id}&secret=${token}`:`${config.appUrl}/api/auth/google/start?native=${entry.id}&secret=${token}`;res.status(201).json({id:entry.id,secret:token,url,expiresAt:entry.expiresAt});}));
    app.get(`/api/auth/${kind}/:id`,asyncRoute(async(req,res)=>{const key=req.params.id;const entry=await store.get('challenges',key);if(!entry||entry.kind!==kind||digest(String(req.query.secret||''))!==entry.secretHash)fail(404,'CHALLENGE_NOT_FOUND','Код не найден.');if(entry.expiresAt<Date.now()||entry.status==='consumed')return res.json({status:'expired'});if(entry.status!=='approved')return res.json({status:'pending'});await store.update('challenges',key,v=>{if(v.status!=='approved')fail(409,'CHALLENGE_USED','Код уже использован.');return {...v,status:'consumed'};});const user=await store.get('users',entry.userId);if(!user||user.blocked)fail(403,'ACCOUNT_BLOCKED','Аккаунт заблокирован.');const {_token,...data}=await issue(user,req,res);res.json({status:'approved',...data,...(kind==='native'?{token:_token}:{})});}));
  }
  app.get('/api/auth/qr/:id/info',asyncRoute(async(req,res)=>{const v=await store.get('challenges',req.params.id);if(!v||v.kind!=='qr')fail(404,'CHALLENGE_NOT_FOUND','Код не найден.');res.json({deviceName:v.deviceName,expiresAt:v.expiresAt,status:v.expiresAt<Date.now()?'expired':v.status});}));
  app.post('/api/auth/qr/:id/approve',requireAuth,asyncRoute(async(req,res)=>{await store.update('challenges',req.params.id,v=>{if(!v||v.kind!=='qr'||v.status!=='pending'||v.expiresAt<Date.now())fail(400,'CHALLENGE_EXPIRED','Код устарел или уже использован.');return {...v,status:'approved',userId:req.auth.user.id};});await ctx.audit('auth.qrApprove',req.auth.user.id,{});res.json({ok:true});}));
  app.post('/api/auth/native/:id/approve',requireAuth,asyncRoute(async(req,res)=>{const b=parse(z.object({secret:text(150)}).strict(),req.body);await store.update('challenges',req.params.id,v=>{if(!v||v.kind!=='native'||v.status!=='pending'||v.expiresAt<Date.now()||v.secretHash!==digest(b.secret))fail(400,'CHALLENGE_EXPIRED','Вход в приложение устарел.');return {...v,status:'approved',userId:req.auth.user.id};});res.json({ok:true});}));
}
