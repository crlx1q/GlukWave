import {Chrome,Compass,Monitor,PanelsTopLeft,Smartphone} from 'lucide-react';
import {t} from './locale';
export function platformLabel(kind:string){
  return t(kind==='web'?'ecosystem.web':kind==='windows'?'ecosystem.windows':kind==='android'?'ecosystem.android':kind==='ios'?'ecosystem.ios':'ecosystem.desktop');
}
export function DevicePlatformIcon({kind,name='',size=23}:{kind:string;name?:string;size?:number}){
  const browser=/chrome|chromium/i.test(name)?Chrome:/safari/i.test(name)?Compass:PanelsTopLeft,Icon=kind==='web'?browser:kind==='android'||kind==='ios'?Smartphone:Monitor;
  return <Icon size={size} data-platform={kind==='web'&&browser===Chrome?'chrome':kind}/>;
}
