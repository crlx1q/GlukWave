import pretty from 'pino-pretty';
import {paintConsole,safeConsole} from './console-brand.js';

export function formatConsoleLog(record,{color=false}={}){
  const safe=safeConsole;
  const status=Number(record.status),tone=status>=500?'red':status>=400?'amber':'mint';
  const elapsed=Number.isFinite(record.ms)?(record.ms>=1000?(record.ms/1000).toFixed(2)+'s':Math.max(0,Math.round(record.ms))+'ms'):'';
  const request=record.method&&record.path?paintConsole(safe(record.method).padEnd(6),'violet',color)+' '+safe(record.path)+
    (record.status?'  '+paintConsole(safe(record.status),tone,color):'')+(elapsed?'  '+paintConsole(elapsed,'muted',color):'')+'  ':'';
  return request+safe(record.msg)+(record.code?'  '+paintConsole('['+safe(record.code)+']','amber',color):'');
}
export default function(options={}){
  const color=options.colorLevel??options.colorize??false;
  return pretty({colorize:Boolean(color),translateTime:'HH:MM:ss',ignore:'pid,hostname,method,path,status,ms,code',singleLine:true,levelFirst:false,messageFormat:record=>formatConsoleLog(record,{color})});
}
