import { t, getLanguageChoice, isLanguageChoice } from './locale';
import { defaultSettings, defaultAppearance, type Appearance, type PaletteMode, type PaletteColors, type Settings, type SettingsPatch } from './types';

const object=(value:unknown):Record<string,unknown>=>value&&typeof value==='object'&&!Array.isArray(value)?value as Record<string,unknown>:{};
const color=(value:unknown,fallback:string)=>typeof value==='string'&&/^#[\da-f]{6}$/i.test(value)?value.toLowerCase():fallback;
const number=(value:unknown,fallback:number,min:number,max:number)=>typeof value==='number'&&Number.isFinite(value)?Math.max(min,Math.min(max,value)):fallback;
function palette(value:unknown,fallback:PaletteColors):PaletteColors{const source=object(value);return {bg:color(source.bg,fallback.bg),surface:color(source.surface,fallback.surface),ink:color(source.ink,fallback.ink),accent:color(source.accent,fallback.accent)};}

export function normalizeSettings(value:unknown):Settings {
  const source=object(value),appearance=object(source.appearance),equalizer=object(source.equalizer);
  return {comments:source.comments!==false,lyricsUnderCover:source.lyricsUnderCover!==false,fontFamily:source.fontFamily==='nunito'||source.fontFamily==='system'?source.fontFamily:'manrope',fontScale:number(source.fontScale,1,.85,1.25),language:isLanguageChoice(source.language)?source.language:getLanguageChoice(),autoCache:typeof source.autoCache==='boolean'?source.autoCache:defaultSettings.autoCache,cacheLimitMB:number(source.cacheLimitMB,1024,64,16384),lyrics:typeof source.lyrics==='boolean'?source.lyrics:true,discordPresence:typeof source.discordPresence==='boolean'?source.discordPresence:true,notifications:source.notifications===true,theme:source.theme==='dark'||source.theme==='amoled'||source.theme==='system'?source.theme:'light',reducedMotion:source.reducedMotion===true,equalizer:{enabled:equalizer.enabled===true,preamp:number(equalizer.preamp,0,-12,12),bands:Array.from({length:10},(_,index)=>number(Array.isArray(equalizer.bands)?equalizer.bands[index]:undefined,0,-12,12))},playbackRate:number(source.playbackRate,1,.5,2),appearance:{light:palette(appearance.light,defaultAppearance.light),dark:palette(appearance.dark,defaultAppearance.dark),amoled:palette(appearance.amoled,defaultAppearance.amoled),radius:number(appearance.radius,24,8,38),speed:number(appearance.speed,1,.3,2),compact:appearance.compact===true,blur:appearance.blur!==false,waveStyle:appearance.waveStyle==='bloom'?'bloom':appearance.waveStyle==='particles'?'particles':'silk',cover3d:appearance.cover3d!==false,coverKind:appearance.coverKind==='cd'?'cd':'vinyl'}};
}

export function mergeSettings(current:Settings,partial:SettingsPatch):Settings {
  const appearance=partial.appearance;
  return normalizeSettings({...current,...partial,equalizer:{...current.equalizer,...partial.equalizer},appearance:{...current.appearance,...appearance,light:{...current.appearance.light,...appearance?.light},dark:{...current.appearance.dark,...appearance?.dark},amoled:{...current.appearance.amoled,...appearance?.amoled}}});
}

export function mergeSettingsPatches(current:SettingsPatch,partial:SettingsPatch):SettingsPatch {
  const result={...current,...partial,...((current.equalizer||partial.equalizer)?{equalizer:{...current.equalizer,...partial.equalizer}}:{})};
  if(!current.appearance&&!partial.appearance)return result;
  return {...result,appearance:{...current.appearance,...partial.appearance,...((current.appearance?.light||partial.appearance?.light)?{light:{...current.appearance?.light,...partial.appearance?.light}}:{}),...((current.appearance?.dark||partial.appearance?.dark)?{dark:{...current.appearance?.dark,...partial.appearance?.dark}}:{}),...((current.appearance?.amoled||partial.appearance?.amoled)?{amoled:{...current.appearance?.amoled,...partial.appearance?.amoled}}:{})}};
}

