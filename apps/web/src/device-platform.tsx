import {Globe,Monitor,Smartphone} from 'lucide-react';
import {t} from './locale';
export function platformLabel(kind:string){
  return t(kind==='web'?'ecosystem.web':kind==='windows'?'ecosystem.windows':kind==='android'?'ecosystem.android':kind==='ios'?'ecosystem.ios':'ecosystem.desktop');
}
export function DevicePlatformIcon({kind,size=23}:{kind:string;size?:number}){
  return kind==='web'?<Globe size={size}/>:kind==='android'||kind==='ios'?<Smartphone size={size}/>:<Monitor size={size}/>;
}
