import fs from 'node:fs';
import path from 'node:path';
import {spawn,spawnSync} from 'node:child_process';
import {fail,HttpError} from '../util.js';

function testPythonModule(pythonPath,moduleName,extraPaths=[]){
  if(!pythonPath||!fs.existsSync(pythonPath))return false;
  try{
    const code=extraPaths.length
      ?`import sys; [sys.path.insert(0, p) for p in ${JSON.stringify(extraPaths)}]; import ${moduleName}`
      : `import ${moduleName}`;
    const res=spawnSync(pythonPath,['-c',code],{windowsHide:true,timeout:5000,stdio:'ignore'});
    return res.status===0;
  }
  catch{return false;}
}

export function createExtractorRuntime(config,{run}={}){
  const settings=config.extractors||{},directory=path.join(config.root,'work/tools/extractors');
  const vendorDir=path.join(config.root,'apps/server/extractors/vendor');
  const vendorZips=fs.existsSync(vendorDir)
    ? fs.readdirSync(vendorDir).filter(f=>f.endsWith('.zip')||f.endsWith('.whl')).map(f=>path.join(vendorDir,f))
    : [];
  const executable=name=>path.join(directory,name,process.platform==='win32'?'Scripts/python.exe':'bin/python');
  const firstExisting=paths=>paths.find(value=>value&&fs.existsSync(value))||paths[0];
  function findSystemExecutable(names){
    const pathDirs=(process.env.PATH||'').split(path.delimiter).filter(Boolean);
    for(const dir of pathDirs){
      for(const name of names){
        const full=path.join(dir,name);
        if(fs.existsSync(full))return full;
      }
    }
    return null;
  }
  const systemPython=findSystemExecutable(process.platform==='win32'?['python.exe','python3.exe','py.exe']:['python3','python']);
  if(config.env!=='test'&&!run){
    const venvPython=executable('ytdlp');
    const hasVendor=vendorZips.length>0&&testPythonModule(systemPython,'yt_dlp',vendorZips);
    if(!hasVendor&&(!fs.existsSync(venvPython)||!testPythonModule(venvPython,'yt_dlp'))){
      try{
        const setupScript=path.join(config.root,'scripts/prepare-extractors.mjs');
        if(fs.existsSync(setupScript)){
          spawnSync(process.execPath,[setupScript,'--adapter','ytdlp'],{cwd:config.root,windowsHide:true,timeout:120000,stdio:'ignore'});
        }
      }catch{}
    }
  }
  const python=settings.python||firstExisting([executable('ytdlp'),path.join(config.root,'.venv',process.platform==='win32'?'Scripts/python.exe':'bin/python'),path.join(config.root,'venv',process.platform==='win32'?'Scripts/python.exe':'bin/python'),'/opt/extractors/ytdlp/bin/python',systemPython].filter(Boolean));
  const spotdlPython=settings.spotdlPython||firstExisting([executable('spotdl'),path.join(config.root,'.venv',process.platform==='win32'?'Scripts/python.exe':'bin/python'),'/opt/extractors/spotdl/bin/python',python].filter(Boolean));
  const deno=settings.deno||firstExisting([path.join(directory,'deno',process.platform==='win32'?'deno.exe':'deno'),'/usr/local/bin/deno','/usr/bin/deno']);
  const script=path.join(config.root,'apps/server/extractors/bridge.py'),queue=[],children=new Set(),limit=settings.concurrency||1;
  let active=0,closed=false,completed=0,failed=0;
  function stop(processHandle){
    if(process.platform==='win32'&&processHandle.pid){const kill=spawn('taskkill',['/PID',String(processHandle.pid),'/T','/F'],{windowsHide:true,stdio:'ignore'});kill.on('error',()=>processHandle.kill());}
    else {try{process.kill(-processHandle.pid,'SIGKILL');}catch{processHandle.kill('SIGKILL');}}
  }
  const hasPython=adapter=>{
    if(settings.enabled===false)return false;
    if(config.env==='test'&&!run)return false;
    if(run)return true;
    const py=adapter==='spotify'?(spotdlPython||python):python;
    if(!py||!fs.existsSync(py))return false;
    if(adapter==='spotify')return testPythonModule(py,'spotdl');
    if(adapter==='youtube')return testPythonModule(py,'yt_dlp',vendorZips);
    return false;
  };
  const available=adapter=>{
    if(settings.enabled===false)return false;
    if(adapter==='soundcloud')return true;
    return hasPython(adapter);
  };
  async function execute(adapter,request){
    if(!hasPython(adapter))fail(503,'EXTRACTOR_UNAVAILABLE','Этот источник временно недоступен.');
    if(closed||queue.length>=16)fail(503,'EXTRACTOR_BUSY','Музыка загружается. Повтори через немного времени.');
    if(active>=limit)await new Promise((resolve,reject)=>queue.push({resolve,reject}));else active++;
    try{
      if(closed)fail(503,'EXTRACTOR_UNAVAILABLE','Этот источник временно недоступен.');
      const result=run?await run(adapter,request):await child(adapter,request);completed++;return result;
    }catch(error){failed++;throw error;}finally{const waiting=queue.shift();if(waiting)waiting.resolve();else active--;}
  }
  function child(adapter,request){return new Promise((resolve,reject)=>{
    const environment=Object.fromEntries(['PATH','SystemRoot','WINDIR','TEMP','TMP','HOME','USERPROFILE','LOCALAPPDATA'].filter(key=>process.env[key]).map(key=>[key,process.env[key]]));
    Object.assign(environment,{PYTHONIOENCODING:'utf-8',PYTHONUTF8:'1',PYTHONDONTWRITEBYTECODE:'1'});
    const processHandle=spawn(adapter==='spotify'?spotdlPython:python,['-B',script],{shell:false,windowsHide:true,detached:process.platform!=='win32',env:environment,stdio:['pipe','pipe','pipe']});
    children.add(processHandle);let size=0,buffers=[],failure=null;
    const timer=setTimeout(()=>{failure=new Error('Extractor timeout');failure.code='EXTRACTOR_TIMEOUT';stop(processHandle);},settings.timeout||45000);timer.unref();
    processHandle.stdout.on('data',chunk=>{size+=chunk.length;if(size>2*1024*1024){failure=new Error('Extractor output limit');failure.code='EXTRACTOR_FORMAT';stop(processHandle);}else buffers.push(chunk);});
    processHandle.stderr.resume();processHandle.stdin.on('error',()=>{});
    processHandle.once('error',error=>{failure=error;});
    processHandle.once('close',code=>{
      clearTimeout(timer);children.delete(processHandle);
      if(failure)return reject(new HttpError(502,failure.code||'EXTRACTOR_UNAVAILABLE','Не удалось получить музыку. Повтори позже.'));
      let response;try{response=JSON.parse(Buffer.concat(buffers).toString('utf8'));}
      catch{return reject(new HttpError(502,'EXTRACTOR_FORMAT','Источник вернул неизвестный формат.'));}
      if(code!==0||!response.ok){
        const detail=response?.message?` (${response.message})`:(response?.type?` (${response.type})`:'');
        return reject(new HttpError(502,response?.code||'EXTRACTOR_UPSTREAM',`Трек сейчас недоступен${detail}. Попробуй другой источник.`,response));
      }
      resolve(response.result);
    });
    processHandle.stdin.end(JSON.stringify({...request,node:process.execPath,...(fs.existsSync(deno)?{deno}:{})}));
  });}
  return {available,hasPython,execute,stats:()=>({active,queued:queue.length,completed,failed,limit}),async versions(){const values=await Promise.allSettled(['youtube','spotify'].map(adapter=>execute(adapter,{action:'versions'})));return Object.fromEntries(values.map((value,index)=>[['youtube','spotify'][index],value.status==='fulfilled'?value.value:{available:false}]));},async close(){closed=true;for(const waiting of queue.splice(0))waiting.reject(new Error('Service closed'));await Promise.all([...children].map(child=>new Promise(resolve=>{child.once('close',resolve);stop(child);})));}};
}
