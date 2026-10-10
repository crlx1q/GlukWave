import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';
import dotenv from 'dotenv';

export const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
dotenv.config({path:path.join(root,'.env'), quiet:true});
const e = process.env;
const bool = (value, fallback=false) => value === undefined ? fallback : value === 'true';
export const dataDir = path.resolve(root,e.DATA_DIR || 'var');
fs.mkdirSync(dataDir,{recursive:true});
const keyFile=path.join(dataDir,'local-secrets.json');
let keys={};
if(e.NODE_ENV !== 'production') {
  if(fs.existsSync(keyFile)) keys=JSON.parse(fs.readFileSync(keyFile,'utf8'));
  else { keys={encryption:crypto.randomBytes(32).toString('hex')};fs.writeFileSync(keyFile,JSON.stringify(keys),{mode:0o600}); }
}
export const config={
  root,dataDir,env:e.NODE_ENV||'development',production:e.NODE_ENV==='production',
  host:e.HOST||'0.0.0.0',port:Number(e.PORT||4000),appUrl:e.APP_URL||'http://127.0.0.1:5173',
  origins:(e.ALLOWED_ORIGINS||e.APP_URL||'http://127.0.0.1:5173,http://localhost:5173').split(',').map(x=>x.trim()),
  trustProxy:Number(e.TRUST_PROXY!==undefined?e.TRUST_PROXY:(e.NODE_ENV==='production'||e.PORT?1:0)),storage:e.DB_DRIVER||'sqlite',mongoUri:e.MONGODB_URI||'',mongoDb:e.MONGODB_DATABASE||'glukwave',
  encryptionKey:e.TOKEN_ENCRYPTION_KEY||keys.encryption,
  adminEmails:(e.ADMIN_EMAILS||'').toLowerCase().split(',').filter(Boolean),
  emailVerify:bool(e.REQUIRE_EMAIL_VERIFICATION,e.NODE_ENV==='production'),
  turnstileSiteKey:e.TURNSTILE_SITE_KEY||e.TURNSTILE_SITEKEY||'',turnstileSecret:e.TURNSTILE_SECRET_KEY||e.TURNSTILE_SECRET||'',
  smtp:e.SMTP_URL||'',mailFrom:e.MAIL_FROM||'GlukWave <noreply@wave.gluk.tech>',
  oauthBaseUrl:e.OAUTH_BASE_URL||'',
  google:{id:e.GOOGLE_CLIENT_ID||'',secret:e.GOOGLE_CLIENT_SECRET||'',redirectUri:e.GOOGLE_REDIRECT_URI||''},
  youtubeOAuth:{id:e.YOUTUBE_CLIENT_ID||'',secret:e.YOUTUBE_CLIENT_SECRET||'',redirectUri:e.YOUTUBE_REDIRECT_URI||''},
  spotify:{id:e.SPOTIFY_CLIENT_ID||'',secret:e.SPOTIFY_CLIENT_SECRET||'',redirectUri:e.SPOTIFY_REDIRECT_URI||''},
  soundcloud:{id:e.SOUNDCLOUD_CLIENT_ID||'',secret:e.SOUNDCLOUD_CLIENT_SECRET||'',redirectUri:e.SOUNDCLOUD_REDIRECT_URI||''},
  soundcloudPublicSearch:bool(e.SOUNDCLOUD_PUBLIC_SEARCH,true),
  youtubeKey:e.YOUTUBE_API_KEY||'',discord:{id:e.DISCORD_CLIENT_ID||'',secret:e.DISCORD_CLIENT_SECRET||'',redirectUri:e.DISCORD_REDIRECT_URI||'',headless:bool(e.DISCORD_HEADLESS_ENABLED,true),logoAsset:e.DISCORD_LOGO_ASSET||''},
  objectStorage:e.MEDIA_STORAGE||'local',r2:{endpoint:e.R2_ENDPOINT||'',bucket:e.R2_BUCKET||'',accessKey:e.R2_ACCESS_KEY_ID||'',secretKey:e.R2_SECRET_ACCESS_KEY||''},
  uploadLimitMB:Number(e.UPLOAD_LIMIT_MB||256),
  vapidPublic:e.VAPID_PUBLIC_KEY||'',vapidPrivate:e.VAPID_PRIVATE_KEY||'',vapidSubject:e.VAPID_SUBJECT||'mailto:admin@gluk.tech',
  fcmProject:e.FCM_PROJECT_ID||'',fcmEmail:e.FCM_CLIENT_EMAIL||'',fcmKey:(e.FCM_PRIVATE_KEY||'').replace(/\\n/g,'\n'),
  stripe:{secret:e.STRIPE_SECRET_KEY||'',webhook:e.STRIPE_WEBHOOK_SECRET||'',price:e.STRIPE_UNBOUND_PRICE_ID||''},
  lanDiscovery:bool(e.LAN_DISCOVERY),discoveryPort:Number(e.LAN_DISCOVERY_PORT||4001),
  geoipDir:path.resolve(root,e.GEOIP_DATA_DIR||'apps/server/data/geoip'),
  releasesDir:path.resolve(root,e.RELEASES_DIR||'outputs'),
  extractors:{enabled:bool(e.EXTRACTORS_ENABLED,true),permissive:bool(e.EXTRACTOR_PERMISSIVE,e.NODE_ENV!=='test'),python:e.EXTRACTOR_PYTHON||'',spotdlPython:e.SPOTDL_PYTHON||'',deno:e.EXTRACTOR_DENO||'',concurrency:Math.max(1,Math.min(3,Number(e.EXTRACTOR_CONCURRENCY)||1)),timeout:Math.max(5000,Math.min(120000,Number(e.EXTRACTOR_TIMEOUT_MS)||45000)),cacheMB:Math.max(64,Math.min(8192,Number(e.EXTRACTOR_CACHE_MB)||512))},
};
export function validateConfig() {
  if(!['sqlite','mongo'].includes(config.storage)) throw new Error('DB_DRIVER must be sqlite or mongo');
  if(config.storage==='mongo'&&!config.mongoUri) throw new Error('MONGODB_URI is required');
  if(!/^[a-f\d]{64}$/i.test(config.encryptionKey||'')) throw new Error('TOKEN_ENCRYPTION_KEY must be 64 hex characters');
  if(config.objectStorage==='r2'&&Object.values(config.r2).some(x=>!x)) throw new Error('R2 credentials and endpoint are required');
  if(config.production) {
    if(!config.appUrl.startsWith('https://')) throw new Error('Production APP_URL requires HTTPS');
    if(!config.turnstileSecret||!config.turnstileSiteKey||config.turnstileSecret.startsWith('1x000')) throw new Error('Production requires real Turnstile keys');
    if(!config.smtp||!config.emailVerify) throw new Error('Production requires SMTP and verified email');
  }
}
