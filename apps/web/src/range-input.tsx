import type { CSSProperties, InputHTMLAttributes } from 'react';

export function rangeProgress(value:unknown,min:unknown=0,max:unknown=100){
 const lower=Number(min),upper=Number(max),position=Number(value);
 if(!Number.isFinite(position)||!Number.isFinite(lower)||!Number.isFinite(upper)||upper<=lower)return 0;
 return Math.max(0,Math.min(100,(position-lower)/(upper-lower)*100));
}

/** Native keyboard and touch behavior, with one theme-aware track everywhere. */
export function RangeInput({value,min=0,max=100,style,className='',...props}:Omit<InputHTMLAttributes<HTMLInputElement>,'type'>){
 const progress=`${rangeProgress(value,min,max)}%`;
 return <input {...props} type="range" min={min} max={max} value={value} className={`wave-range ${className}`} style={{...style,'--range-progress':progress,'--progress':progress} as CSSProperties}/>;
}
