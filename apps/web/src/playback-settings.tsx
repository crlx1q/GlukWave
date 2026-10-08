import { t, useLocale } from './locale';
import { Disc3, RotateCcw, SlidersHorizontal, Volume2 } from 'lucide-react';
import { EQ_FREQUENCIES, EQ_PRESETS } from './audio-processing';
import { usePlayer } from './player';
import { useStore } from './store';
import { Toggle } from './ui';
import { ContinuousRange } from './continuous-range';

export function PlaybackSettings(){useLocale();
 const store=useStore(),player=usePlayer(),eq=store.settings.equalizer,preset=EQ_PRESETS.find(item=>item.preamp===eq.preamp&&item.bands.every((value,index)=>value===eq.bands[index]));
 const frequency=(value:number)=>value>=1000?`${value/1000}k`:`${value}`;
 const db=(value:number)=>`${value>0?'+':''}${value.toFixed(1)} dB`;
 const reset=()=>void store.saveSettings({equalizer:{bands:[...EQ_PRESETS[0].bands],preamp:EQ_PRESETS[0].preamp}});
 return <>
  <section className="settings-section playback-section"><div className="settings-title"><SlidersHorizontal size={20}/><h2>{t('v7.eq.title')}</h2><span className={`audio-availability ${player.equalizerAvailable?'available':''}`}>{player.equalizerAvailable?t('v7.eq.active'):t('v7.eq.audioOnly')}</span></div>
   <Toggle checked={eq.enabled} onChange={enabled=>void store.saveSettings({equalizer:{enabled}})} label={t('v7.eq.enable')} description={t('v7.eq.enableCaption')}/>
   <div className="equalizer-toolbar"><label><span>{t('v7.eq.preset')}</span><select value={preset?.id||'custom'} aria-label={t('v7.eq.preset')} onChange={event=>{const selected=EQ_PRESETS.find(item=>item.id===event.target.value);if(selected)void store.saveSettings({equalizer:{enabled:true,bands:[...selected.bands],preamp:selected.preamp}});}}><option value="custom" disabled>{t('v7.eq.custom')}</option>{EQ_PRESETS.map(item=><option value={item.id} key={item.id}>{t(`v7.eq.${item.id}`)}</option>)}</select></label><button className="text-button" onClick={reset}><RotateCcw size={15}/>{t('v7.eq.reset')}</button></div>
   <div className={`equalizer-bands ${eq.enabled?'enabled':''}`} role="group" aria-label={t('v7.eq.bands')}><div className="equalizer-scale" aria-hidden="true"><span>+12</span><span>0</span><span>−12</span></div>{EQ_FREQUENCIES.map((hz,index)=><label className="equalizer-band" key={hz}><output>{eq.bands[index]>0?'+':''}{eq.bands[index]}</output><input type="range" min={-12} max={12} step={.5} value={eq.bands[index]} aria-label={t('v7.eq.bandLabel',{hz})} aria-valuetext={db(eq.bands[index])} disabled={!eq.enabled} onChange={event=>{const bands=[...eq.bands];bands[index]=Number(event.target.value);void store.saveSettings({equalizer:{bands}});}}/><span>{frequency(hz)}</span></label>)}</div>
   <label className="settings-row equalizer-preamp"><span><b>{t('v7.eq.preamp')}</b><small>{t('v7.eq.preampCaption')}</small></span><input type="range" min={-12} max={12} step={.5} disabled={!eq.enabled} value={eq.preamp} aria-label={t('v7.eq.preamp')} onChange={event=>void store.saveSettings({equalizer:{preamp:Number(event.target.value)}})}/><output>{db(eq.preamp)}</output></label>
   {!player.equalizerAvailable&&<p className="settings-note equalizer-source-note">{t('v7.eq.sourceNote')}</p>}
  </section>
  <section className="settings-section playback-section"><div className="settings-title"><Disc3 size={20}/><h2>{t('copy.005')}</h2></div>
   <label className="settings-row"><span><b>{t('v7.rate.title')}</b><small>{player.room?t('v7.rate.room'):t('v7.rate.caption')}</small></span><select value={player.room?1:store.settings.playbackRate} aria-label={t('v7.rate.title')} disabled={!!player.room||!player.equalizerAvailable} onChange={event=>void store.saveSettings({playbackRate:Number(event.target.value)})}>{[.5,.75,1,1.25,1.5,1.75,2].map(value=><option key={value} value={value}>{value}×</option>)}</select></label>
   <div className="settings-row"><span><b>{t('copy.054')}</b><small>{Math.round(player.state.volume*100)}%</small></span><Volume2 size={17}/><ContinuousRange value={player.state.volume} max={1} step={.01} label={t('copy.054')} onCommit={volume=>void player.command({command:'volume',volume})}/></div>
   <Toggle checked={store.settings.lyrics} onChange={lyrics=>void store.saveSettings({lyrics})} label={t('copy.046')} description={t('copy.047')}/>
   <Toggle checked={store.settings.appearance.cover3d} onChange={cover3d=>void store.saveSettings({appearance:{cover3d}})} label={t('copy.048')} description={t('copy.049')}/>
   <label className="settings-row"><span><b>{t('copy.050')}</b><small>{t('copy.051')}</small></span><select value={store.settings.appearance.coverKind} aria-label={t('copy.052')} onChange={event=>void store.saveSettings({appearance:{coverKind:event.target.value as 'vinyl'|'cd'}})}><option value="vinyl">{t('copy.053')}</option><option value="cd">CD</option></select></label>
   <p className="settings-note">{t('copy.055')}</p>
  </section>
 </>;
}
