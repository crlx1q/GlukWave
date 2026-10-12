import fs from 'node:fs';
import path from 'node:path';
import {spawn} from 'node:child_process';
import {fail,HttpError} from '../util.js';

export function createExtractorRuntime(config,{run}={}){
  const settings=config.extractors||{},directory=path.join(config.root,'work/tools/extractors');
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
  // Readiness checks must never import yt-dlp, run pip or block the API thread.
  // The bounded real job verifies modules; missing modules have a retry cooldown.
  const python=settings.python||firstExisting([executable('ytdlp'),path.join(config.root,'.venv',process.platform==='win32'?'Scripts/python.exe':'bin/python'),path.join(config.root,'venv',process.platform==='win32'?'Scripts/python.exe':'bin/python'),'/opt/extractors/ytdlp/bin/python',systemPython].filter(Boolean));
  const spotdlPython=settings.spotdlPython||firstExisting([executable('spotdl'),path.join(config.root,'.venv',process.platform==='win32'?'Scripts/python.exe':'bin/python'),'/opt/extractors/spotdl/bin/python',python].filter(Boolean));
  const deno=settings.deno||firstExisting([path.join(directory,'deno',process.platform==='win32'?'deno.exe':'deno'),'/usr/local/bin/deno','/usr/bin/deno']);
  const script=path.join(config.root,'apps/server/extractors/bridge.py'),queue=[],children=new Set(),limit=settings.concurrency||1;
  const configured={youtube:!!python&&fs.existsSync(python),soundcloud:!!python&&fs.existsSync(python),spotify:!!spotdlPython&&fs.existsSync(spotdlPython)};
  const unavailableUntil=new Map();let versionJob=null;
  let active=0,closed=false,completed=0,failed=0;
  function stop(processHandle){
    if(process.platform==='win32'&&processHandle.pid){const kill=spawn('taskkill',['/PID',String(processHandle.pid),'/T','/F'],{windowsHide:true,stdio:'ignore'});kill.on('error',()=>processHandle.kill());}
    else {try{process.kill(-processHandle.pid,'SIGKILL');}catch{processHandle.kill('SIGKILL');}}
  }
  const hasPython=adapter=>{
    if(closed||settings.enabled===false)return false;
    if(config.env==='test'&&!run)return false;
    if((unavailableUntil.get(adapter)||0)>Date.now())return false;
    if(run)return true;
    return !!configured[adapter];
  };
  const available=adapter=>{
    if(closed||settings.enabled===false)return false;
    if(adapter==='soundcloud')return true;
    return hasPython(adapter);
  };
  async function execute(adapter,request){
    if(!hasPython(adapter))fail(503,'EXTRACTOR_UNAVAILABLE','Этот источник временно недоступен.');
    if(closed||queue.length>=16)fail(503,'EXTRACTOR_BUSY','Музыка загружается. Повтори через немного времени.');
    if(active>=limit)await new Promise((resolve,reject)=>{
      const waiting={resolve:()=>{clearTimeout(timer);resolve();},reject:error=>{clearTimeout(timer);reject(error);}};
      const timer=setTimeout(()=>{
        const index=queue.indexOf(waiting);if(index<0)return;queue.splice(index,1);failed++;
        reject(new HttpError(503,'EXTRACTOR_BUSY','Музыка загружается. Повтори чуть позже.'));
      },settings.queueTimeout||15000);timer.unref();queue.push(waiting);
    });else active++;
    try{
      if(closed||!hasPython(adapter))fail(503,'EXTRACTOR_UNAVAILABLE','Этот источник временно недоступен.');
      const result=run?await run(adapter,request):await child(adapter,request);completed++;return result;
    }catch(error){failed++;if(error.code==='EXTRACTOR_MODULE')unavailableUntil.set(adapter,Date.now()+60000);throw error;}finally{const waiting=queue.shift();if(waiting)waiting.resolve();else active--;}
  }
  function child(adapter,request){return new Promise((resolve,reject)=>{
    const environment=Object.fromEntries(['PATH','SystemRoot','WINDIR','TEMP','TMP','HOME','USERPROFILE','LOCALAPPDATA'].filter(key=>process.env[key]).map(key=>[key,process.env[key]]));
    Object.assign(environment,{PYTHONIOENCODING:'utf-8',PYTHONUTF8:'1',PYTHONDONTWRITEBYTECODE:'1'});
    const processHandle=spawn(adapter==='spotify'?spotdlPython:python,['-B',script],{shell:false,windowsHide:true,detached:process.platform!=='win32',env:environment,stdio:['pipe','pipe','pipe']});
    children.add(processHandle);let size=0,buffers=[],failure=null;
    const timer=setTimeout(()=>{failure=new Error('Extractor timeout');failure.code='EXTRACTOR_TIMEOUT';stop(processHandle);},settings.timeout||45000);timer.unref();
    processHandle.stdout.on('data',chunk=>{size+=chunk.length;if(size>2*1024*1024){if(!failure){failure=new Error('Extractor output limit');failure.code='EXTRACTOR_FORMAT';stop(processHandle);}}else buffers.push(chunk);});
    processHandle.stderr.resume();processHandle.stdin.on('error',()=>{});
    processHandle.once('error',error=>{failure=error;});
    processHandle.once('close',code=>{
      clearTimeout(timer);children.delete(processHandle);
      if(failure)return reject(new HttpError(502,failure.code||'EXTRACTOR_UNAVAILABLE','Не удалось получить музыку. Повтори позже.'));
      let response;try{response=JSON.parse(Buffer.concat(buffers).toString('utf8'));}
      catch{return reject(new HttpError(502,'EXTRACTOR_FORMAT','Источник вернул неизвестный формат.'));}
      if(code!==0||!response.ok){
        const errorCode=['EXTRACTOR_MODULE','EXTRACTOR_FORMAT','EXTRACTOR_UPSTREAM'].includes(response?.code)?response.code:'EXTRACTOR_UPSTREAM';
        return reject(new HttpError(502,errorCode,'Не удалось получить аудиопоток. Попробуй позже или выбери другой источник.',{type:String(response?.type||'').slice(0,80)}));
      }
      resolve(response.result);
    });
    processHandle.stdin.end(JSON.stringify({...request,node:process.execPath,...(fs.existsSync(deno)?{deno}:{})}));
  });}
  return {available,hasPython,execute,stats:()=>({active,queued:queue.length,completed,failed,limit}),async versions(){
    if(!versionJob)versionJob=(async()=>{const targets=spotdlPython===python?['youtube']:['youtube','spotify'];const values=await Promise.allSettled(targets.map(adapter=>execute(adapter,{action:'versions'})));const result=Object.fromEntries(values.map((value,index)=>[targets[index],value.status==='fulfilled'?value.value:{available:false}]));if(targets.length===1)result.spotify={...result.youtube};return result;})().finally(()=>{versionJob=null;});
    return versionJob;
  },async close(){closed=true;for(const waiting of queue.splice(0))waiting.reject(new Error('Service closed'));await Promise.all([...children].map(child=>new Promise(resolve=>{child.once('close',resolve);stop(child);})));}};
}
