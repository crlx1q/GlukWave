import dgram from 'node:dgram';
import {config,validateConfig} from './config.js';
import {createApp} from './app.js';

validateConfig();const service=await createApp(config);
service.server.listen(config.port,config.host,()=>{service.ctx.log.info(`GlukWave ${config.env} · ${config.host}:${config.port} · ${config.storage}/${config.objectStorage}`);service.ctx.log.info(`Web ${config.appUrl} · credentials ${config.production?'production':'local .env'} · music cache on devices`);});
let discovery=null;if(config.lanDiscovery){discovery=dgram.createSocket('udp4');const cooldown=new Map();discovery.on('message',(message,remote)=>{if(message.toString()!=='GLUKWAVE_DISCOVER_V1')return;const last=cooldown.get(remote.address)||0;if(Date.now()-last<1000)return;cooldown.set(remote.address,Date.now());if(cooldown.size>1000)cooldown.clear();discovery.send(Buffer.from(JSON.stringify({name:'GlukWave',version:1,port:config.port})),remote.port,remote.address);});discovery.on('error',err=>service.ctx.log.warn({message:err.message},'LAN discovery unavailable'));discovery.bind(config.discoveryPort,'0.0.0.0');}
let shuttingDown=false;async function shutdown(){if(shuttingDown)return;shuttingDown=true;discovery?.close();await service.close();process.exit(0);}process.on('SIGINT',shutdown);process.on('SIGTERM',shutdown);
