import dgram from 'node:dgram';
import {config,validateConfig} from './config.js';
import {createApp} from './app.js';
import {openServerConsole} from './console-ui.js';

validateConfig();const service=await createApp(config);
let closeConsole=()=>{};
service.server.listen(config.port,config.host,()=>{closeConsole=openServerConsole(config,service.ctx,shutdown);service.ctx.log.info('GlukWave is ready');});
let discovery=null;if(config.lanDiscovery){discovery=dgram.createSocket('udp4');const cooldown=new Map();discovery.on('message',(message,remote)=>{if(message.toString()!=='GLUKWAVE_DISCOVER_V1')return;const last=cooldown.get(remote.address)||0;if(Date.now()-last<1000)return;cooldown.set(remote.address,Date.now());if(cooldown.size>1000)cooldown.clear();discovery.send(Buffer.from(JSON.stringify({name:'GlukWave',version:1,port:config.port})),remote.port,remote.address);});discovery.on('error',err=>service.ctx.log.warn({message:err.message},'LAN discovery unavailable'));discovery.bind(config.discoveryPort,'0.0.0.0');}
let shuttingDown=false;async function shutdown(exitCode=0){if(shuttingDown)return;shuttingDown=true;closeConsole();discovery?.close();await service.close();process.exit(typeof exitCode==='number'?exitCode:0);}process.on('SIGINT',shutdown);process.on('SIGTERM',shutdown);
async function fatal(error,code){
  if(shuttingDown)return;
  const deadline=setTimeout(()=>process.exit(1),5000);deadline.unref();
  service.ctx.log.error({err:error instanceof Error?error:new Error(String(error)),code},'Fatal server error');
  // Drain the diagnostic write before closing storage; never continue in a broken process.
  try{await shutdown(1);}catch{process.exit(1);}
}
process.on('unhandledRejection',error=>{void fatal(error,'UNHANDLED_REJECTION');});
process.on('uncaughtException',error=>{void fatal(error,'UNCAUGHT_EXCEPTION');});
service.server.on('error',error=>{void fatal(error,'SERVER_LISTEN');});
