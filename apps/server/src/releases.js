import fs from 'node:fs/promises';
import {createReadStream} from 'node:fs';
import crypto from 'node:crypto';
import path from 'node:path';
import multer from 'multer';
import {z} from 'zod';
import {asyncRoute,fail,parse,id} from './util.js';

const platforms={android:['.apk'],windows:['.exe','.zip'],ios:['.ipa']};
const hashes=new Map();
async function fileHash(file,stat){
  const fingerprint=`${file}:${stat.size}:${stat.mtimeMs}:${stat.ctimeMs}`;
  if(!hashes.has(fingerprint)){
    if(hashes.size>=32)hashes.delete(hashes.keys().next().value);
    const pending=(async()=>{const hash=crypto.createHash('sha256');for await(const part of createReadStream(file))hash.update(part);return hash.digest('hex');})();
    hashes.set(fingerprint,pending);pending.catch(()=>hashes.delete(fingerprint));
  }
  return hashes.get(fingerprint);
}
export async function verifiedReleases(directory){
  let root,manifest;
  try{root=await fs.realpath(directory);const location=path.join(root,'releases.json'),stat=await fs.stat(location);if(stat.size>65536)return [];manifest=JSON.parse(await fs.readFile(location,'utf8'));}catch{return [];}
  if(!Array.isArray(manifest.releases)||manifest.releases.length>12)return [];
  const releases=[];
  for(const record of manifest.releases){
    if(!record||!Object.hasOwn(platforms,record.platform)||typeof record.file!=='string'||record.file!==path.basename(record.file)||/[\\/:]/.test(record.file)||!platforms[record.platform].includes(path.extname(record.file).toLowerCase()))continue;
    if(!/^[a-f\d]{64}$/i.test(record.sha256||'')||!Number.isSafeInteger(record.bytes)||record.bytes<1||!/^\d+\.\d+\.\d+(?:[-+][\w.-]+)?$/.test(record.version||'')||!['beta','stable'].includes(record.channel)||!['debug','release'].includes(record.signature)||!Number.isFinite(Date.parse(record.builtAt)))continue;
    try{
      const candidate=path.join(root,record.file),actual=await fs.realpath(candidate);if(path.dirname(actual)!==root||actual!==candidate)continue;
      const stat=await fs.stat(actual);if(!stat.isFile()||stat.size!==record.bytes||stat.size>2*1024*1024*1024)continue;
      if(await fileHash(actual,stat)!==record.sha256.toLowerCase())continue;
      if(releases.some(release=>release.platform===record.platform))continue;
      releases.push({...record,path:actual});
    }catch{/* A missing or modified package is never advertised as downloadable. */}
  }
  return releases;
}
const publicRelease=({platform,file,version,channel,bytes,sha256,builtAt,signature})=>({platform,version,channel,bytes,sha256,builtAt,signature,format:path.extname(file)==='.exe'?'installer':path.extname(file)==='.zip'?'portable':'package',available:true,url:`/api/downloads/${platform}`});
export function setupReleases(app,ctx){
  const directory=ctx.config.releasesDir||path.join(ctx.config.root,'outputs');
  const uploaded=path.join(ctx.config.dataDir,'releases'),temporary=path.join(ctx.config.dataDir,'tmp');
  const upload=multer({dest:temporary,limits:{fileSize:512*1024*1024,files:1,fields:3,fieldSize:200}});
  const available=async()=>{const all=[...await verifiedReleases(uploaded),...await verifiedReleases(directory)];return [...new Map(all.reverse().map(value=>[value.platform,value])).values()];};
  app.get('/api/releases',asyncRoute(async(req,res)=>{res.set('Cache-Control','no-store');res.json({releases:(await available()).map(publicRelease)});}));
  app.post('/api/admin/releases/:platform',ctx.requireAdmin,(req,res,next)=>{if(!ctx.isOwner(req.auth.user))return next(new ctx.HttpError(403,'OWNER_REQUIRED','Загрузить сборку может владелец сервиса.'));next();},upload.single('file'),asyncRoute(async(req,res)=>{
    const file=req.file;if(!file)fail(400,'FILE_REQUIRED','Выбери файл сборки.');let target,committed=false;
    try{const platform=parse(z.enum(['android','windows','ios']),req.params.platform),metadata=parse(z.object({version:z.string().regex(/^\d+\.\d+\.\d+(?:[-+][\w.-]+)?$/),channel:z.enum(['beta','stable']),signature:z.enum(['debug','release'])}).strict(),req.body),ext=path.extname(file.originalname).toLowerCase();
      if(!platforms[platform].includes(ext)||file.size<1024)fail(415,'PACKAGE_FORMAT','Выбери подходящий установочный пакет.');
      const handle=await fs.open(file.path,'r');try{const header=Buffer.alloc(Math.min(file.size,1024*1024));await handle.read(header,0,header.length,0);
        if(ext==='.exe'){const pe=header.readUInt32LE(0x3c);if(header.subarray(0,2).toString()!=='MZ'||pe+4>header.length||header.subarray(pe,pe+4).toString()!=='PE\0\0')fail(415,'PACKAGE_FORMAT','Файл не является Windows-программой.');}
        else{const tail=Buffer.alloc(Math.min(file.size,1024*1024));await handle.read(tail,0,tail.length,file.size-tail.length);if(header.readUInt32LE(0)!==0x04034b50||!tail.includes(Buffer.from([0x50,0x4b,0x05,0x06])))fail(415,'PACKAGE_FORMAT','Архив пакета повреждён.');if(ext==='.apk'&&!tail.includes(Buffer.from('AndroidManifest.xml')))fail(415,'PACKAGE_FORMAT','Android-манифест не найден.');if(ext==='.ipa'&&!tail.includes(Buffer.from('Payload/')))fail(415,'PACKAGE_FORMAT','iOS-приложение не найдено.');}
      }finally{await handle.close();}
      const result=await ctx.withLock('release-upload',async()=>{await fs.mkdir(uploaded,{recursive:true});const name=`GlukWave-${platform}-${metadata.version}-${id().slice(0,8)}${ext}`;target=path.join(uploaded,name);await fs.rename(file.path,target);const stat=await fs.stat(target),record={platform,...metadata,file:name,bytes:stat.size,sha256:await fileHash(target,stat),builtAt:new Date().toISOString()},existing=await verifiedReleases(uploaded),manifest={releases:[record,...existing.filter(value=>value.platform!==platform).map(({path,...value})=>value)]};const pending=path.join(uploaded,'manifest-'+id()+'.tmp');try{await fs.writeFile(pending,JSON.stringify(manifest,null,2));await fs.rename(pending,path.join(uploaded,'releases.json'));committed=true;}finally{await fs.unlink(pending).catch(()=>{});}await ctx.audit('admin.releaseUpload',req.auth.user.id,{platform,version:record.version,sha256:record.sha256});return record;});res.status(201).json({release:publicRelease(result)});
    }finally{await fs.unlink(file.path).catch(()=>{});if(target&&!committed)await fs.unlink(target).catch(()=>{});}
  }));
  app.get('/api/downloads/:platform',asyncRoute(async(req,res)=>{
    if(!Object.hasOwn(platforms,req.params.platform))fail(404,'NOT_FOUND','Сборка не найдена.');
    const release=(await available()).find(record=>record.platform===req.params.platform);if(!release)fail(404,'NOT_FOUND','Сборка не найдена.');
    res.set('X-Content-SHA256',release.sha256);res.set('Cache-Control','private, no-store');res.download(release.path,release.file,error=>{if(error&&!res.headersSent)res.status(404).end();});
  }));
}
