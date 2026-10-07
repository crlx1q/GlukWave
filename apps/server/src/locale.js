import fs from 'node:fs';
import path from 'node:path';
import {isIP} from 'node:net';
import {gunzipSync} from 'node:zlib';

export const supportedLanguages=[
  {code:'en',name:'English',nativeName:'English'},
  {code:'ru',name:'Russian',nativeName:'Русский'},
  {code:'kk',name:'Kazakh',nativeName:'Қазақша'},
  {code:'uk',name:'Ukrainian',nativeName:'Українська'},
  {code:'de',name:'German',nativeName:'Deutsch'},
  {code:'es',name:'Spanish',nativeName:'Español'},
];
export const languageCodes=supportedLanguages.map(language=>language.code);
export function browserLanguage(header=''){
  if(typeof header!=='string')return null;
  const candidates=header.slice(0,1024).split(',').map((part,index)=>{
    const [tag,...parameters]=part.trim().split(';');
    const quality=parameters.find(parameter=>parameter.trim().startsWith('q='));
    const q=quality===undefined?1:Number(quality.trim().slice(2));
    return {code:tag.toLowerCase().split('-')[0],q,index};
  }).filter(value=>languageCodes.includes(value.code)&&Number.isFinite(value.q)&&value.q>0&&value.q<=1);
  candidates.sort((a,b)=>b.q-a.q||a.index-b.index);return candidates[0]?.code||null;
}
export function countryLanguage(country){
  if(country==='KZ')return 'kk';if(country==='UA')return 'uk';
  if(['RU','BY'].includes(country))return 'ru';
  if(['DE','AT','LI'].includes(country))return 'de';
  if(['ES','MX','AR','BO','CL','CO','CR','CU','DO','EC','SV','GT','HN','NI','PA','PY','PE','PR','UY','VE','GQ'].includes(country))return 'es';
  if(['US','GB','AU','NZ','CA','IE'].includes(country))return 'en';
  return null;
}
export function ipNumber(input){
  if(typeof input!=='string')return null;let ip=input.toLowerCase();
  if(ip.includes('%'))return null;
  if(ip.startsWith('::ffff:')&&isIP(ip.slice(7))===4)ip=ip.slice(7);
  const family=isIP(ip);if(!family)return null;
  if(family===4){const parts=ip.split('.').map(Number),[a,b]=parts;
    if(a===0||a===10||a===127||a>=224||(a===169&&b===254)||(a===172&&b>=16&&b<=31)||(a===192&&b===168)||(a===100&&b>=64&&b<=127)||(a===198&&[18,19].includes(b)))return null;
    return {family,value:parts.reduce((value,part)=>(value<<8n)+BigInt(part),0n)};
  }
  // Mapped hexadecimal IPv4 addresses have the same lookup and private-address rules.
  if(ip.includes('.')){const lastColon=ip.lastIndexOf(':'),parts=ip.slice(lastColon+1).split('.').map(Number);ip=ip.slice(0,lastColon+1)+((parts[0]<<8)+parts[1]).toString(16)+':'+((parts[2]<<8)+parts[3]).toString(16);}
  const split=ip.split('::');if(split.length>2)return null;
  let left=split[0]?split[0].split(':'):[],right=split[1]?split[1].split(':'):[];
  const groups=split.length===2?[...left,...Array(8-left.length-right.length).fill('0'),...right]:left;
  if(groups.length!==8)return null;
  const value=groups.reduce((result,group)=>(result<<16n)+BigInt('0x'+group),0n);
  if((value>>32n)===0xffffn){const v4=Number(value&0xffffffffn);return ipNumber([v4>>>24,(v4>>>16)&255,(v4>>>8)&255,v4&255].join('.'));}
  // Only globally routable IPv6 unicast is useful for country detection.
  if((value>>125n)!==1n)return null;
  return {family,value};
}
function loadRanges(file){
  if(!fs.existsSync(file))return [];
  const content=gunzipSync(fs.readFileSync(file),{maxOutputLength:100*1024*1024}).toString('utf8'),ranges=[];
  let previous=-1n;
  for(const line of content.split('\n')){
    if(!line.trim())continue;const [start,end,country]=line.trim().split(',');
    if(!/^\d+$/.test(start)||!/^\d+$/.test(end)||!/^[A-Z]{2}$/.test(country))throw new Error('Invalid country database row');
    const lower=BigInt(start),upper=BigInt(end);if(lower>upper||lower<=previous)throw new Error('Unsorted or overlapping country database');
    ranges.push({lower,upper,country});previous=upper;
  }
  return ranges;
}
export function createCountryLookup(directory,log){
  const databases={4:[],6:[]};
  for(const family of [4,6]){try{databases[family]=loadRanges(path.join(directory,`ipv${family}.csv.gz`));}catch(error){log?.warn({family,message:error.message},'Country lookup unavailable');}}
  return input=>{
    const ip=ipNumber(input);if(!ip)return null;const rows=databases[ip.family];let lo=0,hi=rows.length-1;
    while(lo<=hi){const middle=(lo+hi)>>1,row=rows[middle];if(ip.value<row.lower)hi=middle-1;else if(ip.value>row.upper)lo=middle+1;else return row.country;}
    return null;
  };
}
export function localeFor(req,lookup){
  // Express honours forwarded IP only when the owner's trust proxy setting permits it.
  // CF-IPCountry and arbitrary visitor-supplied location headers are never trusted.
  const country=lookup(req.ip||req.socket?.remoteAddress)||null;
  const regional=countryLanguage(country),browser=browserLanguage(req.headers?.['accept-language']);
  return {language:regional||browser||'en',country,source:regional?'ip':browser?'browser':'default',supported:supportedLanguages,defaultLanguage:'en'};
}
export function setupLocale(app,ctx,override){
  const lookup=override||createCountryLookup(ctx.config.geoipDir||path.join(ctx.config.root,'apps/server/data/geoip'),ctx.log);
  ctx.localeFor=req=>localeFor(req,lookup);
  ctx.getLocale=(req,res)=>{const locale=ctx.localeFor(req);res.set('Cache-Control','private, no-store');res.set('Content-Language',locale.language);res.vary('Accept-Language');res.json(locale);};
}
