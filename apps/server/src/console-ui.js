import readline from 'node:readline';
import {consoleColorLevel,formatConsoleCard} from './console-brand.js';
export {formatConsoleCard} from './console-brand.js';

export function consoleStyle(config){const requested=process.env.CONSOLE_STYLE;return ['studio','compact','json'].includes(requested)?requested:config.production?'json':'studio';}
export function runtimeSnapshot(ctx){
  const sockets=ctx.io?.sockets.sockets,rooms=ctx.io?.sockets.adapter.rooms,metrics=ctx.metrics||{},memory=process.memoryUsage();
  return {clients:sockets?.size||0,rooms:rooms?[...rooms.keys()].filter(key=>key.startsWith('room:')).length:0,uptime:Math.floor(process.uptime()),memoryMB:Math.round(memory.rss/1048576),heapMB:Math.round(memory.heapUsed/1048576),cpuPercent:ctx.resourceSnapshot?.().cpuOneCorePercent,requests:metrics.requests||0,failures:metrics.failures||0,averageMs:metrics.requests?Math.round(metrics.duration/metrics.requests):0};
}
export function openServerConsole(config,ctx,onStop,{output=process.stdout,input=process.stdin}={}){
  if(consoleStyle(config)!=='studio')return ()=>{};
  const show=(logo=false)=>output.write(formatConsoleCard(config,runtimeSnapshot(ctx),{color:consoleColorLevel(output),columns:output.columns||80,logo})+'\n');
  show(true);
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
