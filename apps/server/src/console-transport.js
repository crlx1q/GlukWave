import pretty from 'pino-pretty';
import {stripVTControlCharacters} from 'node:util';

const safe=value=>stripVTControlCharacters(String(value??'')).replace(/[\r\n\t\x00-\x1f\x7f]/g,' ').slice(0,800);
export default function(options={}){
  return pretty({colorize:options.colorize,translateTime:'HH:MM:ss',ignore:'pid,hostname,method,path,status,ms,code',singleLine:true,levelFirst:false,messageFormat:record=>{
    const request=record.method&&record.path?`${safe(record.method)} ${safe(record.path)}${record.status?'  '+record.status:''}${Number.isFinite(record.ms)?'  '+record.ms+'ms':''}  `:'';
    return request+safe(record.msg)+(record.code?'  ['+safe(record.code)+']':'');
  }});
}
