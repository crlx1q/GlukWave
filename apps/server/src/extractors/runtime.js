import fs from 'node:fs';
import path from 'node:path';
import {spawn} from 'node:child_process';
import {fail} from '../util.js';

export function createExtractorRuntime(config,{run}={}){
  const settings=config.extractors||{},directory=path.join(config.root,'work/tools/extractors');
  const executable=name=>path.join(directory,name,process.platform==='win32'?'Scripts/python.exe':'bin/python');
  const firstExisting=paths=>paths.find(value=>fs.existsSync(value))||paths[0];
  // Docker, project-local venv and conventional system venv deployments all
  // work without a Windows-specific path leaking into a Linux installation.
  const python=settings.python||firstExisting([executable('ytdlp'),'/opt/extractors/ytdlp/bin/python',path.join(config.root,'.venv/bin/python')]);
  const spotdlPython=settings.spotdlPython||firstExisting([executable('spotdl'),'/opt/extractors/spotdl/bin/python']);
  const deno=settings.deno||firstExisting([path.join(directory,'deno',process.platform==='win32'?'deno.exe':'deno'),'/usr/local/bin/deno','/usr/bin/deno']);
  const script=path.join(config.root,'apps/server/extractors/bridge.py'),queue=[],children=new Set(),limit=settings.concurrency||1;
  let active=0,closed=false,completed=0,failed=0;
  function stop(processHandle){
    if(process.platform==='win32'&&processHandle.pid){const kill=spawn('taskkill',['/PID',String(processHandle.pid),'/T','/F'],{windowsHide:true,stdio:'ignore'});kill.on('error',()=>processHandle.kill());}
    else {try{process.kill(-processHandle.pid,'SIGKILL');}catch{processHandle.kill('SIGKILL');}}
  }
  const available=adapter=>settings.enabled!==false&&(config.env!=='test'||!!run)&&(!!run||fs.existsSync(adapter==='spotify'?spotdlPython:python));
  async function execute(adapter,request){
    if(!available(adapter))fail(503,'EXTRACTOR_UNAVAILABLE','Этот источник временно недоступен.');
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
    processHandle.once('close',code=>{clearTimeout(timer);children.delete(processHandle);if(failure)return reject(Object.assign(new Error('Не удалось получить музыку. Повтори позже.'),{status:502,code:failure.code||'EXTRACTOR_UNAVAILABLE'}));let response;try{response=JSON.parse(Buffer.concat(buffers).toString('utf8'));}catch{return reject(Object.assign(new Error('Источник вернул неизвестный формат.'),{status:502,code:'EXTRACTOR_FORMAT'}));}if(code!==0||!response.ok)return reject(Object.assign(new Error('Трек сейчас недоступен. Попробуй другой источник.'),{status:502,code:response.code||'EXTRACTOR_UPSTREAM'}));resolve(response.result);});
    processHandle.stdin.end(JSON.stringify({...request,...(fs.existsSync(deno)?{deno}:{})}));
  });}
  return {available,execute,stats:()=>({active,queued:queue.length,completed,failed,limit}),async versions(){const values=await Promise.allSettled(['youtube','spotify'].map(adapter=>execute(adapter,{action:'versions'})));return Object.fromEntries(values.map((value,index)=>[['youtube','spotify'][index],value.status==='fulfilled'?value.value:{available:false}]));},async close(){closed=true;for(const waiting of queue.splice(0))waiting.reject(new Error('Service closed'));await Promise.all([...children].map(child=>new Promise(resolve=>{child.once('close',resolve);stop(child);})));}};
}
