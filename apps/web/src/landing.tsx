import { useEffect, useRef, useState } from 'react';
import { ArrowDown, ArrowDownToLine, ArrowRight, ArrowUpRight, Disc3, Globe, Monitor, Smartphone, Users, Waves } from 'lucide-react';
import { BrandGraphic as Brand } from './ui';
import { api, ApiError } from './api';
import { getLanguageChoice, LanguagePicker, t, useLocale, setLanguageChoice, date, type LanguageChoice } from './locale';
import { createSilkWave } from './wave-silk';
import { BLOOM } from './wave-math';
import { bytes, type Config, type Settings, type User } from './types';
import { mergeSettings, readLocalSettings, readPendingSettings, writeLocalSettings, writePendingSettings } from './preferences';
import './landing.css';
type Release={platform:'android'|'windows'|'ios';version:string;channel:'beta'|'stable';bytes:number;sha256:string;builtAt:string;url:string;available:true;signature:'debug'|'release';format?:'installer'|'portable'};
function StudioWave(){
 const canvas=useRef<HTMLCanvasElement>(null);
 useEffect(()=>{const element=canvas.current;if(!element)return;const renderer=createSilkWave(element),fallback=renderer?null:element.getContext('2d'),motion=matchMedia('(prefers-reduced-motion: reduce)');let frame=0,visible=true,last=0,phase=BLOOM.phase as number;const draw=(now:number)=>{if(document.hidden||!visible)return;if(last&&now-last<1000/24&&!motion.matches){frame=requestAnimationFrame(draw);return;}const rect=element.getBoundingClientRect(),width=rect.width,height=rect.height,scale=Math.min(devicePixelRatio||1,1.5);if(element.width!==Math.round(width*scale)||element.height!==Math.round(height*scale)){element.width=Math.round(width*scale);element.height=Math.round(height*scale);}if(!motion.matches&&last)phase+=Math.min(.07,(now-last)/1000)*.65;last=now;const value={width,height,phase,energy:0,pointer:{x:.5,y:.5,active:0},tint:'#b9997b',background:'#302f2c'};if(!renderer?.draw(value)&&fallback){fallback.setTransform(scale,0,0,scale,0,0);fallback.clearRect(0,0,width,height);for(let line=0;line<46;line++){fallback.beginPath();for(let x=0;x<=width;x+=4){const u=x/width,y=height*.5+Math.sin(u*9+phase*.3+line/23)*Math.sin(u*Math.PI)*height*.27;x?fallback.lineTo(x,y):fallback.moveTo(x,y);}fallback.strokeStyle=`rgba(204,168,128,${.1+Math.sin(line/46*Math.PI)*.4})`;fallback.lineWidth=.8;fallback.stroke();}}if(!motion.matches)frame=requestAnimationFrame(draw);};const repaint=()=>{cancelAnimationFrame(frame);last=0;draw(performance.now());},observer=new IntersectionObserver(entries=>{visible=entries[0].isIntersecting;repaint();}),resize=new ResizeObserver(repaint);observer.observe(element);resize.observe(element);motion.addEventListener('change',repaint);document.addEventListener('visibilitychange',repaint);repaint();return()=>{cancelAnimationFrame(frame);renderer?.dispose();observer.disconnect();resize.disconnect();motion.removeEventListener('change',repaint);document.removeEventListener('visibilitychange',repaint);};},[]);
 return <canvas ref={canvas} className="studio-wave" aria-hidden="true"/>;
}
export function Landing(){
 const locale=useLocale(),[releases,setReleases]=useState<Release[]>([]),[status,setStatus]=useState<'loading'|'ready'|'error'>('loading'),[config,setConfig]=useState<Config|null>(null),[preview,setPreview]=useState(true),generation=useRef(0),languageFlight=useRef<AbortController|null>(null);
 const accountStamp=()=>localStorage.getItem('gw-user');
 const refresh=()=>{setStatus('loading');void api<{releases:Release[]}>('/releases').then(result=>{setReleases(result.releases.filter(release=>release.available&&release.url.startsWith('/api/downloads/')));setStatus('ready');}).catch(()=>setStatus('error'));};
 useEffect(()=>{refresh();void api<Config>('/config').then(setConfig).catch(()=>{});if(import.meta.env.PROD&&'serviceWorker'in navigator)void navigator.serviceWorker.register('/sw.js').catch(()=>{});},[]);
 useEffect(()=>{
  const revision=generation.current,stamp=accountStamp(),controller=new AbortController();
  const current=()=>!controller.signal.aborted&&revision===generation.current&&stamp===accountStamp();
  // The account preference wins on arrival, unless this visitor has since chosen a language.
  void api<{user:User|null}>('/auth/me',{signal:controller.signal}).then(async result=>{
   if(!result.user||!current())return;
   const id=result.user.id,payload=await api<{settings:Settings}>('/settings',{signal:controller.signal});
   if(!current())return;
   const session=await api<{user:User|null}>('/auth/me',{signal:controller.signal});
   if(!current()||session.user?.id!==id)return;
   const language=readPendingSettings(id).language??payload.settings.language;
   setLanguageChoice(language);writeLocalSettings(id,mergeSettings(readLocalSettings(id),{language}));
  }).catch(()=>{});
  const changed=(event:StorageEvent)=>{if(event.key==='gw-user'){generation.current++;controller.abort();languageFlight.current?.abort();}};
  window.addEventListener('storage',changed);
  return()=>{generation.current++;controller.abort();languageFlight.current?.abort();window.removeEventListener('storage',changed);};
 },[]);
 useEffect(()=>{document.title=t('landing.metaTitle');document.querySelector('meta[name="description"]')?.setAttribute('content',t('landing.metaDescription'));},[locale.language]);
 useEffect(()=>{let canonical=document.querySelector<HTMLLinkElement>('link[rel="canonical"]');try{const url=new URL(config?.appUrl||'');if(!['http:','https:'].includes(url.protocol)||['localhost','127.0.0.1','0.0.0.0'].includes(url.hostname)||/^192\.168\.|^10\./.test(url.hostname))return;canonical??=document.createElement('link');canonical.rel='canonical';canonical.href=new URL('/',url).href;document.head.appendChild(canonical);}catch{/* Local development has no public canonical. */}},[config?.appUrl]);
 const choose=(language:LanguageChoice)=>{
  const revision=++generation.current,stamp=accountStamp(),controller=new AbortController();languageFlight.current?.abort();languageFlight.current=controller;
  const current=()=>!controller.signal.aborted&&revision===generation.current&&stamp===accountStamp();
  setLanguageChoice(language);writeLocalSettings(null,mergeSettings(readLocalSettings(null),{language}));
  void api<{user:User|null}>('/auth/me',{signal:controller.signal}).then(async result=>{
   if(!result.user||!current())return;
   const id=result.user.id,previous=readPendingSettings(id).language;
   writeLocalSettings(id,mergeSettings(readLocalSettings(id),{language}));writePendingSettings(id,{...readPendingSettings(id),language});
   try{
    await api('/settings',{method:'PATCH',headers:{'X-GlukWave-Account':id},body:JSON.stringify({language}),signal:controller.signal});
    if(current()&&getLanguageChoice()===language){const remaining=readPendingSettings(id);if(remaining.language===language)delete remaining.language;writePendingSettings(id,remaining);}
   }catch(error){
    if(error instanceof ApiError&&error.code==='SESSION_CHANGED'&&current()){
     const remaining=readPendingSettings(id);if(remaining.language===language){if(previous===undefined)delete remaining.language;else remaining.language=previous;}writePendingSettings(id,remaining);
    }
    // Network failures retain a choice scoped to the original account for the next sync.
   }
  }).catch(()=>{});
 };
 return <div className="public-site"><a className="skip-link" href="#site-content">{t('copy.180')}</a><header className="site-header"><a href="/" aria-label={t('copy.181')}><Brand animated={false}/></a><div><LanguagePicker onChange={choose}/><a href="/app/" className="site-open">{t('landing.open')}<ArrowUpRight size={17}/></a></div></header><main id="site-content" className="site-main"><section className="site-intro"><p className="eyebrow">{t('landing.eyebrow')}</p><h1>{t('landing.title1')}<br/><span>{t('landing.title2')}</span></h1><div className="site-intro-bottom"><p>{t('landing.intro')}</p><div className="site-actions"><a href="/app/" className="site-primary">{t('landing.open')}<ArrowRight size={19}/></a><a href="#get-glukwave" className="site-secondary">{t('landing.downloads')}<ArrowDown size={18}/></a><small>{t('landing.browserNote')}</small></div></div></section><section className="studio-stage" aria-label={t('landing.waveCaption')}><StudioWave/><div className="studio-top"><span>{t('landing.waveCaption')}</span><span>GLUKWAVE / ∞</span></div><p className="studio-signature">{t('landing.signature1')}<br/><b>{t('landing.signature2')}</b></p><div className="studio-bottom"><span>{t('landing.footer')}</span><Waves size={22}/></div></section>{preview&&<figure className="site-preview"><div className="site-preview-frame"><span className="site-preview-bar"><i/><i/><i/><b>glukwave / app</b></span><img src="/brand/app-preview.png" alt={t('landing.previewAlt')} loading="lazy" width="1280" height="900" onError={()=>setPreview(false)}/></div><figcaption><b>{t('landing.preview')}</b><span>{t('landing.previewNote')}</span><a href="/app/" aria-label={t('landing.open')}><ArrowUpRight size={21}/></a></figcaption></figure>}<section className="site-features"><div className="site-feature-intro"><p className="eyebrow">{t('copy.182')}</p><h2>{t('landing.benefitTitle')}</h2><p>{t('landing.benefitIntro')}</p></div><div className="site-feature-list">{[['01','library',Disc3],['02','together',Users],['03','space',Waves]].map(([id,key,Icon])=>{const Symbol=Icon as typeof Disc3;return <article key={String(id)}><span className="feature-number">{String(id)}</span><div><h3>{t(`landing.${key}Title`)}</h3><p>{t(`landing.${key}Text`)}</p></div><Symbol size={23}/></article>;})}</div></section><section id="get-glukwave" className="site-downloads"><div className="site-downloads-heading"><p className="eyebrow">{t('landing.downloads')}</p><h2>{t('landing.platformTitle')}</h2><p>{t('landing.platformIntro')}</p></div><div className="platform-list"><article><Globe size={25}/><div><h3>Web</h3><p>{t('landing.available')}</p></div><a href="/app/">{t('landing.open')}<ArrowUpRight size={18}/></a></article>{(['android','windows','ios'] as const).map(platform=>{const release=releases.find(item=>item.platform===platform),name=platform==='android'?'Android':platform==='windows'?'Windows':'iOS';return <article key={platform}>{platform==='windows'?<Monitor size={25}/>:<Smartphone size={25}/>}<div><h3>{name}</h3>{platform==='windows'&&release?.format==='installer'&&<small>{t('landing.installer')}</small>}<p>{release?`${release.version} · ${bytes(release.bytes)}${release.channel==='beta'||release.signature==='debug'?` · ${t('landing.beta')}`:''}`:status==='loading'?t('landing.loading'):t('landing.unavailable')}</p>{release&&<small>{date(release.builtAt,{year:'numeric',month:'short',day:'numeric'})}</small>}</div>{release&&<a href={release.url} download aria-label={t('landing.downloadPlatform',{platform:name})}>{t('copy.749')}<ArrowDownToLine size={18}/></a>}</article>;})}</div>{status==='error'&&<div className="site-release-error" role="status"><p>{t('landing.releaseError')}</p><button onClick={refresh}>{t('copy.129')}</button></div>}</section><section className="site-faq"><h2>{t('landing.faqTitle')}</h2><div>{['Offline','Account','Sources'].map(key=><details key={key}><summary>{t(`landing.faq${key}Q`)}<span>+</span></summary><p>{t(`landing.faq${key}A`)}</p></details>)}</div></section></main><footer className="site-footer"><a href="/" aria-label={t('copy.181')}><Brand animated={false}/></a><p>{t('landing.footer')}</p><a href="/app/#settings">{t('copy.023')}<ArrowUpRight size={14}/></a><span>© {new Date().getFullYear()} GlukWave</span></footer></div>;
}



