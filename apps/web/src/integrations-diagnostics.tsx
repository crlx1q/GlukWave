import {useEffect,useState} from 'react';
import {RefreshCw} from 'lucide-react';
import {api,errorText} from './api';
import {t,useLocale} from './locale';
import {Loading,SourceMark} from './ui';
import {sourceNames,type Source} from './types';
type Diagnostic={id:string;loginAvailable:boolean;searchAvailable:boolean;redirectUri:string;issues:string[]};
export function IntegrationsDiagnostics(){
 useLocale();const [items,setItems]=useState<Diagnostic[]>([]),[loading,setLoading]=useState(true),[error,setError]=useState('');
 const refresh=async()=>{setLoading(true);try{const result=await api<{providers:Diagnostic[]}>('/admin/integrations/diagnostics');setItems(result.providers);setError('');}catch(error){setError(errorText(error));}finally{setLoading(false);}};
 useEffect(()=>{void refresh();},[]);
 return <section className="admin-section"><div className="section-heading"><h2>{t('ecosystem.diagnostics')}</h2><button className="subtle-button" disabled={loading} onClick={()=>void refresh()}><RefreshCw size={15}/>{t('copy.129')}</button></div><p className="settings-note">{t('ecosystem.diagnosticsCaption')}</p>{error&&<p className="ecosystem-inline-error" role="alert">{error}</p>}{loading&&!items.length?<Loading/>:<div className="diagnostic-providers">{items.map(item=><article key={item.id} className="diagnostic-provider"><header><h3>{(['soundcloud','spotify','yandex','youtube'] as string[]).includes(item.id)&&<SourceMark source={item.id as Source}/>} {sourceNames[item.id as Source]||item.id}</h3><span className="connection-status"><i className={`status-dot ${item.loginAvailable?'':'offline'}`}/>{t(item.loginAvailable?'ecosystem.loginAvailable':'ecosystem.loginUnavailable')}</span></header>{item.redirectUri&&<code>{item.redirectUri}</code>}{item.issues.length>0&&<ul>{item.issues.map(issue=><li key={issue}>{issue}</li>)}</ul>}</article>)}</div>}</section>;
}
