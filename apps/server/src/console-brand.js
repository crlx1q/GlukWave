import {stripVTControlCharacters} from 'node:util';

const reset='\x1b[0m';
const tones={violet:[184,163,230],mint:[133,219,189],muted:[139,146,164],ink:[238,234,243],amber:[241,196,123],red:[244,139,155]};
const basic={violet:95,mint:92,muted:90,ink:97,amber:93,red:91};
export const waveAscii=[
  ':-          #@@@:          @@@@-    ',
  '*@@        #@@@@@#        @@@@@@@   ',
  '*@@@-      @@@@@@@@      +@@@@@@@@. ',
  ' %@@@#    @@@@-#@@@@:    @@@%.+@@@@+',
  '  *@@@@  #@@@    @@@@*  @@@@    @@@@%',
  '    @@@@@@@@-     @@@@@@@@@.     #@@@.',
  '     @@@@@@@       -@@@@@@#       .@@',
  '      *@@@@         .@@@@@          *',
];
export const safeConsole=value=>stripVTControlCharacters(String(value??'')).replace(/[\r\n\t\x00-\x1f\x7f]/g,' ').slice(0,800);
const clip=(value,width)=>{const characters=[...safeConsole(value)];return characters.length>width?characters.slice(0,Math.max(0,width-1)).join('')+'…':characters.join('');};
const padded=(value,width)=>{const text=clip(value,width);return text+' '.repeat(Math.max(0,width-[...text].length));};
const level=color=>color===true?3:[1,2,3].includes(color)?color:0;
function rgbColor(rgb,color,tone='violet'){
  if(!level(color))return '';
  if(level(color)===1)return `\x1b[${basic[tone]}m`;
  if(level(color)===2){const cube=rgb.map(channel=>Math.round(channel/255*5));return `\x1b[38;5;${16+36*cube[0]+6*cube[1]+cube[2]}m`;}
  return `\x1b[38;2;${rgb.join(';')}m`;
}
export const paintConsole=(value,tone,color)=>level(color)?rgbColor(tones[tone],color,tone)+value+reset:value;
export function consoleColorLevel(output=process.stdout,env=process.env){
  if(Object.hasOwn(env,'NO_COLOR')||env.FORCE_COLOR==='0')return 0;
  if(['1','2','3'].includes(env.FORCE_COLOR))return Number(env.FORCE_COLOR);
  if(!output.isTTY||env.TERM==='dumb')return 0;
  if(env.COLORTERM==='truecolor'||env.COLORTERM==='24bit'||env.WT_SESSION||env.TERM_PROGRAM==='vscode')return 3;
  if(process.platform==='win32'&&!env.TERM)return 3;
  return /256color/.test(env.TERM||'')?2:1;
}
export function consoleGradient(value,{color=false}={}){
  const text=safeConsole(value),characters=[...text];if(!level(color))return text;
  if(level(color)===1)return paintConsole(text,'violet',color);
  return characters.map((character,index)=>{
    if(character===' ')return character;
    const t=index/Math.max(1,characters.length-1),rgb=tones.violet.map((start,channel)=>Math.round(start+(tones.mint[channel]-start)*t));
    return rgbColor(rgb,color)+character;
  }).join('')+reset;
}
function displayUrl(value){try{const url=new URL(value);url.username='';url.password='';url.search='';url.hash='';return url.toString();}catch{return safeConsole(value);}}
export function formatConsoleCard(config,snapshot,{color=false,columns=80,logo=true}={}){
  const width=Math.min(88,Math.max(18,Math.floor(columns||80)-2)),inside=width-4;
  const row=(value='',tone='ink')=>' '+paintConsole('│','muted',color)+' '+paintConsole(padded(value,inside),tone,color)+' '+paintConsole('│','muted',color);
  const edge=(left,right)=>' '+paintConsole(left+'─'.repeat(width-2)+right,'muted',color);
  const section=name=>row('── '+name,'muted');
  const metric=value=>Number.isFinite(Number(value))?Math.max(0,Number(value)):0;
  const elapsed=Math.floor(metric(snapshot.uptime)),hours=Math.floor(elapsed/3600),minutes=Math.floor(elapsed/60)%60,seconds=elapsed%60;
  const duration=`${hours?hours+':':''}${hours?String(minutes).padStart(2,'0'):minutes}:${String(seconds).padStart(2,'0')}`;
  const cpu=Number.isFinite(snapshot.cpuPercent)?metric(snapshot.cpuPercent).toFixed(1)+'%':'warming up';
  const lines=[''];
  if(logo&&inside>=40){
    const artWidth=Math.max(...waveAscii.map(line=>line.length)),indent=' '.repeat(1+Math.floor((width-artWidth)/2));
    lines.push(...waveAscii.map(line=>indent+consoleGradient(line,{color})), '');
  }
  lines.push(' '+consoleGradient(clip('GLUK WAVE  /  SERVER STUDIO',width),{color}),edge('╭','╮'),
    row('● ONLINE  ·  '+(config.production?'Production':'Local development'),'mint'),row(),section('CONNECTION'),
    row('Listen     '+safeConsole(config.host)+':'+safeConsole(config.port)),row('Web        '+displayUrl(config.appUrl)),
    row('Database   '+(config.storage==='mongo'?'MongoDB':'SQLite · local')),
    row('Media      '+(config.objectStorage==='r2'?'Cloudflare R2 · private':'Local files · private')),row(),section('LIVE SESSION'),
    row(`${metric(snapshot.clients)} connected clients  ·  ${metric(snapshot.rooms)} rooms`,'violet'),
    row('Uptime     '+duration),row('Memory     '+metric(snapshot.memoryMB)+' MB RSS  ·  '+metric(snapshot.heapMB)+' MB heap'),row('CPU        '+cpu+' / one core'),row(),section('API ACTIVITY'),
    row('Requests   '+metric(snapshot.requests)),row('Failures   '+metric(snapshot.failures),metric(snapshot.failures)?'amber':'muted'),
    row('Latency    '+metric(snapshot.averageMs)+' ms average'),edge('╰','╯'),
    ' '+paintConsole(clip('s / Enter  status   h  help   q  stop',width),'muted',color),'');
  return lines.join('\n');
}
