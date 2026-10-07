import { createContext, useContext, useEffect, useSyncExternalStore, type ReactNode } from 'react';
import en from './locales/en.json';
import ru from './locales/ru.json';
import kk from './locales/kk.json';
import uk from './locales/uk.json';
import de from './locales/de.json';
import es from './locales/es.json';
export const languages=[{code:'en',name:'English'},{code:'ru',name:'Русский'},{code:'kk',name:'Қазақша'},{code:'uk',name:'Українська'},{code:'de',name:'Deutsch'},{code:'es',name:'Español'}] as const;
export type Language=typeof languages[number]['code'];
export type LanguageChoice=Language|'auto';
export type LocaleResponse={language:Language;country:string|null;source:'ip'|'browser'|'default'};
export const isLanguage=(value:unknown):value is Language=>languages.some(item=>item.code===value);
export const isLanguageChoice=(value:unknown):value is LanguageChoice=>value==='auto'||isLanguage(value);
const catalogs:Record<Language,Record<string,string>>={en,ru,kk,uk,de,es};
const browserLanguage=():Language=>{for(const value of navigator.languages||[navigator.language]){const code=value.split('-')[0].toLowerCase();if(isLanguage(code))return code;}return 'en';};
export function readLanguageChoice():LanguageChoice{try{const value=localStorage.getItem('gw-language-choice');return isLanguageChoice(value)?value:'auto';}catch{return 'auto';}}
let automatic:LocaleResponse={language:browserLanguage(),country:null,source:'browser'};
let choice=readLanguageChoice(),snapshot={choice,language:choice==='auto'?automatic.language:choice,country:automatic.country,source:automatic.source};
const listeners=new Set<()=>void>();
const publish=()=>{const language=choice==='auto'?automatic.language:choice;if(snapshot.choice===choice&&snapshot.language===language&&snapshot.country===automatic.country&&snapshot.source===automatic.source)return;snapshot={choice,language,country:automatic.country,source:automatic.source};listeners.forEach(listener=>listener());};
export const getLanguage=()=>snapshot.language;
export const getLanguageChoice=()=>snapshot.choice;
export function setLanguageChoice(next:LanguageChoice){choice=next;try{localStorage.setItem('gw-language-choice',next);}catch{/* Current tab still switches. */}publish();}
export function t(key:string,values:Record<string,string|number|undefined>={}){const text=catalogs[getLanguage()][key]??catalogs.en[key]??key;return text.replace(/\{(\w+)\}/g,(_,name)=>String(values[name]??`{${name}}`));}
export const number=(value:number,options:Intl.NumberFormatOptions={})=>new Intl.NumberFormat(getLanguage(),options).format(value);
export const date=(value:string|number|Date,options:Intl.DateTimeFormatOptions={})=>new Intl.DateTimeFormat(getLanguage(),options).format(new Date(value));
export function countLabel(count:number,kind:'tracks'|'files'|'members'|'playlists'='tracks'){
 const category=new Intl.PluralRules(getLanguage()).select(count),key=`count.${kind}.${category}`;
 const label=catalogs[getLanguage()][key]??catalogs[getLanguage()][`count.${kind}.other`]??catalogs.en[`count.${kind}.other`];return `${number(count)} ${label}`;
}
const Context=createContext(snapshot);
export function LocaleProvider({children}:{children:ReactNode}){
 const state=useSyncExternalStore(callback=>{listeners.add(callback);return()=>listeners.delete(callback);},()=>snapshot);
 useEffect(()=>{document.documentElement.lang=state.language;},[state.language]);
 useEffect(()=>{if(state.choice!=='auto')return;const controller=new AbortController();void fetch('/api/locale',{credentials:'include',headers:{'Accept-Language':browserLanguage()},signal:controller.signal}).then(response=>{if(!response.ok)throw new Error();return response.json();}).then((result:LocaleResponse)=>{if(!controller.signal.aborted&&choice==='auto'&&isLanguage(result.language)){automatic=result;publish();}}).catch(()=>{});return()=>controller.abort();},[state.choice]);
 useEffect(()=>{const changed=(event:StorageEvent)=>{if(event.key==='gw-language-choice')setLanguageChoice(readLanguageChoice());};window.addEventListener('storage',changed);return()=>window.removeEventListener('storage',changed);},[]);
 return <Context.Provider value={state}>{children}</Context.Provider>;
}
export function useLocale(){return useContext(Context);}
export function LanguagePicker({value,onChange,className=''}:{value?:LanguageChoice;onChange?:(language:LanguageChoice)=>void;className?:string}){
 const state=useLocale();return <label className={`language-picker ${className}`}><span>{t('language.title')}</span><select aria-label={t('language.label')} value={value??state.choice} onChange={event=>{const next=event.target.value;if(isLanguageChoice(next))(onChange??setLanguageChoice)(next);}}><option value="auto">{t('language.auto')}</option>{languages.map(item=><option value={item.code} key={item.code}>{item.name}</option>)}</select></label>;
}
