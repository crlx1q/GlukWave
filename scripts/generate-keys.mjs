import fs from 'node:fs';
import crypto from 'node:crypto';
import webpush from 'web-push';
const path='.env';let content=fs.existsSync(path)?fs.readFileSync(path,'utf8'):fs.readFileSync('.env.example','utf8');
const vapid=webpush.generateVAPIDKeys();
const localSecrets=fs.existsSync('var/local-secrets.json')?JSON.parse(fs.readFileSync('var/local-secrets.json','utf8')):{};
for(const [name,value] of Object.entries({TOKEN_ENCRYPTION_KEY:localSecrets.encryption||crypto.randomBytes(32).toString('hex'),VAPID_PUBLIC_KEY:vapid.publicKey,VAPID_PRIVATE_KEY:vapid.privateKey})){const pattern=new RegExp(`^${name}=(.*)$`,'m');const match=content.match(pattern);if(match?.[1]?.trim())continue;content=match?content.replace(pattern,`${name}=${value}`):`${content}\n${name}=${value}\n`;}
fs.writeFileSync(path,content,{mode:0o600});console.log('Saved .env with encryption and Web Push keys. Existing keys preserved. Keep this file private.');
