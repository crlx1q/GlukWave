import fs from 'node:fs/promises';
import {createReadStream} from 'node:fs';
import crypto from 'node:crypto';
import path from 'node:path';
import {asyncRoute,fail} from './util.js';

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
  app.get('/api/releases',asyncRoute(async(req,res)=>{res.set('Cache-Control','no-store');res.json({releases:(await verifiedReleases(directory)).map(publicRelease)});}));
  app.get('/api/downloads/:platform',asyncRoute(async(req,res)=>{
    if(!Object.hasOwn(platforms,req.params.platform))fail(404,'NOT_FOUND','Сборка не найдена.');
    const release=(await verifiedReleases(directory)).find(record=>record.platform===req.params.platform);if(!release)fail(404,'NOT_FOUND','Сборка не найдена.');
    res.set('X-Content-SHA256',release.sha256);res.set('Cache-Control','private, no-store');res.download(release.path,release.file,error=>{if(error&&!res.headersSent)res.status(404).end();});
  }));
}