const settingsKey=(userId:string|null)=>`gw-settings:${userId||'guest'}`;
const pendingKey=(userId:string)=>`gw-settings-pending:${userId}`;
export function readLocalSettings(userId:string|null):Settings {try{return normalizeSettings(JSON.parse(localStorage.getItem(settingsKey(userId))||'null'));}catch{return normalizeSettings(null);}}
export function writeLocalSettings(userId:string|null,settings:Settings){try{const key=settingsKey(userId),value=JSON.stringify(settings);if(localStorage.getItem(key)!==value)localStorage.setItem(key,value);}catch{/* Preferences remain active when storage is unavailable. */}}
export function writeConfirmedSettings(userId:string,settings:Settings,revision:number){try{const key=`gw-settings-confirmed:${userId}`,value=JSON.stringify({settings,revision});if(localStorage.getItem(key)!==value)localStorage.setItem(key,value);}catch{/* Socket synchronization remains available. */}}
export function writePendingSettings(userId:string,partial:SettingsPatch){try{if(Object.keys(partial).length)localStorage.setItem(pendingKey(userId),JSON.stringify(partial));else localStorage.removeItem(pendingKey(userId));}catch{/* The current tab keeps the pending change in memory. */}}
export function normalizeSettingsPatch(value:unknown):SettingsPatch {
  try {
    const source=object(value),result:SettingsPatch={};
    for(const key of ['autoCache','lyrics','comments','lyricsUnderCover','discordPresence','notifications','reducedMotion'] as const)if(typeof source[key]==='boolean')result[key]=source[key];
    if(typeof source.fontScale==='number')result.fontScale=number(source.fontScale,1,.85,1.25);
    if(source.fontFamily==='manrope'||source.fontFamily==='nunito'||source.fontFamily==='system')result.fontFamily=source.fontFamily;
    if(typeof source.cacheLimitMB==='number')result.cacheLimitMB=number(source.cacheLimitMB,1024,64,16384);
    if(typeof source.playbackRate==='number')result.playbackRate=number(source.playbackRate,1,.5,2);
    if(source.equalizer&&typeof source.equalizer==='object'){
      const input=object(source.equalizer),equalizer:NonNullable<SettingsPatch['equalizer']>={};
      if(typeof input.enabled==='boolean')equalizer.enabled=input.enabled;
      if(typeof input.preamp==='number')equalizer.preamp=number(input.preamp,0,-12,12);
      if(Array.isArray(input.bands)&&input.bands.length===10)equalizer.bands=input.bands.map(value=>number(value,0,-12,12));
      if(Object.keys(equalizer).length)result.equalizer=equalizer;
    }
    if(isLanguageChoice(source.language))result.language=source.language;
    if(source.theme==='light'||source.theme==='dark'||source.theme==='amoled'||source.theme==='system')result.theme=source.theme;
    if(source.appearance&&typeof source.appearance==='object') {
      const input=object(source.appearance),appearance:NonNullable<SettingsPatch['appearance']>={};
      for(const mode of ['light','dark','amoled'] as const){const colors=object(input[mode]),next:Partial<PaletteColors>={};for(const key of ['bg','surface','ink','accent'] as const)if(typeof colors[key]==='string'&&/^#[\da-f]{6}$/i.test(colors[key]))next[key]=colors[key].toLowerCase();if(Object.keys(next).length)appearance[mode]=next;}
      if(typeof input.radius==='number')appearance.radius=number(input.radius,24,8,38);
      if(typeof input.speed==='number')appearance.speed=number(input.speed,1,.3,2);
      if(typeof input.compact==='boolean')appearance.compact=input.compact;
      if(typeof input.blur==='boolean')appearance.blur=input.blur;
      if(typeof input.cover3d==='boolean')appearance.cover3d=input.cover3d;
      if(input.coverKind==='vinyl'||input.coverKind==='cd')appearance.coverKind=input.coverKind;
      if(input.waveStyle==='silk'||input.waveStyle==='particles'||input.waveStyle==='bloom')appearance.waveStyle=input.waveStyle;
      if(Object.keys(appearance).length)result.appearance=appearance;
    }
    return result;
  }catch{return {};}
}

export function readPendingSettings(userId:string):SettingsPatch {try{return normalizeSettingsPatch(JSON.parse(localStorage.getItem(pendingKey(userId))||'null'));}catch{return {};}}

export const getAppearancePresets=():{id:string;name:string;description:string;mode:'light'|'dark';colors:PaletteColors}[]=>[
  {id:'paper',name:'Paper',description:t('copy.725'),mode:'light',colors:defaultAppearance.light},
  {id:'midnight',name:'Midnight',description:t('copy.726'),mode:'dark',colors:{bg:'#202423',surface:'#2c312f',ink:'#edece2',accent:'#a4b59c'}},
  {id:'sage',name:'Sage',description:t('copy.727'),mode:'light',colors:{bg:'#e5e9dd',surface:'#f2f4eb',ink:'#323f35',accent:'#7d9574'}},
  {id:'lilac',name:'Lilac',description:t('copy.728'),mode:'light',colors:{bg:'#eae5ed',surface:'#f6f1f8',ink:'#44394b',accent:'#aa89b7'}},
];
export const accentSwatches=['#a08369','#b1a2de','#9bb99a','#7ca8bb','#d2939c','#dbb976','#df9978'];

export function applyAppearance(appearance:Appearance,mode:PaletteMode,motion:boolean) {
  const root=document.documentElement,colors=appearance[mode];
  for(const key of ['bg','surface','ink','accent'] as const)root.style.setProperty(`--${key}`,colors[key]);
  root.style.setProperty('--muted',`color-mix(in srgb,${colors.ink} 70%,${colors.bg})`);
  root.style.setProperty('--line',`color-mix(in srgb,${colors.ink} 11%,transparent)`);
  root.style.setProperty('--accent-soft',`color-mix(in srgb,${colors.accent} 18%,${colors.bg})`);
  root.style.setProperty('--player',`color-mix(in srgb,${colors.surface} 94%,${colors.ink})`);
  root.style.setProperty('--radius',`${appearance.radius}px`);root.style.setProperty('--motion-speed',String(appearance.speed));root.style.setProperty('--motion-duration',`${220/appearance.speed}ms`);
  root.dataset.theme=mode;root.dataset.motion=motion?'full':'reduce';root.dataset.blur=String(appearance.blur);root.dataset.compact=String(appearance.compact);root.style.colorScheme=mode==='amoled'?'dark':mode;
  document.body.classList.toggle('compact',appearance.compact);document.body.classList.toggle('soft-blur',appearance.blur);
  document.querySelector('meta[name="theme-color"]')?.setAttribute('content',colors.bg);
}
