import {spawnSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';

// Deployment CLI, never called from a request or with a listener's credentials.
// The same project-local virtualenv layout works on Linux and Windows.
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const args=process.argv.slice(2),adapterIndex=args.indexOf('--adapter'),selected=adapterIndex<0?'all':args[adapterIndex+1];
if(!['all','ytdlp','spotdl','deno'].includes(selected)||args.some(arg=>!['--adapter','--check','all','ytdlp','spotdl','deno'].includes(arg)))throw new Error('Use --adapter ytdlp|spotdl|deno|all and optionally --check.');
const check=args.includes('--check'),names=selected==='all'?['ytdlp','spotdl']:[selected];
function run(command,argumentsList,quiet=false){const result=spawnSync(command,argumentsList,{cwd:root,shell:false,windowsHide:true,stdio:quiet?'pipe':'inherit',encoding:'utf8',timeout:quiet?30000:1200000});if(result.error||result.status!==0)throw new Error(`Audio runtime command failed: ${path.basename(command)} (${result.status??'unavailable'}).`);return result.stdout;}
function systemPython(){
  const choices=process.platform==='win32'?[['py',['-3']],['python',[]],['python3',[]]]:[['python3',[]],['python',[]]];
  for(const [command,prefix] of choices){const result=spawnSync(command,[...prefix,'-c','import sys; assert sys.version_info >= (3,10); print(sys.executable)'],{shell:false,windowsHide:true,encoding:'utf8',timeout:30000});if(result.status===0&&result.stdout.trim())return {command,prefix};}
  throw new Error('Python 3.10+ is required on the server. Container builds install it automatically.');
}
for(const name of names.filter(name=>name!=='deno')){
  const folder=path.join(root,'work/tools/extractors',name),python=path.join(folder,process.platform==='win32'?'Scripts/python.exe':'bin/python');
  if(!check){if(!fs.existsSync(python)){const base=systemPython();run(base.command,[...base.prefix,'-m','venv',folder]);}run(python,['-m','pip','install','--disable-pip-version-check','-r',path.join(root,`apps/server/extractors/requirements-${name}.txt`)]);}
  if(!fs.existsSync(python))throw new Error(`${name}: virtualenv missing. Run npm run audio:setup on the server.`);
  const modules=name==='ytdlp'?['yt_dlp','ytmusicapi']:['spotdl'];
  run(python,['-c',"import importlib.util; assert all(importlib.util.find_spec(name) is not None for name in "+JSON.stringify(modules)+")"],true);
  console.log(`${name}: ready (isolated, pinned dependencies).`);
}
if(selected==='all'||selected==='deno'){
  const version='2.9.7',folder=path.join(root,'work/tools/extractors/deno'),binary=path.join(folder,process.platform==='win32'?'deno.exe':'deno');
  if(!fs.existsSync(binary)&&!check){
    const targets={win32:{x64:'x86_64-pc-windows-msvc'},linux:{x64:'x86_64-unknown-linux-gnu',arm64:'aarch64-unknown-linux-gnu'},darwin:{x64:'x86_64-apple-darwin',arm64:'aarch64-apple-darwin'}};
    const target=targets[process.platform]?.[process.arch];if(!target)throw new Error('Deno: unsupported server platform. Set EXTRACTOR_DENO to a separately installed runtime.');
    const response=await fetch(`https://api.github.com/repos/denoland/deno/releases/tags/v${version}`,{signal:AbortSignal.timeout(30000),headers:{Accept:'application/vnd.github+json','User-Agent':'GlukWave-audio-setup'}});
    if(!response.ok)throw new Error('Deno: official release metadata unavailable.');
    const release=await response.json(),asset=release.assets?.find(item=>item.name===`deno-${target}.zip`);
    if(!asset?.browser_download_url?.startsWith(`https://github.com/denoland/deno/releases/download/v${version}/`)||!/^sha256:[a-f0-9]{64}$/.test(asset.digest||''))throw new Error('Deno: verified official release asset missing.');
    const download=await fetch(asset.browser_download_url,{signal:AbortSignal.timeout(120000)});if(!download.ok)throw new Error('Deno: download failed.');
    const chunks=[];let size=0;for await(const chunk of download.body){size+=chunk.length;if(size>100*1024*1024){await download.body.cancel().catch(()=>{});throw new Error('Deno: archive too large.');}chunks.push(chunk);}
    const bytes=Buffer.concat(chunks);if('sha256:'+crypto.createHash('sha256').update(bytes).digest('hex')!==asset.digest)throw new Error('Deno: checksum mismatch.');
    fs.mkdirSync(folder,{recursive:true});const archive=path.join(folder,'deno-download.zip');fs.writeFileSync(archive,bytes);
    try{const base=systemPython();run(base.command,[...base.prefix,'-c',"import pathlib,sys,zipfile; z=zipfile.ZipFile(sys.argv[1]); i=z.getinfo(sys.argv[3]); assert i.file_size<=150*1024*1024; pathlib.Path(sys.argv[2]).write_bytes(z.read(i))",archive,binary,path.basename(binary)],true);if(process.platform!=='win32')fs.chmodSync(binary,0o755);}finally{fs.unlinkSync(archive);}
  }
  if(!fs.existsSync(binary))throw new Error('Deno: runtime missing. Run npm run audio:setup -- --adapter deno on the server.');
  const actual=run(binary,['--version'],true);if(!actual.startsWith(`deno ${version} `))throw new Error('Deno: runtime differs from pinned deployment version.');
  console.log('deno: ready (official checksum-verified release on installation).');
}
console.log('Audio adapters ready. Playback permission is checked separately; no account keys are printed or changed.');
