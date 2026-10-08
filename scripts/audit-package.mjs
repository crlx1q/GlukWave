import fs from 'node:fs/promises';
import {createReadStream} from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import zlib from 'node:zlib';
import {fileURLToPath} from 'node:url';
import dotenv from 'dotenv';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const archivePath=path.join(root,'outputs/GlukWave-source.zip');
const archive=await fs.readFile(archivePath);
const requireCondition=(value,message)=>{if(!value)throw new Error(message);};
const sha=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
const checksum=async filename=>{const h=crypto.createHash('sha256');for await(const part of createReadStream(filename))h.update(part);return h.digest('hex');};
const table=Array.from({length:256},(_,n)=>{let value=n;for(let bit=0;bit<8;bit++)value=value&1?0xedb88320^(value>>>1):value>>>1;return value>>>0;});
const crc32=bytes=>{let crc=0xffffffff;for(const byte of bytes)crc=table[(crc^byte)&255]^(crc>>>8);return (crc^0xffffffff)>>>0;};

// Inspect local secret values only in memory. Neither values nor names are logged.
const secrets=new Set();
const add=value=>{if(typeof value==='string'&&value.length>=8){secrets.add(value);if(value.includes('\n'))secrets.add(value.replaceAll('\n','\\n'));}};
const env=dotenv.parse(await fs.readFile(path.join(root,'.env')).catch(()=>Buffer.alloc(0)));
for(const [key,value] of Object.entries(env)){
  if(/SECRET|PASSWORD|PRIVATE|ENCRYPTION|MONGODB_URI|SMTP_URL|ACCESS_KEY|ORIGINKIT_API_KEY/i.test(key))add(value);
  if(/MONGODB_URI|SMTP_URL/i.test(key)){try{const url=new URL(value);if(url.password)add(decodeURIComponent(url.password));}catch{}}
}
try{const local=JSON.parse(await fs.readFile(path.join(root,'var/local-secrets.json'),'utf8'));for(const [key,value] of Object.entries(local))if(/PRIVATE|ENCRYPTION|SECRET/i.test(key))add(value);}catch{}

