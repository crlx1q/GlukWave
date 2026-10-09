import readline from 'node:readline';
import {stripVTControlCharacters} from 'node:util';

const colors={violet:'\x1b[38;2;177;162;222m',mint:'\x1b[38;2;145;210;182m',muted:'\x1b[38;2;148;150;166m',ink:'\x1b[38;2;238;234;243m',reset:'\x1b[0m'};
const safe=value=>stripVTControlCharacters(String(value??'')).replace(/[\r\n\t\x00-\x1f\x7f]/g,' ').slice(0,180);
const paint=(value,tone,color)=>color?colors[tone]+value+colors.reset:value;
export function consoleStyle(config){const requested=process.env.CONSOLE_STYLE;return ['studio','compact','json'].includes(requested)?requested:config.production?'json':'studio';}
export function runtimeSnapshot(ctx){
  const sockets=ctx.io?.sockets.sockets;
  const rooms=ctx.io?.sockets.adapter.rooms;
  const metrics=ctx.metrics||{};
  return {clients:sockets?.size||0,rooms:rooms?[...rooms.keys()].filter(key=>key.startsWith('room:')).length:0,uptime:Math.floor(process.uptime()),memoryMB:Math.round(process.memoryUsage().rss/1048576),cpuPercent:ctx.resourceSnapshot?.().cpuOneCorePercent,requests:metrics.requests||0,failures:metrics.failures||0,averageMs:metrics.requests?Math.round(metrics.duration/metrics.requests):0};
}
export function formatConsoleCard(config,snapshot,{color=false,columns=80}={}){
  const width=Math.min(88,Math.max(44,columns-2)),inside=width-4;
  const row=(value='',tone='ink')=>' '+paint('│','muted',color)+' '+paint(safe(value).slice(0,inside).padEnd(inside),tone,color)+' '+paint('│','muted',color);
  const edge=(left,right)=>' '+paint(left+'─'.repeat(width-2)+right,'muted',color);
  const elapsed=snapshot.uptime||0,hours=Math.floor(elapsed/3600),minutes=Math.floor(elapsed/60)%60,seconds=elapsed%60;
  const duration=hours?`${hours}h ${minutes}m`:`${minutes}m ${String(seconds).padStart(2,'0')}s`;
  const endpoints=[['Listen',`${config.host}:${config.port}`],['Web',config.appUrl],['Database',config.storage==='mongo'?'MongoDB':'SQLite · local'],['Media',config.objectStorage==='r2'?'Cloudflare R2 · private':'Local files · private']];
  return ['',' '+paint('∿  GLUKWAVE','violet',color)+'  '+paint('SERVER STUDIO','muted',color),edge('╭','╮'),row('ONLINE  ·  '+(config.production?'Production':'Local development'),'mint'),row(),...endpoints.map(([name,value])=>row(name.padEnd(12)+safe(value))),row(),row(`${snapshot.clients||0} devices   ·   ${snapshot.rooms||0} listening rooms`,'violet'),row(`Uptime ${duration}   ·   Memory ${snapshot.memoryMB||0} MB   ·   CPU ${snapshot.cpuPercent??0}%`,'muted'),row(`${snapshot.requests||0} API requests   ·   ${snapshot.failures||0} failed   ·   ${snapshot.averageMs||0} ms average`,'muted'),edge('╰','╯'),' '+paint('s / Enter  status    h  help    q  graceful shutdown','muted',color),''].join('\n');
}
export function openServerConsole(config,ctx,onStop,{output=process.stdout,input=process.stdin}={}){
  if(consoleStyle(config)!=='studio')return ()=>{};
  const color=!process.env.NO_COLOR&&(output.isTTY||process.env.FORCE_COLOR==='1');
  const show=()=>output.write(formatConsoleCard(config,runtimeSnapshot(ctx),{color,columns:output.columns||80})+'\n');
  show();
  if(!input.isTTY||!output.isTTY)return ()=>{};
  const terminal=readline.createInterface({input,output,terminal:false});
  terminal.on('line',line=>{
    const command=line.trim().toLowerCase();
    if(command==='s'||!command)show();
    else if(command==='h')output.write('\n  s / Enter  Read current server status\n  q          Finish active work and stop the server\n  Ctrl+C     Graceful shutdown\n\n');
    else if(command==='q')void onStop();
    else output.write('  Unknown command. Press h for help.\n');
  });
  return ()=>terminal.close();
}
