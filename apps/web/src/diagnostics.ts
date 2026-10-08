type DiagnosticKind='runtime'|'framework'|'network'|'playback'|'socket'|'background'|'resource';
type Diagnostic={platform:'web';kind:DiagnosticKind;message:string;stack:string;version:string;route:string;code?:string;status?:number};
export function scrubDiagnostic(value:unknown,max=2000):string{
 return String(value??'').slice(0,12000)
  .replace(/\bBearer\s+[^\s,;"']+/gi,'Bearer [redacted]')
  .replace(/(["']?(?:password|passwd|token|secret|authorization|cookie|api[_-]?key|captchaToken)["']?\s*[:=]\s*)(?:"[^"\r\n]*"|'[^'\r\n]*'|[^\s,;}"']+)/gi,'$1[redacted]')
  .replace(/(?:mongodb(?:\+srv)?|postgres(?:ql)?|redis):\/\/[^\s<>"')]+/gi,'[connection]')
  .replace(/\b(?:cmp_live_|sk_live_)[\w-]+/g,'[redacted]')
  .replace(/\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/gi,'[email]')
  .replace(/(?:[A-Z]:[\\/]Users[\\/]|\/Users\/|\/home\/)[^\s\\/]+/gi,'[user-path]')
  .replace(/https?:\/\/[^\s<>"')]+/gi,value=>{try{const url=new URL(value);return url.origin+url.pathname;}catch{return '[url]';}})
  .replace(/\?[^\s)\]]+/g,'?[redacted]').replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/g,'').slice(0,max);
}
const queue:Diagnostic[]=[],seen=new Map<string,number>();
let installed=false,sending=false,timer:ReturnType<typeof setTimeout>|undefined,retry=30000;
export function resetDiagnostics(){queue.length=0;seen.clear();if(timer)clearTimeout(timer);timer=undefined;retry=30000;}
function schedule(delay=30000){if(timer||!queue.length)return;timer=setTimeout(()=>{timer=undefined;void flushDiagnostics();},delay);}
export function reportError(error:unknown,kind:DiagnosticKind='background',details:{code?:string;status?:number;stack?:string}={}){
 const value=error instanceof Error?error.message:typeof error==='string'?error:'Unknown application error';
 if((error as Error)?.name==='AbortError'||!value.trim())return;
 const event:Diagnostic={platform:'web',kind,message:scrubDiagnostic(value),stack:scrubDiagnostic(details.stack||(error instanceof Error?error.stack:''),8000),version:import.meta.env.VITE_APP_VERSION||'0.1.0',route:location.pathname+(location.hash.split('?')[0]||''),...(details.code?{code:scrubDiagnostic(details.code,100)}:{}),...(details.status?{status:details.status}:{})};
 const key=kind+event.message;if(Date.now()-(seen.get(key)||0)<60000)return;
 if(seen.size>=100)seen.delete(seen.keys().next().value!);seen.set(key,Date.now());
 if(queue.length>=30)queue.shift();queue.push(event);schedule(1000);
}
export async function flushDiagnostics(){
 if(sending||!queue.length||!navigator.onLine)return;
 sending=true;const events=queue.slice(0,10);
 try{const response=await fetch('/api/diagnostics/events',{method:'POST',headers:{'Content-Type':'application/json'},credentials:'include',body:JSON.stringify({events}),keepalive:true});if(response.ok||response.status===400||response.status===413){for(const event of events){const index=queue.indexOf(event);if(index>=0)queue.splice(index,1);}retry=30000;}else retry=Math.min(retry*2,300000);}
 catch{retry=Math.min(retry*2,300000);}finally{sending=false;schedule(retry);}
}
export function installDiagnostics(){
 if(installed)return;installed=true;
 window.addEventListener('error',(event:Event)=>{if(event instanceof ErrorEvent)reportError(event.error||event.message,'runtime');else if(event.target instanceof HTMLImageElement||event.target instanceof HTMLScriptElement)reportError('Resource failed to load: '+scrubDiagnostic(event.target.src),'resource');},true);
 window.addEventListener('unhandledrejection',event=>reportError(event.reason,'runtime'));
 window.addEventListener('online',()=>{void flushDiagnostics();});
 document.addEventListener('visibilitychange',()=>{if(document.hidden)void flushDiagnostics();});
}