let end=-1;
for(let n=archive.length-22;n>=Math.max(0,archive.length-65557);n--){if(archive.readUInt32LE(n)===0x06054b50&&n+22+archive.readUInt16LE(n+20)===archive.length){end=n;break;}}
requireCondition(end>=0,'ZIP footer missing');
requireCondition(archive.readUInt16LE(end+4)===0&&archive.readUInt16LE(end+6)===0,'Multi-disk ZIP unsupported');
const count=archive.readUInt16LE(end+10),offset=archive.readUInt32LE(end+16),directorySize=archive.readUInt32LE(end+12);
requireCondition(count>0&&count<65535&&offset+directorySize===end,'Invalid ZIP directory');
const allowed=new Set(['apps','docs','scripts','deploy','.github']);
const rootFiles=new Set(['.env.example','.gitignore','.dockerignore','Dockerfile','compose.yaml','package.json','package-lock.json','README.md']);
const outputFiles=new Set(['outputs/START.md','outputs/VERIFICATION.md','outputs/Start-GlukWave.ps1']);
const forbidden=/(?:^|\/)(?:node_modules|\.git|\.originkit|work|var|build|\.dart_tool|\.gradle|ephemeral|\.symlinks|__pycache__|xcuserdata)(?:\/|$)|\.(?:sqlite(?:3)?(?:-wal|-shm)?|keystore|jks|p12|apk|ipa|exe|pyc)$/i;
const textFile=/\.(?:md|txt|json|[cm]?js|tsx?|css|html|ya?ml|ps1|py|dart|xml|java|kt|kts|cpp|cc|c|h|rc|properties|lock|cmake|xcconfig|plist|entitlements|example|gitignore|dockerignore)$|\/Dockerfile$/i;
const names=new Set(),hashes=new Map();let cursor=offset,totalBytes=0,textFilesScanned=0;
for(let n=0;n<count;n++){
  requireCondition(archive.readUInt32LE(cursor)===0x02014b50,'Invalid ZIP entry');
  const flags=archive.readUInt16LE(cursor+8),method=archive.readUInt16LE(cursor+10),crc=archive.readUInt32LE(cursor+16),compressed=archive.readUInt32LE(cursor+20),size=archive.readUInt32LE(cursor+24);
  const nameLength=archive.readUInt16LE(cursor+28),extra=archive.readUInt16LE(cursor+30),comment=archive.readUInt16LE(cursor+32),localOffset=archive.readUInt32LE(cursor+42);
  const name=archive.subarray(cursor+46,cursor+46+nameLength).toString('utf8');cursor+=46+nameLength+extra+comment;
  requireCondition(name.startsWith('GlukWave/')&&!name.includes('\\')&&!name.split('/').includes('..'),'Unsafe ZIP path');
  const relative=name.slice('GlukWave/'.length),top=relative.split('/')[0];
  requireCondition(relative&&!names.has(relative),'Duplicate or empty ZIP path');names.add(relative);
  requireCondition(!forbidden.test(relative),'Runtime/private artifact included: '+relative);
  requireCondition(!relative.split('/').some(part=>part.startsWith('.env')&&relative!=='.env.example'),'Private environment included');
  requireCondition(allowed.has(top)||rootFiles.has(relative)||outputFiles.has(relative),'Unexpected archive root: '+relative);
  requireCondition(!(flags&1)&&[0,8].includes(method)&&size<=256*1024*1024,'Unsupported ZIP compression/entry size');
  requireCondition(archive.readUInt32LE(localOffset)===0x04034b50,'Invalid local ZIP entry');
  const bodyStart=localOffset+30+archive.readUInt16LE(localOffset+26)+archive.readUInt16LE(localOffset+28);
  const packed=archive.subarray(bodyStart,bodyStart+compressed),body=method===0?packed:zlib.inflateRawSync(packed,{maxOutputLength:256*1024*1024});
  requireCondition(body.length===size&&crc32(body)===crc,'ZIP CRC/size mismatch: '+relative);
  const actualPath=path.resolve(root,relative);requireCondition(actualPath.startsWith(root+path.sep),'Source outside project');
  const digest=sha(body);requireCondition(digest===await checksum(actualPath),'Archive differs from current source: '+relative);hashes.set(relative,digest);
  totalBytes+=size;requireCondition(totalBytes<1024*1024*1024,'Unexpected archive expansion');
  if(textFile.test(relative)){
    textFilesScanned++;const text=body.toString('utf8');
    requireCondition(!Array.from(secrets).some(value=>text.includes(value)),'Local private value found in: '+relative);
    requireCondition(!/(?:cmp_live_|sk_live_)[A-Za-z0-9_]{24,}/.test(text),'Live credential pattern found in: '+relative);
  }
}
requireCondition(cursor===end,'ZIP directory size mismatch');
for(const filename of ['README.md','.env.example','outputs/START.md','outputs/VERIFICATION.md','docs/design-reference/Gluk-Wave-v2.html','docs/design-reference/Gluk-Wave-v6-PC-fixed.html','docs/verification/2026-10-08/evidence.json','apps/web/dist/index.html','apps/native/pubspec.yaml'])requireCondition(names.has(filename),'Required source missing: '+filename);
const evidence=JSON.parse(await fs.readFile(path.join(root,'docs/verification/2026-10-08/evidence.json'),'utf8'));
requireCondition(names.has('apps/web/dist'+evidence.web.javascript),'Current web build missing');
const frozen=JSON.parse(await fs.readFile(path.join(root,'docs/verification/2026-10-08/native-source-freeze.json'),'utf8'));
for(const record of frozen.files)requireCondition(hashes.get('apps/native/'+record.path)===record.sha256,'Frozen native source missing/changed: '+record.path);
const fonts=Array.from(names).filter(name=>/^apps\/native\/assets\/fonts\/Nunito-.+\.ttf$/.test(name));requireCondition(fonts.length===6,'Static font faces missing');
const manrope=Array.from(names).filter(name=>/^apps\/native\/assets\/fonts\/Manrope-.+\.ttf$/.test(name));requireCondition(manrope.length===5,'Manrope static font faces missing');
const archiveSha256=sha(archive),apkPath=path.join(root,'outputs/GlukWave-android-debug.apk'),apkSha256=await checksum(apkPath);
requireCondition(apkSha256===evidence.native.sha256,'APK differs from verified build');
let windowsSha256=null;
if(evidence.native.windowsExecutableBuilt){windowsSha256=await checksum(path.join(root,'outputs/GlukWave-windows.zip'));requireCondition(windowsSha256===evidence.native.windows.sha256,'Windows package differs from verified build');}
let installerSha256=null;
if(evidence.native.windows?.installer?.sha256){installerSha256=await checksum(path.join(root,'outputs/GlukWave-Setup.exe'));requireCondition(installerSha256===evidence.native.windows.installer.sha256,'Installer differs from verified build');}
const result={checkedAt:new Date().toISOString(),passed:true,archiveBytes:archive.length,archiveSha256,entries:count,allCrcAndSourceHashesMatched:true,textFilesScanned,localPrivateValuesAbsent:true,liveCredentialPatternsAbsent:true,staticFontFaces:fonts.length,manropeStaticFontFaces:manrope.length,frozenNativeSourcesMatched:frozen.files.length,currentWebBuild:evidence.web.javascript,runtimeDataExcluded:true,apkSha256,windowsSha256,installerSha256};
await fs.mkdir(path.join(root,'work/qa'),{recursive:true});await fs.writeFile(path.join(root,'work/qa/source-package-proof.json'),JSON.stringify(result,null,2)+'\n');
await fs.writeFile(path.join(root,'outputs/SHA256SUMS.txt'),`${apkSha256}  GlukWave-android-debug.apk\n${windowsSha256?windowsSha256+'  GlukWave-windows.zip\n':''}${installerSha256?installerSha256+'  GlukWave-Setup.exe\n':''}${archiveSha256}  GlukWave-source.zip\n`);
console.log(JSON.stringify(result));
