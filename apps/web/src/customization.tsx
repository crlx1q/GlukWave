import { t, useLocale } from './locale';
import { useEffect, useState, type CSSProperties } from 'react';
import { Check, Monitor, Moon, Palette, RotateCcw, Sun, Waves } from 'lucide-react';
import { useStore } from './store';
import { usePlayer } from './player';
import { accentSwatches, getAppearancePresets } from './preferences';
import { defaultAppearance, type AppearancePatch, type PaletteColors } from './types';
import { Art, Brand, Toggle } from './ui';
import { WaveVisual } from './wave';

function contrast(a:string,b:string){const luminance=(hex:string)=>{const rgb=[1,3,5].map(index=>parseInt(hex.slice(index,index+2),16)/255).map(value=>value<=.04045?value/12.92:((value+.055)/1.055)**2.4);return rgb[0]*.2126+rgb[1]*.7152+rgb[2]*.0722;};const x=luminance(a),y=luminance(b);return (Math.max(x,y)+.05)/(Math.min(x,y)+.05);}
function ColorField({label,value,onChange}:{label:string;value:string;onChange:(color:string)=>void}) {useLocale();
  const [text,setText]=useState(value);useEffect(()=>setText(value),[value]);
  return <label className="appearance-color-field"><span>{label}</span><div><input type="color" value={value} onChange={event=>onChange(event.target.value)} aria-label={t('template.005', {v0: label})}/><input type="text" value={text} maxLength={7} spellCheck={false} autoComplete="off" aria-label={`HEX: ${label}`} onChange={event=>{const next=event.target.value;setText(next);if(/^#[\da-f]{6}$/i.test(next))onChange(next.toLowerCase());}} onBlur={()=>setText(value)}/></div></label>;
}

export function AppearanceSettings() {useLocale();
  const store=useStore(),player=usePlayer(),[editingMode,setEditingMode]=useState<'light'|'dark'>(store.resolvedTheme),appearance=store.settings.appearance,colors=appearance[editingMode];
  useEffect(()=>setEditingMode(store.resolvedTheme),[store.resolvedTheme]);
  const saveAppearance=(partial:AppearancePatch)=>void store.saveSettings({appearance:partial});
  const saveColor=(key:keyof PaletteColors,value:string)=>saveAppearance({[editingMode]:{[key]:value}});
  const reset=()=>{void store.saveSettings({appearance:{[editingMode]:defaultAppearance[editingMode],radius:24,speed:1,compact:false,blur:true,waveStyle:'silk'},reducedMotion:false});store.notify(t('copy.332'));};
  const textContrast=Math.min(contrast(colors.ink,colors.bg),contrast(colors.ink,colors.surface));
  const previewStyle={'--preview-bg':colors.bg,'--preview-surface':colors.surface,'--preview-ink':colors.ink,'--preview-accent':colors.accent,'--preview-radius':`${appearance.radius}px`} as CSSProperties;
  return <section id="appearance-settings" className="settings-section appearance-section">
    <div className="settings-title appearance-title"><Palette size={20}/><h2>{t('copy.003')}</h2><span className={`appearance-save-state ${store.settingsSync}`} role="status">{store.user?(store.settingsSync==='saving'?t('copy.333'):store.settingsSync==='saved'?t('copy.334'):t('copy.335')):t('copy.336')}</span></div>
    <div className="appearance-layout">
      <div className="appearance-controls">
        <h3 className="appearance-setting-title">{t('copy.337')}</h3>
        <div className="appearance-modes">{([['light',t('copy.338'),Sun],['dark',t('copy.339'),Moon],['system',t('copy.340'),Monitor]] as const).map(([mode,label,Icon])=><button type="button" key={mode} aria-pressed={store.settings.theme===mode} className={store.settings.theme===mode?'selected':''} onClick={()=>{void store.saveSettings({theme:mode});setEditingMode(mode==='system'?(matchMedia('(prefers-color-scheme: dark)').matches?'dark':'light'):mode);}}><Icon size={17}/><span>{label}</span>{store.settings.theme===mode&&<Check size={14}/>}</button>)}</div>
        <div className="appearance-presets">{getAppearancePresets().map(preset=><button type="button" className={preset.mode===editingMode&&Object.keys(preset.colors).every(key=>preset.colors[key as keyof PaletteColors]===colors[key as keyof PaletteColors])?'selected':''} key={preset.id} aria-label={t('template.006', {v0: preset.name})} onClick={()=>{setEditingMode(preset.mode);void store.saveSettings({theme:preset.mode,appearance:{[preset.mode]:preset.colors}});}}><span className="appearance-preset-sample" style={{background:preset.colors.bg,color:preset.colors.ink,'--sample-surface':preset.colors.surface,'--sample-accent':preset.colors.accent} as CSSProperties}><i/><b/><em/></span><b>{preset.name}</b><small>{preset.description}</small></button>)}</div>
        <div className="appearance-palette-heading"><h3 className="appearance-setting-title">{t('copy.341')}</h3><div className="appearance-palette-tabs" aria-label={t('copy.342')}>{(['light','dark'] as const).map(mode=><button type="button" key={mode} aria-pressed={editingMode===mode} className={editingMode===mode?'selected':''} onClick={()=>setEditingMode(mode)}>{mode==='light'?t('copy.338'):t('copy.339')}</button>)}</div></div>
        <p className="appearance-note">{t('copy.343')}</p>
        <div className="appearance-swatches">{accentSwatches.map(accent=><button type="button" className={colors.accent===accent?'selected':''} key={accent} aria-label={t('template.007', {v0: accent})} aria-pressed={colors.accent===accent} style={{background:accent}} onClick={()=>saveColor('accent',accent)}>{colors.accent===accent&&<Check size={14}/>}</button>)}</div>
        <ColorField label={t('copy.344')} value={colors.accent} onChange={value=>saveColor('accent',value)}/>
        <details className="appearance-custom-colors"><summary>{t('copy.345')}<span>+</span></summary><div className="appearance-color-grid">{([['bg',t('copy.346')],['surface',t('copy.347')],['ink',t('copy.348')]] as const).map(([key,label])=><ColorField key={key} label={label} value={colors[key]} onChange={value=>saveColor(key,value)}/>)}</div></details>
        {textContrast<4.5&&<p className="appearance-contrast-note" role="status">{t('copy.349')}</p>}
        <h3 className="appearance-setting-title visualizer-title">{t('copy.350')}</h3><div className="appearance-wave-options">{([['silk',t('copy.351')],['particles',t('copy.352')],['bloom','Bloom']] as const).map(([style,label])=><button type="button" key={style} aria-pressed={appearance.waveStyle===style} className={appearance.waveStyle===style?'selected':''} onClick={()=>saveAppearance({waveStyle:style})}><Waves size={16}/>{label}</button>)}</div>
        <label className="appearance-range"><span>{t('copy.353')}<output>{appearance.radius} px</output></span><input type="range" min={8} max={38} value={appearance.radius} aria-label={t('copy.353')} onChange={event=>saveAppearance({radius:Number(event.target.value)})}/></label>
        <label className="appearance-range"><span>{t('copy.354')}<output>{appearance.speed.toFixed(1)}×</output></span><input type="range" min={.3} max={2} step={.1} value={appearance.speed} aria-label={t('copy.354')} onChange={event=>saveAppearance({speed:Number(event.target.value)})}/></label>
        <Toggle checked={!store.settings.reducedMotion} onChange={enabled=>void store.saveSettings({reducedMotion:!enabled})} label={t('copy.355')} description={store.motion?t('copy.356'):store.settings.reducedMotion?t('copy.357'):t('copy.358')}/>
        <Toggle checked={appearance.blur} onChange={blur=>saveAppearance({blur})} label={t('copy.359')} description={t('copy.360')}/>
        <Toggle checked={appearance.compact} onChange={compact=>saveAppearance({compact})} label={t('copy.361')} description={t('copy.362')}/>
        <Toggle checked={store.settings.lyrics} onChange={lyrics=>void store.saveSettings({lyrics})} label={t('copy.046')} description={t('copy.363')}/>
        <button type="button" className="subtle-button appearance-reset" onClick={reset}><RotateCcw size={15}/>{t('copy.364')}</button>
      </div>
      <aside className="appearance-preview-column"><p className="appearance-preview-label">{t('copy.365')}</p><div className={`appearance-preview ${appearance.compact?'dense':''}`} style={previewStyle}><div className="appearance-preview-top"><Brand animated={false}/><span className="appearance-preview-avatar">{store.user?.displayName.slice(0,1)||'G'}</span></div><h3>{store.user?t('template.008', {v0: store.user.displayName}):t('copy.366')}</h3><p>{t('copy.367')}</p><div className="appearance-preview-hero"><WaveVisual className="appearance-preview-wave" color={colors.accent} waveStyle={appearance.waveStyle} speed={appearance.speed}/><b>{t('copy.368')}<span>.</span></b><small>{t('copy.369')}</small><span className="appearance-preview-play" aria-hidden="true">▶</span></div><div className="appearance-preview-tiles" aria-hidden="true"><span/><span/></div><div className="appearance-preview-player"><Art track={player.track||undefined}/><span><b>{player.track?.title||t('copy.370')}</b><small>{player.track?.artist||t('copy.371')}</small></span><span aria-hidden="true">{player.state.playing?'Ⅱ':'▶'}</span></div></div><p className="appearance-preview-caption">{t('copy.372')}{' '}{store.settings.theme==='system'?t('copy.373'):t('copy.374')}</p></aside>
    </div>
  </section>;
}
